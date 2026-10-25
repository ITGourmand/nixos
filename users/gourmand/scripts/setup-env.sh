#!/usr/bin/env bash

set -euo pipefail
unset TMPDIR

if [ -z "${1:-}" ]; then
  echo "❌ Usage: setup-env <extension|fichier.ext>"
  exit 1
fi

ARG="$1"
if [[ "$ARG" == *.* ]]; then
  EXTENSION="${ARG##*.}"
  BASENAME="${ARG%.*}"
else
  EXTENSION="$ARG"
  BASENAME="main"
fi

if [ -f flake.nix ]; then
  echo "⚠️ Un fichier flake.nix existe déjà ici. Abandon."
  exit 1
fi

# 1. Structure générique (commune à tous les langages)
mkdir -p src .build

# 2. HELPER : Générateur de Flake Nix Multi-Architecture
generate_flake() {
  local desc="$1"
  local pkgs_list="$2"
  local extra_bindings="${3:-}"

  cat << EOF > flake.nix
{
  description = "$desc";
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };
  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.\${system};
        $extra_bindings
      in {
        devShells.default = pkgs.mkShell {
          packages = [ $pkgs_list ];
        };
      });
}
EOF
}

# 3. HELPER : Makefile C/C++ (Linux + Windows Cross-Compilation + support .rc)
generate_makefile_cpp_c() {
  local compiler_linux="$1"
  local compiler_win="$2"
  local ext="$3"
  local std_flag="$4"
  local is_cpp="$5"

  cat << EOF > Makefile
ifeq (\$(TARGET_OS),)

all: linux windows

linux:
	@\$(MAKE) TARGET_OS=linux

windows:
	@\$(MAKE) TARGET_OS=windows

clean:
	@\$(MAKE) TARGET_OS=linux clean
	@\$(MAKE) TARGET_OS=windows clean

.PHONY: all linux windows clean

else

BUILD_DIR  := .build/\$(TARGET_OS)
OBJ_DIR    := \$(BUILD_DIR)/obj
BIN_DIR    := \$(BUILD_DIR)/bin
SRC_DIR    := src
INC_DIR    := include
ASSETS_DIR := assets

ifeq (\$(TARGET_OS), windows)
    CC := $compiler_win
    WINDRES := x86_64-w64-mingw32-windres
    EXE_EXT := .exe
    CFLAGS := $std_flag -O3 -Wall -Wextra -Wpedantic -Werror -I\$(INC_DIR) -DWIN32 -D_WINDOWS
    LDFLAGS := -static -static-libgcc $( [ "$is_cpp" = "true" ] && echo "-static-libstdc++ -lstdc++exp" )
else ifeq (\$(TARGET_OS), linux)
    CC := $compiler_linux
    WINDRES :=
    EXE_EXT :=
    CFLAGS := $std_flag -O3 -Wall -Wextra -Wpedantic -Werror -I\$(INC_DIR)
    LDFLAGS := $( [ "$is_cpp" = "true" ] && echo "-static-libgcc -static-libstdc++" ) -lpthread
else
    \$(error TARGET_OS inconnu. Utilisez "linux" ou "windows")
endif

INC_SRCS   := \$(wildcard \$(INC_DIR)/*.$ext)
INC_OBJS   := \$(patsubst \$(INC_DIR)/%.$ext,\$(OBJ_DIR)/inc_%.o,\$(INC_SRCS))

APP_SRCS   := \$(wildcard \$(SRC_DIR)/*.$ext)
STEMS      := \$(patsubst \$(SRC_DIR)/%.$ext,%,\$(APP_SRCS))

.DEFAULT_GOAL := all
all: \$(STEMS:%=\$(BIN_DIR)/%\$(EXE_EXT))

ifeq (\$(TARGET_OS), windows)

GET_RC = \$(if \$(wildcard \$(ASSETS_DIR)/\$(1).rc),\$(ASSETS_DIR)/\$(1).rc,\$(wildcard \$(ASSETS_DIR)/app.rc))

define BUILD_TARGET
ifneq (\$(call GET_RC,\$(1)),)
\$(OBJ_DIR)/\$(1)_resource.o: \$(call GET_RC,\$(1))
	@mkdir -p \$\$(@D)
	@echo "🎨 Compiling Resource [\$(call GET_RC,\$(1))] pour \$(1) -> \$\$(@)"
	\$\$(WINDRES) \$\$< -O coff -o \$\$(@)

\$(BIN_DIR)/\$(1)\$(EXE_EXT): \$(OBJ_DIR)/\$(1).o \$(INC_OBJS) \$(OBJ_DIR)/\$(1)_resource.o
	@mkdir -p \$\$(@D)
	@echo "🔗 Linking [\$(TARGET_OS)] -> \$\$(@)"
	\$\$(CC) \$\$^ -o \$\$(@) \$\$(LDFLAGS)
else
\$(BIN_DIR)/\$(1)\$(EXE_EXT): \$(OBJ_DIR)/\$(1).o \$(INC_OBJS)
	@mkdir -p \$\$(@D)
	@echo "🔗 Linking [\$(TARGET_OS)] -> \$\$(@)"
	\$\$(CC) \$\$^ -o \$\$(@) \$\$(LDFLAGS)
endif
endef

else

define BUILD_TARGET
\$(BIN_DIR)/\$(1)\$(EXE_EXT): \$(OBJ_DIR)/\$(1).o \$(INC_OBJS)
	@mkdir -p \$\$(@D)
	@echo "🔗 Linking [\$(TARGET_OS)] -> \$\$(@)"
	\$\$(CC) \$\$^ -o \$\$(@) \$\$(LDFLAGS)
endef

endif

\$(OBJ_DIR)/%.o: \$(SRC_DIR)/%.$ext
	@mkdir -p \$(@D)
	@echo "🔨 Compiling App [\$(TARGET_OS)] -> \$<"
	\$(CC) \$(CFLAGS) -c \$< -o \$@

\$(OBJ_DIR)/inc_%.o: \$(INC_DIR)/%.$ext
	@mkdir -p \$(@D)
	@echo "🔨 Compiling Lib [\$(TARGET_OS)] -> \$<"
	\$(CC) \$(CFLAGS) -c \$< -o \$@

\$(foreach stem,\$(STEMS),\$(eval \$(call BUILD_TARGET,\$(stem))))

clean:
	rm -rf .build

.PHONY: all clean

endif
EOF
}

# 4. Traitement selon l'extension
case "$EXTENSION" in
  cpp|c)
    mkdir -p include assets

    IS_CPP=$([ "$EXTENSION" = "cpp" ] && echo "true" || echo "false")
    COMP_LINUX=$([ "$IS_CPP" = "true" ] && echo "g++" || echo "gcc")
    COMP_WIN=$([ "$IS_CPP" = "true" ] && echo "x86_64-w64-mingw32-g++" || echo "x86_64-w64-mingw32-gcc")
    STD_FLAG=$([ "$IS_CPP" = "true" ] && echo "-std=gnu++26" || echo "-std=c17")

    if [ ! -f "assets/app.rc" ]; then
      cat << 'EOF' > assets/app.rc
1 VERSIONINFO
FILEVERSION 1,0,0,0
PRODUCTVERSION 1,0,0,0
BEGIN
    BLOCK "StringFileInfo"
    BEGIN
        BLOCK "040904E4"
        BEGIN
            VALUE "FileDescription", "Application Windows"
            VALUE "FileVersion", "1.0.0.0"
            VALUE "ProductName", "App"
            VALUE "ProductVersion", "1.0.0.0"
        END
    END
    BLOCK "VarFileInfo"
    BEGIN
        VALUE "Translation", 0x0409, 1252
    END
END
EOF
    fi

    if [ ! -f "src/${BASENAME}.${EXTENSION}" ]; then
      if [ "$IS_CPP" = "true" ]; then
        cat << EOF > "src/${BASENAME}.cpp"
#include <iostream>

int main() {
    std::cout << "Hello depuis C++ !" << std::endl;
    return 0;
}
EOF
      else
        cat << EOF > "src/${BASENAME}.c"
#include <stdio.h>

int main() {
    printf("Hello depuis C !\n");
    return 0;
}
EOF
      fi
    fi

    generate_makefile_cpp_c "$COMP_LINUX" "$COMP_WIN" "$EXTENSION" "$STD_FLAG" "$IS_CPP"

    FLAKE_PKGS="pkgs.gnumake pkgs.cmake pkgs.gdb mingwPkgs.stdenv.cc mingwPkgs.buildPackages.binutils"
    generate_flake "Environnement $EXTENSION Multi-Plateforme" "$FLAKE_PKGS" "mingwPkgs = pkgs.pkgsCross.mingwW64;"
    ;;

  py)
    mkdir -p src/lib
    touch src/lib/__init__.py

    if [ ! -f "src/${BASENAME}.py" ]; then
      cat << EOF > "src/${BASENAME}.py"
import sys

def main():
    print(f"Hello depuis Python ({sys.platform}) !")

if __name__ == "__main__":
    main()
EOF
    fi

    imports_from=$(grep -rIhE '^from[[:space:]]+[a-zA-Z0-9_.]+[[:space:]]+import' --include="*.py" src/ 2>/dev/null \
      | awk '{print $2}' | cut -d. -f1)
    imports_plain=$(grep -rIhE '^import[[:space:]]+[a-zA-Z0-9_]' --include="*.py" src/ 2>/dev/null \
      | sed -E 's/^import[[:space:]]+//; s/[[:space:]]+as[[:space:]]+[a-zA-Z0-9_]+//g' \
      | tr ',' '\n' | awk '{print $1}' | cut -d. -f1)
    detected_imports=$(printf '%s\n%s\n' "$imports_from" "$imports_plain" | sed '/^$/d' | sort -u || true)
    py_modules="ps.pyinstaller"
    for mod in $detected_imports; do
      case "$mod" in
        pandas|numpy|requests|matplotlib|scipy|tensorflow|torch|torchvision)
          py_modules="$py_modules ps.$mod"
          ;;
        sklearn)
          py_modules="$py_modules ps.scikit-learn"
          ;;
      esac
    done

    cat << 'EOF' > Makefile
BUILD_DIR := .build
SRCS      := $(wildcard src/*.py)
STEMS     := $(patsubst src/%.py,%,$(SRCS))

all: linux windows

linux: $(STEMS:%=$(BUILD_DIR)/linux/bin/%)
windows: $(STEMS:%=$(BUILD_DIR)/windows/bin/%.exe)

$(BUILD_DIR)/linux/bin/%: src/%.py
	@mkdir -p $(BUILD_DIR)/linux/bin
	@echo "📦 [Linux] Packaging binaire pour $<"
	pyinstaller --onefile --noconfirm --distpath $(BUILD_DIR)/linux/bin --workpath $(BUILD_DIR)/linux/obj $<

$(BUILD_DIR)/windows/bin/%.exe: src/%.py
	@mkdir -p $(BUILD_DIR)/windows/bin
	@echo "📦 [Windows] Packaging éphémère via Podman pour $<"
	podman run --rm --userns=keep-id -v "$(PWD):/src:z" cdrx/pyinstaller-windows "pyinstaller --onefile --noconfirm --distpath .build/windows/bin --workpath .build/windows/obj src/$*.py"

clean:
	rm -rf .build build dist *.spec

.PHONY: all linux windows clean
EOF

    generate_flake "Environnement Python Multi-Entry" "(pkgs.python3.withPackages (ps: [ $py_modules ])) pkgs.gnumake pkgs.podman"
    ;;

  js|ts)
    if [ ! -f package.json ]; then
      cat << EOF > package.json
{
  "name": "multi-app",
  "version": "1.0.0",
  "main": ".build/compiled/${BASENAME}.js",
  "scripts": {
    "compile": "esbuild src/${BASENAME}.${EXTENSION} --bundle --platform=node --external:electron --outdir=.build/compiled",
    "linux": "npm run compile && electron-builder --linux -c.directories.output=.build/linux/bin",
    "windows": "npm run compile && electron-builder --windows -c.directories.output=.build/windows/bin"
  },
  "build": {
    "appId": "com.example.${BASENAME}",
    "files": [".build/compiled/**/*"],
    "linux": {
      "target": ["AppImage"]
    },
    "extraArgs": ["--no-sandbox"]
  },
  "devDependencies": {
    "@types/node": "latest",
    "electron": "latest",
    "electron-builder": "latest",
    "esbuild": "latest"
  }
}
EOF
    fi

    if [ ! -f "src/${BASENAME}.${EXTENSION}" ]; then
      cat << EOF > "src/${BASENAME}.${EXTENSION}"
