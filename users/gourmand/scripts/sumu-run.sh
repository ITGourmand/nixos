#!/usr/bin/env bash
# ==============================================================================
# sumu-run: Secure Bubblewrap sandbox wrapper for umu-run / Proton on NixOS
# ==============================================================================
set -euo pipefail

# Default configuration
ALLOW_NET=false
ALLOW_X11=false
ALLOW_INPUT=false
UNRESTRICTED=false
KEEP_PREFIX=false
AUTO_DRIVES=true
MANUAL_DRIVES=()
DRIVE_MAP=()
PERSIST_PATHS=()
TEMP_PATHS=()
UMU_ARGS=()

usage() {
    cat <<EOF
Usage: sumu-run [options] -- [umu-run arguments]

Options:
  -i, --internet       Allow network access (e.g., for first launch / updates)
  -x, --x11            Allow access to X11 display server (discouraged if Wayland is available)
      --input          Expose /dev/input and /run/udev (required for gamepads/controllers)
  -k, --keep-prefix    Makes WINEPREFIX/umu caches PERSISTENT (saves retained).
                       By default, the prefix is a disposable overlay.
  -p, --path <path>    Mounts <path> for read/REAL-WRITE (persistent)
  -w, --workdir <path> Mounts <path> as a TEMPORARY overlay (writes are lost upon closing). Default: -w "."
  -D, --drive <L=/p>   Maps a Wine drive letter to <path> (mounted as persistent RW)
      --no-drives      Disables automatic drive letter creation for /mnt, /media, etc.
  -a, --all            Disable sandboxing (runs umu-run directly)
  -h, --help           Display this help message
EOF
    exit 1
}

# Parse CLI arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -i|--internet)    ALLOW_NET=true; shift ;;
        -x|--x11)         ALLOW_X11=true; shift ;;
        --input)          ALLOW_INPUT=true; shift ;;
        -k|--keep-prefix) KEEP_PREFIX=true; shift ;;
        -a|--all)         UNRESTRICTED=true; shift ;;
        --no-drives)      AUTO_DRIVES=false; shift ;;
        -D|--drive)
            [[ -z "${2:-}" ]] && { echo "Error: --drive requires LETTER=/path." >&2; exit 1; }
            [[ "$2" =~ ^[A-Za-z]=.+ ]] || { echo "Error: format attendu: -D G=/mnt/TO" >&2; exit 1; }
            drive_letter="${2%%=*}"
            drive_path="${2#*=}"
            MANUAL_DRIVES+=("${drive_letter,,}=$drive_path")
            PERSIST_PATHS+=("$(realpath -m -- "$drive_path")")
            shift 2 ;;
        -p|--path)
            [[ -z "${2:-}" ]] && { echo "Error: --path requires an argument." >&2; exit 1; }
            PERSIST_PATHS+=("$(realpath -m -- "$2")"); shift 2 ;;
        -w|--workdir)
            [[ -z "${2:-}" ]] && { echo "Error: --workdir requires an argument." >&2; exit 1; }
            TEMP_PATHS+=("$(realpath -m -- "$2")"); shift 2 ;;
        -h|--help) usage ;;
        --) shift; UMU_ARGS=("$@"); break ;;
        -*) echo "Unknown option: $1" >&2; exit 1 ;;
        *)  UMU_ARGS=("$@"); break ;;
    esac
done

