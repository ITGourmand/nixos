#!/usr/bin/env bash
# ==============================================================================
# sumu-run: A secure Bubblewrap-based sandbox wrapper for umu-run on NixOS
# ==============================================================================
set -euo pipefail

# Default configuration variables
ALLOW_NET=false
UNRESTRICTED=false
EXTRA_PATHS=()
UMU_ARGS=()

# CLI Argument Parser
while [[ $# -gt 0 ]]; do
    case "$1" in
        -i|--internet) 
            ALLOW_NET=true
            shift 
            ;;
        -a|--all) 
            UNRESTRICTED=true
            shift 
            ;;
        -p|--path)
            if [[ -z "${2:-}" ]]; then 
                echo "Error: --path requires an argument." >&2
                exit 1
            fi
            EXTRA_PATHS+=("$2")
            shift 2 
            ;;
        --) 
            shift
            UMU_ARGS=("$@")
            break 
            ;;
        -*) 
            echo "Unknown option: $1" >&2
            exit 1 
            ;;
        *) 
            UMU_ARGS=("$@")
            break 
            ;;
    esac
done

# Check if arguments were provided
if [[ ${#UMU_ARGS[@]} -eq 0 ]]; then
    echo "Usage: sumu-run [options] -- [umu-run arguments]"
    echo "Options:"
    echo "  -i, --internet       Allow network access"
    echo "  -p, --path <path>    Allow access to a specific directory/file (can be repeated)"
    echo "  -a, --all            Run umu-run normally without any sandboxing"
    exit 1
fi

# Bypass sandbox if requested
if [[ "$UNRESTRICTED" == true ]]; then
    exec umu-run "${UMU_ARGS[@]}"
fi

# Store the real HOME before bwrap overrides it
REAL_HOME="$HOME"

# Set up temporary directories
SANDBOX_HOME=$(mktemp -d /tmp/sumu-home.XXXXXX)
DBUS_PROXY_DIR=$(mktemp -d /tmp/sumu-dbus.XXXXXX)

# --- CRÉATION DE L'ARBORESCENCE FHS POUR NIXOS ---
# NixOS ne met pas les libs dans /usr/lib par défaut. 
# pressure-vessel a besoin d'une structure FHS pour trouver libvulkan/libGL.
FAKE_USR=$(mktemp -d /tmp/sumu-usr.XXXXXX)
mkdir -p "$FAKE_USR/lib" "$FAKE_USR/lib64" "$FAKE_USR/bin" "$FAKE_USR/share" "$FAKE_USR/etc"

# 1. Lier les librairies système de NixOS
if [[ -d /run/current-system/sw/lib ]]; then
    ln -s /run/current-system/sw/lib/* "$FAKE_USR/lib/" 2>/dev/null
fi
if [[ -d /run/current-system/sw/lib64 ]]; then
    ln -s /run/current-system/sw/lib64/* "$FAKE_USR/lib64/" 2>/dev/null
fi

# 2. Lier les pilotes graphiques (OpenGL, Vulkan, NVIDIA, etc.)
if [[ -d /run/opengl-driver-32/lib ]]; then
    ln -sf /run/opengl-driver-32/lib/* "$FAKE_USR/lib/" 2>/dev/null
fi
if [[ -d /run/opengl-driver/lib ]]; then
    ln -sf /run/opengl-driver/lib/* "$FAKE_USR/lib64/" 2>/dev/null
fi

# 3. Lier bin, share, etc depuis le profil système
if [[ -d /run/current-system/sw/bin ]]; then
    ln -s /run/current-system/sw/bin/* "$FAKE_USR/bin/" 2>/dev/null
fi
if [[ -d /run/current-system/sw/share ]]; then
    ln -s /run/current-system/sw/share/* "$FAKE_USR/share/" 2>/dev/null
fi
if [[ -d /run/current-system/sw/etc ]]; then
    ln -s /run/current-system/sw/etc/* "$FAKE_USR/etc/" 2>/dev/null
fi
# ------------------------------------------------

# Cleanup resources on script termination
cleanup() {
    rm -rf "$SANDBOX_HOME" "$DBUS_PROXY_DIR" "$FAKE_USR"
    if [[ -n "${DBUS_PROXY_PID:-}" ]] && kill -0 "$DBUS_PROXY_PID" 2>/dev/null; then
        kill "$DBUS_PROXY_PID" 2>/dev/null || true
    fi
}
trap cleanup EXIT

# 1. D-Bus Proxy Setup (if session bus is available)
REAL_XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
FAKE_DBUS_SOCKET="$DBUS_PROXY_DIR/bus"

if [[ -n "${DBUS_SESSION_BUS_ADDRESS:-}" && -S "$REAL_XDG_RUNTIME_DIR/bus" ]]; then
    xdg-dbus-proxy "$DBUS_SESSION_BUS_ADDRESS" "$FAKE_DBUS_SOCKET" --filter &
    DBUS_PROXY_PID=$!
    sleep 0.2
fi

# 2. Base Bubblewrap Arguments
BWRAP_ARGS=(
    bwrap
    --die-with-parent
    --new-session
    --unshare-uts
    --unshare-cgroup
)

if [[ "$ALLOW_NET" == false ]]; then
    BWRAP_ARGS+=(--unshare-net)
fi

# --- MINIMAL NIXOS ROOT DIRECTORY CONSTRUCTION ---
BWRAP_ARGS+=(
    --dir /
    --dev /dev
    --proc /proc
    --ro-bind /sys /sys
    
    # 1. Bare minimum paths for NixOS execution
    --ro-bind /nix /nix
    --tmpfs /run
    --ro-bind / /run/host
    --ro-bind /run/current-system /run/current-system
    --ro-bind-try /run/opengl-driver /run/opengl-driver
    --ro-bind-try /run/opengl-driver-32 /run/opengl-driver-32
    --ro-bind-try /run/systemd /run/systemd
    --ro-bind-try /run/user /run/user 
    
    # 2. Standard directory symlinks (utilisant notre FHS factice)
    --symlink /run/current-system/sw/bin /bin
    --symlink /run/current-system/sw/bin /sbin
    --bind "$FAKE_USR" /usr
    --bind "$FAKE_USR/lib" /lib
    --bind "$FAKE_USR/lib64" /lib64
    
    # 3. Prevent access to host's sensitive root directories
    --tmpfs /tmp
    --tmpfs /var
    --tmpfs /srv
    --tmpfs /boot
    --tmpfs /root
    --tmpfs /home
    --bind "$SANDBOX_HOME" "$HOME"
    
    # 4. Mock /etc layout
    --tmpfs /etc
    --symlink /run/current-system/sw/etc /etc/static
    --ro-bind-try /etc/os-release /etc/os-release
    --ro-bind-try /etc/NIXOS /etc/NIXOS
    --ro-bind-try /etc/passwd /etc/passwd
    --ro-bind-try /etc/group /etc/group
    --ro-bind-try /etc/hosts /etc/hosts
    --ro-bind-try /etc/nsswitch.conf /etc/nsswitch.conf
    --ro-bind-try /etc/machine-id /etc/machine-id
    --ro-bind-try /etc/localtime /etc/localtime
    --ro-bind-try /etc/ssl/certs /etc/ssl/certs
    --ro-bind-try /etc/fonts /etc/fonts
    
    # Fichiers de config pour ldconfig et GPU
    --ro-bind-try /etc/ld.so.conf /etc/ld.so.conf
    --ro-bind-try /etc/ld.so.cache /etc/ld.so.cache
    --ro-bind-try /etc/ld.so.conf.d /etc/ld.so.conf.d
    --ro-bind-try /etc/vulkan /etc/vulkan
    --ro-bind-try /etc/egl /etc/egl
    
    --symlink /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
    --symlink /proc/self/mounts /etc/mtab
)

# --- UMU-RUN EXCEPTIONS (Required for Proton to work) ---
BWRAP_ARGS+=(
    --bind-try "$PWD" "$PWD"
    --bind-try "$REAL_HOME/.local/share/Steam/compatibilitytools.d" "$REAL_HOME/.local/share/Steam/compatibilitytools.d"
    --bind-try "$REAL_HOME/.local/share/umu" "$REAL_HOME/.local/share/umu"
    --bind-try "$REAL_HOME/Games/umu" "$REAL_HOME/Games/umu"
    --bind-try "$REAL_HOME/.cache/umu" "$REAL_HOME/.cache/umu"
)
# --------------------------------------------------------

# 3. Hardware Acceleration (GPU Passthrough)
if [[ -d /dev/dri ]]; then
    BWRAP_ARGS+=(--dev-bind /dev/dri /dev/dri)
fi
for dev in /dev/nvidia0 /dev/nvidiactl /dev/nvidia-modeset /dev/nvidia-uvm /dev/nvidia-uvm-tools; do
    if [[ -e "$dev" ]]; then
        BWRAP_ARGS+=(--dev-bind "$dev" "$dev")
    fi
done

BWRAP_ARGS+=(--dev-bind /dev/shm /dev/shm)

# 4. Display (Wayland Forcé), Audio, and Filtered D-Bus Passthrough
WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}"

# Forcer Wayland natif, mais laisser Xwayland en fallback
# BWRAP_ARGS+=(--setenv PROTON_ENABLE_WAYLAND 1)

if [[ -n "${DISPLAY:-}" ]]; then
    BWRAP_ARGS+=(--setenv DISPLAY "$DISPLAY"
                 --ro-bind-try /tmp/.X11-unix /tmp/.X11-unix)
    
    # INDISPENSABLE : Partager le jeton d'authentification X11
    if [[ -n "${XAUTHORITY:-}" ]]; then
        BWRAP_ARGS+=(--setenv XAUTHORITY "$XAUTHORITY"
                     --ro-bind-try "$XAUTHORITY" "$XAUTHORITY")
    elif [[ -f "$REAL_HOME/.Xauthority" ]]; then
        BWRAP_ARGS+=(--ro-bind-try "$REAL_HOME/.Xauthority" "$REAL_HOME/.Xauthority")
    fi
fi

# Bind Filtered D-Bus
if [[ -S "$FAKE_DBUS_SOCKET" ]]; then
    BWRAP_ARGS+=(--bind "$FAKE_DBUS_SOCKET" "$REAL_XDG_RUNTIME_DIR/bus")
fi

# 5. User-provided custom path mounting
if [[ ${#EXTRA_PATHS[@]} -gt 0 ]]; then
    for p in "${EXTRA_PATHS[@]}"; do
        ABS_PATH=$(realpath -m "$p")
        if [[ -d "$ABS_PATH" ]]; then
            BWRAP_ARGS+=(--bind "$ABS_PATH" "$ABS_PATH")
        elif [[ -f "$ABS_PATH" ]]; then
            BWRAP_ARGS+=(--ro-bind "$ABS_PATH" "$ABS_PATH")
        else
            echo "Warning: Path '$p' does not exist, skipping." >&2
        fi
    done
fi

# 6. Execute
exec "${BWRAP_ARGS[@]}" umu-run "${UMU_ARGS[@]}"