import { app, BrowserWindow } from "electron";

function createWindow() {
  const win = new BrowserWindow({ width: 800, height: 600 });
  win.loadURL("data:text/html,<h1>Hello depuis ${EXTENSION^^} / Electron !</h1>");
}

app.whenReady().then(createWindow);

app.on("window-all-closed", () => {
  if (process.platform !== "darwin") app.quit();
});
EOF
    fi

    cat << 'EOF' > Makefile
all: linux windows

linux:
	@mkdir -p .build/cache/electron .build/cache/electron-builder .build/cache/npm
	ELECTRON_CACHE="$(PWD)/.build/cache/electron" \
	ELECTRON_BUILDER_CACHE="$(PWD)/.build/cache/electron-builder" \
	npm_config_cache="$(PWD)/.build/cache/npm" \
	npm run linux

windows:
	@mkdir -p .build/cache/electron .build/cache/electron-builder
	podman run --rm --userns=keep-id \
	  -v "$(PWD):/project:z" \
	  -v "$(PWD)/.build/cache/electron:/root/.cache/electron:z" \
	  -v "$(PWD)/.build/cache/electron-builder:/root/.cache/electron-builder:z" \
	  -w /project \
	  electronuserland/builder:wine \
	  npm run windows

clean:
	rm -rf .build dist node_modules