[[ ${#UMU_ARGS[@]} -eq 0 ]] && usage

# --- BINARY RESOLUTION (NixOS / Home Manager Support) ---
UMU_BIN="$(type -P umu-run || true)"
[[ -z "$UMU_BIN" ]] && { echo "Error: umu-run not found in PATH." >&2; exit 127; }
UMU_BIN="$(readlink -f -- "$UMU_BIN")"

# Execute directly if unrestricted mode is enabled
if [[ "$UNRESTRICTED" == true ]]; then
    exec "$UMU_BIN" "${UMU_ARGS[@]}"
fi

BWRAP_BIN="$(type -P bwrap || true)"
[[ -z "$BWRAP_BIN" ]] && { echo "Error: bwrap (bubblewrap) not found." >&2; exit 127; }

# Bubblewrap setuid verification
if [[ -u "$BWRAP_BIN" ]]; then
    echo "Error: $BWRAP_BIN has the setuid bit set. Bubblewrap must run unprivileged." >&2
    exit 1
fi

# Détection du support --tmp-overlay par bwrap
HAS_TMP_OVERLAY=false
"$BWRAP_BIN" --help 2>&1 | grep -q -- '--tmp-overlay' && HAS_TMP_OVERLAY=true

XDG_DBUS_PROXY_BIN="$(type -P xdg-dbus-proxy || true)"

# Capture host environment
REAL_HOME="$HOME"
REAL_UID="$(id -u)"
REAL_XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$REAL_UID}"

if [[ ! -d "$REAL_XDG_RUNTIME_DIR" ]]; then
    if ! mkdir -p "$REAL_XDG_RUNTIME_DIR" 2>/dev/null; then
        echo "Error: XDG_RUNTIME_DIR ('$REAL_XDG_RUNTIME_DIR') does not exist and cannot be created." >&2
        exit 1
    fi
fi

# Create disposable temporary directories
OVERLAY_DIR=$(mktemp -d /tmp/sumu-ovl.XXXXXX)
SANDBOX_HOME=$(mktemp -d /tmp/sumu-home.XXXXXX)
DBUS_PROXY_DIR=$(mktemp -d /tmp/sumu-dbus.XXXXXX)
FAKE_USR=$(mktemp -d /tmp/sumu-usr.XXXXXX)

# --- FAKE FHS TREE (Crucial pour NixOS : /usr, /lib, /lib64, /bin n'existent pas) ---
mkdir -p "$FAKE_USR/lib" "$FAKE_USR/lib64" "$FAKE_USR/bin" "$FAKE_USR/share" "$FAKE_USR/etc"

if [[ -d /run/current-system/sw/lib ]]; then
    ln -s /run/current-system/sw/lib/* "$FAKE_USR/lib/" 2>/dev/null || true
fi
if [[ -d /run/current-system/sw/lib64 ]]; then
    ln -s /run/current-system/sw/lib64/* "$FAKE_USR/lib64/" 2>/dev/null || true
fi
if [[ -d /run/opengl-driver-32/lib ]]; then
    ln -sf /run/opengl-driver-32/lib/* "$FAKE_USR/lib/" 2>/dev/null || true
fi
if [[ -d /run/opengl-driver/lib ]]; then
    ln -sf /run/opengl-driver/lib/* "$FAKE_USR/lib64/" 2>/dev/null || true
fi
if [[ -d /run/current-system/sw/bin ]]; then
    ln -s /run/current-system/sw/bin/* "$FAKE_USR/bin/" 2>/dev/null || true
fi
if [[ -d /run/current-system/sw/share ]]; then
    ln -s /run/current-system/sw/share/* "$FAKE_USR/share/" 2>/dev/null || true
fi

# --- CLEANUP AND TRAP HANDLERS ---
BWRAP_PID=""
DBUS_PROXY_PID=""
CLEANUP_RUNNING=false

cleanup() {
    local rc=${1:-$?}
    [[ "$CLEANUP_RUNNING" == true ]] && exit "$rc"
    CLEANUP_RUNNING=true
    trap - EXIT INT TERM HUP

    if [[ -n "${BWRAP_PID:-}" ]]; then
        kill "$BWRAP_PID" 2>/dev/null || true
        wait "$BWRAP_PID" 2>/dev/null || true
    fi

    if [[ -n "${DBUS_PROXY_PID:-}" ]]; then
        kill "$DBUS_PROXY_PID" 2>/dev/null || true
        wait "$DBUS_PROXY_PID" 2>/dev/null || true
    fi

    rm -rf -- "$SANDBOX_HOME" "$DBUS_PROXY_DIR" "$FAKE_USR" "$OVERLAY_DIR" 2>/dev/null || true
    exit "$rc"
}

trap 'cleanup $?' EXIT
trap 'cleanup 129' HUP
trap 'cleanup 130' INT
trap 'cleanup 143' TERM

# --- HELPERS DE MONTAGE ---
declare -a MOUNT_ARGS=()

path_covered() {
    local q="$1" p
    local all_paths=("${PERSIST_PATHS[@]}" "${TEMP_PATHS[@]}")
    for p in "${all_paths[@]}"; do
        [[ "$q" == "$p" || "$q" == "$p"/* || "$p" == "$q"/* ]] && return 0
    done
    return 1
}

add_persist() { MOUNT_ARGS+=(--bind "$1" "$1"); }
add_ro()      { MOUNT_ARGS+=(--ro-bind "$1" "$1"); }

add_temp() {
    local src="$1" ov
    if [[ ! -d "$src" ]]; then
        ov="$OVERLAY_DIR/f-$(printf '%s' "$src" | md5sum | cut -c1-16)"
        cp -a --reflink=auto -- "$src" "$ov" 2>/dev/null || cp -a -- "$src" "$ov" 2>/dev/null || { add_ro "$src"; return; }
        MOUNT_ARGS+=(--bind "$ov" "$src")
        return
    fi
    if [[ "$HAS_TMP_OVERLAY" == true ]]; then
        MOUNT_ARGS+=(--overlay-src "$src" --tmp-overlay "$src")
    else
        ov="$OVERLAY_DIR/d-$(printf '%s' "$src" | md5sum | cut -c1-16)"
        mkdir -p "$ov/upper" "$ov/work"
        MOUNT_ARGS+=(--overlay-src "$src" --overlay "$ov/upper" "$ov/work" "$src")
    fi
}

warn_dangerous() {
    case "$1" in
        /|/etc|/etc/*|/run|/run/*|/proc|/proc/*|/sys|/sys/*|/nix|/nix/*|"$REAL_HOME")
            echo "Warning: Mounting '$1' significantly reduces sandbox security." >&2 ;;
    esac
}

# --- SECTION 1: Filtered D-Bus Proxy (Portals only) ---
FAKE_DBUS_SOCKET="$DBUS_PROXY_DIR/bus"
HAS_DBUS_PROXY=false

if [[ -n "${XDG_DBUS_PROXY_BIN:-}" && -n "${DBUS_SESSION_BUS_ADDRESS:-}" && -S "$REAL_XDG_RUNTIME_DIR/bus" ]]; then
    "$XDG_DBUS_PROXY_BIN" "$DBUS_SESSION_BUS_ADDRESS" "$FAKE_DBUS_SOCKET" \
        --filter \
        '--talk=org.freedesktop.portal.*' \
        '--talk=org.freedesktop.Notifications' \
        '--broadcast=org.freedesktop.portal.*=@/org/freedesktop/portal/*' &
    DBUS_PROXY_PID=$!

    for ((i = 0; i < 100; i++)); do
        [[ -S "$FAKE_DBUS_SOCKET" ]] && { HAS_DBUS_PROXY=true; break; }
        if ! kill -0 "$DBUS_PROXY_PID" 2>/dev/null; then
            wait "$DBUS_PROXY_PID" 2>/dev/null || true
            DBUS_PROXY_PID=""
            echo "Warning: xdg-dbus-proxy exited unexpectedly. D-Bus will be disabled." >&2
            break
        fi
        sleep 0.05
    done

    if [[ "$HAS_DBUS_PROXY" == false && -n "${DBUS_PROXY_PID:-}" ]]; then
        echo "Warning: xdg-dbus-proxy failed to create socket in time. D-Bus disabled." >&2
        kill "$DBUS_PROXY_PID" 2>/dev/null || true
        wait "$DBUS_PROXY_PID" 2>/dev/null || true
        DBUS_PROXY_PID=""
    fi
fi

# --- SECTION 2: UMU / Proton Directory Binds ---
mkdir -p "$SANDBOX_HOME"/{.config,.cache,.local/share,.local/state}

# 2.a Runtimes Steam / compat tools : LECTURE SEULE
for ro_path in ".steam" ".local/share/Steam" ".local/share/Steam/compatibilitytools.d"; do
    tgt="$REAL_HOME/$ro_path"
    [[ -d "$tgt" ]] || continue
    path_covered "$tgt" && continue
    mkdir -p "$SANDBOX_HOME/$ro_path"
    add_ro "$tgt"
done

# 2.b Runtime umu + cache : écriture nécessaire pour màj du runtime
for rw_path in ".local/share/umu" ".cache/umu"; do
    tgt="$REAL_HOME/$rw_path"
    path_covered "$tgt" && continue
    if [[ "$KEEP_PREFIX" == true ]]; then
        mkdir -p "$tgt" "$SANDBOX_HOME/$rw_path"
        add_persist "$tgt"
    elif [[ -d "$tgt" ]]; then
        mkdir -p "$SANDBOX_HOME/$rw_path"
        add_temp "$tgt"
    fi
done

# 2.c WINEPREFIX : jetable par défaut
PREFIX_TGT="${WINEPREFIX:-$REAL_HOME/Games/umu}"
if ! path_covered "$PREFIX_TGT"; then
    if [[ "$KEEP_PREFIX" == true ]]; then
        mkdir -p "$PREFIX_TGT"
        mkdir -p "$SANDBOX_HOME/${PREFIX_TGT#"$REAL_HOME"/}" 2>/dev/null || true
        add_persist "$PREFIX_TGT"
    elif [[ -d "$PREFIX_TGT" ]]; then
        mkdir -p "$SANDBOX_HOME/${PREFIX_TGT#"$REAL_HOME"/}" 2>/dev/null || true
        add_temp "$PREFIX_TGT"
        echo "Info: WINEPREFIX '$PREFIX_TGT' en overlay jetable (sauvegardes perdues à la fermeture)." >&2
        echo "      Utilise -k, ou -p '$PREFIX_TGT', pour le rendre persistant." >&2
    fi
fi

# --- SECTION 3: Bubblewrap Arguments Construction ---
BWRAP_ARGS=(
    --die-with-parent
    --new-session
    --hostname sandbox
    --cap-drop ALL
    --unshare-uts
    --unshare-cgroup
    --unshare-pid
)

# Conditional Network Isolation
[[ "$ALLOW_NET" == false ]] && BWRAP_ARGS+=(--unshare-net)

BWRAP_ARGS+=(
    --proc /proc
    --ro-bind /sys /sys
    --ro-bind /nix /nix

    --dev /dev
    --perms 1777 --tmpfs /dev/shm
    --perms 1777 --size "${SUMU_TMPFS_SIZE:-$((8*1024*1024*1024))}" --tmpfs /tmp

    --tmpfs /var
    --tmpfs /srv
    --tmpfs /boot
    --tmpfs /root

    # NixOS Runtime & OpenGL/Vulkan Drivers
    --tmpfs /run
    --ro-bind /run/current-system /run/current-system
    --ro-bind-try /run/opengl-driver /run/opengl-driver
    --ro-bind-try /run/opengl-driver-32 /run/opengl-driver-32
    --ro-bind-try /run/dbus /run/dbus

    # $XDG_RUNTIME_DIR Configuration
    --dir /run/user
    --perms 0700 --tmpfs "$REAL_XDG_RUNTIME_DIR"
    --setenv XDG_RUNTIME_DIR "$REAL_XDG_RUNTIME_DIR"

    # Virtual HOME
    --tmpfs /home
    --bind "$SANDBOX_HOME" "$REAL_HOME"
    --setenv HOME "$REAL_HOME"

    # CWD
    --chdir "$PWD"

    # Structure FHS factice
    --bind "$FAKE_USR" /usr
    --bind "$FAKE_USR/lib" /lib
    --bind "$FAKE_USR/lib64" /lib64
    --symlink /run/current-system/sw/bin /bin
    --symlink /run/current-system/sw/bin /sbin

    # Secure & Complete /etc Configuration
    --tmpfs /etc
    --ro-bind-try /etc/passwd /etc/passwd
    --ro-bind-try /etc/group /etc/group
    --ro-bind-try /etc/nsswitch.conf /etc/nsswitch.conf
    --ro-bind-try /etc/hosts /etc/hosts
    --ro-bind-try /etc/host.conf /etc/host.conf
    --ro-bind-try /etc/gai.conf /etc/gai.conf
    --ro-bind-try /etc/machine-id /etc/machine-id
    --ro-bind-try /var/lib/dbus/machine-id /var/lib/dbus/machine-id
    --ro-bind-try /etc/localtime /etc/localtime
    --ro-bind-try /etc/zoneinfo /etc/zoneinfo
    --ro-bind-try /etc/fonts /etc/fonts
    --ro-bind-try /etc/os-release /etc/os-release
    --ro-bind-try /etc/alsa /etc/alsa
    --ro-bind-try /etc/asound.conf /etc/asound.conf

    # Dynamic Loaders
    --ro-bind-try /etc/ld.so.cache /etc/ld.so.cache
    --ro-bind-try /etc/ld.so.conf /etc/ld.so.conf
    --ro-bind-try /etc/ld.so.conf.d /etc/ld.so.conf.d

    # GPU / ICD / DRIRC
    --ro-bind-try /etc/vulkan /etc/vulkan
    --ro-bind-try /etc/glvnd /etc/glvnd

    --symlink /proc/self/mounts /etc/mtab
)

# --- SECTION 3.b: CA Certificates (minimal, symlink-safe) ---
bind_ca_bundle() {
    local dest="$1" real
    real="$(readlink -f -- "$dest" 2>/dev/null || true)"
    [[ -n "$real" && -f "$real" ]] || return 0
    BWRAP_ARGS+=(--dir "$(dirname "$dest")" --ro-bind-try "$real" "$dest")
}

for cert_path in \
    /etc/ssl/certs/ca-certificates.crt \
    /etc/ssl/certs/ca-bundle.crt \
    /etc/pki/tls/certs/ca-bundle.crt \
    /etc/ssl/cert.pem \
    /etc/ssl/ca-bundle.pem; do
    bind_ca_bundle "$cert_path"
done
unset -f bind_ca_bundle

# DNS Resolution setup
if [[ "$ALLOW_NET" == true ]]; then
    if [[ -L /etc/resolv.conf ]]; then
        RESOLV_TARGET="$(readlink -f -- /etc/resolv.conf || true)"
        if [[ -n "$RESOLV_TARGET" && -e "$RESOLV_TARGET" ]]; then
            BWRAP_ARGS+=(--ro-bind-try "$RESOLV_TARGET" /etc/resolv.conf)
        else
            BWRAP_ARGS+=(--ro-bind-try /etc/resolv.conf /etc/resolv.conf)
        fi
    else
        BWRAP_ARGS+=(--ro-bind-try /etc/resolv.conf /etc/resolv.conf)
    fi
else
    : > "$SANDBOX_HOME/dummy-resolv.conf"
    BWRAP_ARGS+=(--ro-bind "$SANDBOX_HOME/dummy-resolv.conf" /etc/resolv.conf)
fi

# --- SECTION 4: Graphics Devices (DRI & NVIDIA) ---
[[ -d /dev/dri ]] && BWRAP_ARGS+=(--dev-bind /dev/dri /dev/dri)

shopt -s nullglob
for nv_dev in /dev/nvidia[0-9]* /dev/nvidiactl /dev/nvidia-modeset \
              /dev/nvidia-uvm /dev/nvidia-uvm-tools /dev/nvidia-peermem; do
    [[ -e "$nv_dev" ]] && BWRAP_ARGS+=(--dev-bind "$nv_dev" "$nv_dev")
done
shopt -u nullglob

if [[ -d /dev/nvidia-caps ]]; then
    BWRAP_ARGS+=(--dev-bind /dev/nvidia-caps /dev/nvidia-caps)
fi

# --- SECTION 5: Input Devices (Gamepads, etc.) ---
if [[ "$ALLOW_INPUT" == true ]]; then
    [[ -d /dev/input ]] && BWRAP_ARGS+=(--dev-bind /dev/input /dev/input)
    [[ -d /run/udev ]]  && BWRAP_ARGS+=(--ro-bind-try /run/udev /run/udev)
fi

# --- SECTION 6: Audio Servers (PipeWire / PulseAudio) ---
if [[ -S "$REAL_XDG_RUNTIME_DIR/pipewire-0" ]]; then
    BWRAP_ARGS+=(--bind "$REAL_XDG_RUNTIME_DIR/pipewire-0" "$REAL_XDG_RUNTIME_DIR/pipewire-0")
fi
if [[ -d "$REAL_XDG_RUNTIME_DIR/pulse" ]]; then
    BWRAP_ARGS+=(
        --bind-try "$REAL_XDG_RUNTIME_DIR/pulse" "$REAL_XDG_RUNTIME_DIR/pulse"
        --setenv PULSE_SERVER "unix:$REAL_XDG_RUNTIME_DIR/pulse/native"
    )
fi

# --- SECTION 7: Display (Wayland & X11) ---
WL_DISPLAY_NAME="${WAYLAND_DISPLAY:-wayland-0}"
if [[ "$WL_DISPLAY_NAME" != /* ]] && [[ -S "$REAL_XDG_RUNTIME_DIR/$WL_DISPLAY_NAME" ]]; then
    BWRAP_ARGS+=(
        --setenv WAYLAND_DISPLAY "$WL_DISPLAY_NAME"
        --bind "$REAL_XDG_RUNTIME_DIR/$WL_DISPLAY_NAME" "$REAL_XDG_RUNTIME_DIR/$WL_DISPLAY_NAME"
    )
fi

if [[ "$ALLOW_X11" == true && -n "${DISPLAY:-}" ]]; then
    display_number="${DISPLAY#*:}"
    display_number="${display_number%%.*}"

    if [[ "$display_number" =~ ^[0-9]+$ && -e "/tmp/.X11-unix/X$display_number" ]]; then
        x11_socket="/tmp/.X11-unix/X$display_number"
        BWRAP_ARGS+=(
            --setenv DISPLAY "$DISPLAY"
            --bind "$x11_socket" "$x11_socket"
        )
        if [[ -n "${XAUTHORITY:-}" && -f "$XAUTHORITY" ]]; then
            BWRAP_ARGS+=(
                --setenv XAUTHORITY "$XAUTHORITY"
                --ro-bind "$XAUTHORITY" "$XAUTHORITY"
            )
        elif [[ -f "$REAL_HOME/.Xauthority" ]]; then
            BWRAP_ARGS+=(
                --setenv XAUTHORITY "$REAL_HOME/.Xauthority"
                --ro-bind "$REAL_HOME/.Xauthority" "$REAL_HOME/.Xauthority"
            )
        else
            echo "Warning: X11 enabled but no valid XAUTHORITY found; authentication might fail." >&2
        fi
    else
        echo "Warning: X11 enabled but DISPLAY='$DISPLAY' is invalid or socket is missing." >&2
    fi
fi

# --- SECTION 8: D-Bus Configuration ---
if [[ "$HAS_DBUS_PROXY" == true ]]; then
    BWRAP_ARGS+=(
        --bind "$FAKE_DBUS_SOCKET" "$REAL_XDG_RUNTIME_DIR/bus"
        --setenv DBUS_SESSION_BUS_ADDRESS "unix:path=$REAL_XDG_RUNTIME_DIR/bus"
    )
else
    BWRAP_ARGS+=(--unsetenv DBUS_SESSION_BUS_ADDRESS)
fi

# --- SECTION 9: Environment Variables & Security ---
BWRAP_ARGS+=(
    --setenv PATH "/run/current-system/sw/bin:/usr/bin:/bin"
    --setenv LANG "${LANG:-C.UTF-8}"
    --setenv TMPDIR /tmp
    --setenv USER "${USER:-$(id -un)}"
    --setenv LOGNAME "${LOGNAME:-$(id -un)}"
    --setenv XDG_CONFIG_HOME "$REAL_HOME/.config"
    --setenv XDG_CACHE_HOME  "$REAL_HOME/.cache"
    --setenv XDG_DATA_HOME   "$REAL_HOME/.local/share"
    --setenv XDG_STATE_HOME  "$REAL_HOME/.local/state"
    --unsetenv SSH_AUTH_SOCK
    --unsetenv SSH_AGENT_PID
    --unsetenv GPG_AGENT_INFO
)

# Forward essential gaming and graphics environment variables
for var in XDG_SESSION_TYPE XDG_CURRENT_DESKTOP LC_ALL LC_CTYPE LC_MESSAGES \
           MANGOHUD MANGOHUD_CONFIG DXVK_HUD VKD3D_CONFIG PROTON_LOG \
           GAMESCOPE __NV_PRIME_RENDER_OFFLOAD __GLX_VENDOR_LIBRARY_NAME \
           DRI_PRIME NVD_BACKEND VK_ICD_FILENAMES VK_LAYER_PATH; do
    if [[ -n "${!var:-}" ]]; then
        BWRAP_ARGS+=(--setenv "$var" "${!var}")
    fi
done

# Forward essential UMU / Proton variables
for var in GAMEID STORE PROTONPATH WINEPREFIX UMU_ID PROTON_VERB STEAM_EXTRA_COMPAT_TOOLS_PATHS PROTON_ENABLE_WAYLAND; do
    if [[ -n "${!var:-}" ]]; then
        BWRAP_ARGS+=(--setenv "$var" "${!var}")
    fi
done

# --- SECTION 10: Custom User Mounts (-p persistant / -w temporaire) ---
CWD_ABS="$(realpath -m -- "$PWD")"
cwd_handled=false
all_user_paths=("${PERSIST_PATHS[@]}" "${TEMP_PATHS[@]}")
for p in "${all_user_paths[@]}"; do
    if [[ "$CWD_ABS" == "$p" || "$CWD_ABS" == "$p"/* ]]; then cwd_handled=true; break; fi
done
[[ "$cwd_handled" == false ]] && TEMP_PATHS+=("$CWD_ABS")

# Tri lexicographique
if ((${#PERSIST_PATHS[@]})); then
    mapfile -t PERSIST_PATHS < <(printf '%s\n' "${PERSIST_PATHS[@]}" | sort -u)
fi
if ((${#TEMP_PATHS[@]})); then
    mapfile -t TEMP_PATHS < <(printf '%s\n' "${TEMP_PATHS[@]}" | sort -u)
fi

# Application des montages utilisateur
for ABS_PATH in "${PERSIST_PATHS[@]}"; do
    if [[ ! -e "$ABS_PATH" ]]; then
        mkdir -p -- "$ABS_PATH" 2>/dev/null || {
            echo "Warning: Path '$ABS_PATH' does not exist and cannot be created, skipping." >&2
            continue; }
    fi
    warn_dangerous "$ABS_PATH"
    [[ -w "$ABS_PATH" ]] || echo "Warning: '$ABS_PATH' is not writable by the current user." >&2
    add_persist "$ABS_PATH"
done

for ABS_PATH in "${TEMP_PATHS[@]}"; do
    if [[ ! -e "$ABS_PATH" ]]; then
        echo "Warning: Path '$ABS_PATH' does not exist, skipping." >&2
        continue
    fi
    warn_dangerous "$ABS_PATH"
    add_temp "$ABS_PATH"
done

# --- SECTION 10.b: Lettres de lecteur Wine pour les vrais montages ---
path_is_bound() {
    local q="$1" p
    for p in "${PERSIST_PATHS[@]}" "${TEMP_PATHS[@]}"; do
        [[ "$q" == "$p" || "$q" == "$p"/* ]] && return 0
    done
    return 1
}

mount_point_of() {
    findmnt -n -o TARGET --target "$1" 2>/dev/null | tail -n1
}

drive_target_for() {
    local p="$1" mp
    mp="$(mount_point_of "$p")"
    if [[ -n "$mp" && "$mp" != "/" ]] && path_is_bound "$mp"; then
        printf '%s' "$mp"
    else
        printf '%s' "$p"
    fi
}

declare -A DRIVE_USED=( [c]=1 [z]=1 )
declare -A DRIVE_SEEN=()

# Lettres imposées par l'utilisateur (-D)
for md in "${MANUAL_DRIVES[@]}"; do
    l="${md%%=*}"; t="$(realpath -m -- "${md#*=}")"
    DRIVE_USED["$l"]=1
    DRIVE_SEEN["$t"]="$l"
    DRIVE_MAP+=("$l=$t")
done

if [[ "$AUTO_DRIVES" == true ]]; then
    for p in "${PERSIST_PATHS[@]}" "${TEMP_PATHS[@]}"; do
        mp="$(mount_point_of "$p")"
        case "$p" in
            /mnt|/mnt/*|/media/*|/run/media/*) ;;
            *) [[ -n "$mp" && "$mp" != "/" ]] || continue ;;
        esac

        tgt="$(drive_target_for "$p")"
        [[ -n "${DRIVE_SEEN[$tgt]:-}" ]] && continue

        letter=""
        for l in g h i j k l m n o p q r s t u v w x y d e f; do
            [[ -z "${DRIVE_USED[$l]:-}" ]] && { letter="$l"; break; }
        done
        [[ -z "$letter" ]] && { echo "Warning: plus de lettre libre pour '$tgt'." >&2; continue; }

        DRIVE_USED["$letter"]=1
        DRIVE_SEEN["$tgt"]="$letter"
        DRIVE_MAP+=("$letter=$tgt")
    done
fi

SUMU_DRIVES=""
if ((${#DRIVE_MAP[@]})); then
    SUMU_DRIVES="$(IFS='|'; printf '%s' "${DRIVE_MAP[*]}")"
    for d in "${DRIVE_MAP[@]}"; do
        echo "Info: lecteur Wine ${d%%=*}: -> ${d#*=} (espace disque réel)" >&2
    done
fi

# Injection des variables d'environnement Wine dans Bwrap
BWRAP_ARGS+=(
    --setenv WINEPREFIX "$PREFIX_TGT"
    --setenv SUMU_DRIVES "$SUMU_DRIVES"
)

# Script d'initialisation des dosdevices à exécuter dans le sandbox
INIT_SCRIPT="$SANDBOX_HOME/.sumu-init.sh"
cat > "$INIT_SCRIPT" <<'EOS'
#!/usr/bin/env bash
set -u

prefix="${WINEPREFIX:-}"
drives="${SUMU_DRIVES:-}"

link_drives() {
    local dd="$prefix/dosdevices" entry letter target link
    [ -d "$dd" ] || return 1
    local IFS='|'
    for entry in $drives; do
        letter="${entry%%=*}"
        target="${entry#*=}"
        link="$dd/${letter}:"
        if [ ! -L "$link" ] || [ "$(readlink "$link")" != "$target" ]; then
            rm -rf -- "$link"
            ln -s -- "$target" "$link" 2>/dev/null || true
        fi
    done
    return 0
}

if [ -n "$prefix" ] && [ -n "$drives" ]; then
    link_drives || true
    (
        i=0
        while [ "$i" -lt 600 ]; do
            link_drives >/dev/null 2>&1 || true
            sleep 0.5
            i=$((i+1))
        done
    ) &
fi

exec "$@"
EOS
chmod +x "$INIT_SCRIPT"

# --- SECTION 11: Monitored Execution ---
BASH_BIN="$(readlink -f -- "$(type -P bash)")"

set +e
"$BWRAP_BIN" "${BWRAP_ARGS[@]}" "${MOUNT_ARGS[@]}" -- \
    "$BASH_BIN" "$REAL_HOME/.sumu-init.sh" "$UMU_BIN" "${UMU_ARGS[@]}" &
BWRAP_PID=$!
wait "$BWRAP_PID"
rc=$?
BWRAP_PID=""
set -e

exit "$rc"