.PHONY: all linux windows clean
EOF

    generate_flake "Environnement JS/TS/Electron Multi-Entry" "pkgs.nodejs pkgs.gnumake pkgs.podman"
    if [ ! -d node_modules ]; then
      echo "📦 Installation automatique des dépendances..."
      nix develop --command npm install
    fi
    ;;

  java)
    if [ ! -f "src/${BASENAME}.java" ]; then
      cat << EOF > "src/${BASENAME}.java"
public class $BASENAME {
    public static void main(String[] args) {
        System.out.println("Hello depuis Java !");
    }
}
EOF
    fi

    cat << 'EOF' > Makefile
BUILD_DIR := .build/bin
SRCS      := $(wildcard src/*.java)

all:
	@mkdir -p $(BUILD_DIR)
	javac -d $(BUILD_DIR) $(SRCS)

clean:
	rm -rf .build

.PHONY: all clean
EOF

    generate_flake "Environnement Java Multi-Entry" "pkgs.jdk pkgs.gnumake"
    ;;

  *)
    echo "❌ Extension .$EXTENSION non supportée."
    exit 1
    ;;
esac

# 5. Configuration Direnv & Environnement
cat << 'EOF' > .envrc
unset TMPDIR
use flake
EOF

direnv allow || echo "👉 Exécutez 'direnv allow' si nécessaire."

echo "✅ Projet $EXTENSION prêt (Architecture Multi-Entry / Multi-OS)."
