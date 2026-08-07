#!/usr/bin/env bash

unset TMPDIR

if [ -z "$1" ]; then
  echo "❌ Usage: setup-env <extension|fichier.ext>"
  exit 1
fi

ARG="$1"

if [[ "$ARG" == *.* ]]; then
  EXTENSION="${ARG##*.}"
  BASENAME="${ARG%.*}"
  FILENAME="$ARG"
else
  EXTENSION="$ARG"
  BASENAME="main"
  FILENAME=""
fi

if [ -f flake.nix ]; then
  echo "⚠️ Un fichier flake.nix existe déjà ici. Abandon."
  exit 1
fi

if [ "$EXTENSION" = "cpp" ]; then
  echo "🏗️ Création de la structure de projet C++..."
  
  mkdir -p src include assets

  if [ ! -f src/main.cpp ]; then
    cat << 'EOF' > src/main.cpp
#include <iostream>

int main() {
    std::cout << "Hello depuis C++ !" << std::endl;
    return 0;
}
EOF
  fi

  if [ ! -f assets/app.rc ]; then
    touch assets/app.rc
  fi

  if [ ! -f Makefile ]; then
    cat << 'EOF' > Makefile
ifeq ($(TARGET_OS),)

all: linux windows

linux:
	@$(MAKE) TARGET_OS=linux

windows:
	@$(MAKE) TARGET_OS=windows

clean:
	@$(MAKE) TARGET_OS=linux clean
	@$(MAKE) TARGET_OS=windows clean

.PHONY: all linux windows clean

else

BUILD_DIR  := .build/$(TARGET_OS)
OBJ_DIR    := $(BUILD_DIR)/obj
BIN_DIR    := $(BUILD_DIR)/bin
SRC_DIR    := src
INC_DIR    := include
ASSETS_DIR := assets

ifeq ($(TARGET_OS), windows)
    CXX := x86_64-w64-mingw32-g++
    WINDRES := x86_64-w64-mingw32-windres
    EXE_EXT := .exe
    CXXFLAGS := -std=gnu++26 -O3 -Wall -Wextra -Wpedantic -Werror -DWIN32 -D_WINDOWS
    LDFLAGS := -static -static-libgcc -static-libstdc++
else ifeq ($(TARGET_OS), linux)
    CXX := g++
    WINDRES :=
    EXE_EXT :=
    CXXFLAGS := -std=gnu++26 -O3 -Wall -Wextra -Wpedantic -Werror
    LDFLAGS := -static-libgcc -static-libstdc++ -lpthread
else
    $(error TARGET_OS inconnu. Utilisez "linux" ou "windows")
endif

CXXFLAGS += -I$(INC_DIR)

SRCS    := $(wildcard $(SRC_DIR)/*.cpp)
STEMS   := $(patsubst $(SRC_DIR)/%.cpp,%,$(SRCS))
TARGETS := $(patsubst %,$(BIN_DIR)/%$(EXE_EXT),$(STEMS))

all: $(TARGETS)

$(OBJ_DIR)/%.o: $(SRC_DIR)/%.cpp
	@mkdir -p $(@D)
	@echo "Compiling [$(TARGET_OS)] -> $<"
	$(CXX) $(CXXFLAGS) -c $< -o $@

ifeq ($(TARGET_OS), windows)

GET_RC = $(if $(wildcard $(ASSETS_DIR)/$(1).rc),$(ASSETS_DIR)/$(1).rc,$(wildcard $(ASSETS_DIR)/app.rc))

define BUILD_TARGET
ifneq ($(call GET_RC,$(1)),)
$(OBJ_DIR)/$(1)_resource.o: $(call GET_RC,$(1))
	@mkdir -p $$(@D)
	@echo "Compiling Resource [$(call GET_RC,$(1))] pour $(1) -> $$@"
	$$(WINDRES) $$< -O coff -o $$@

$(BIN_DIR)/$(1)$(EXE_EXT): $(OBJ_DIR)/$(1).o $(OBJ_DIR)/$(1)_resource.o
	@mkdir -p $$(@D)
	@echo "Linking [$(TARGET_OS)] -> $$@"
	$$(CXX) $$^ -o $$@ $$(LDFLAGS)
else
$(BIN_DIR)/$(1)$(EXE_EXT): $(OBJ_DIR)/$(1).o
	@mkdir -p $$(@D)
	@echo "Linking [$(TARGET_OS)] -> $$@"
	$$(CXX) $$^ -o $$@ $$(LDFLAGS)
endif
endef

else

define BUILD_TARGET
$(BIN_DIR)/$(1)$(EXE_EXT): $(OBJ_DIR)/$(1).o
	@mkdir -p $$(@D)
	@echo "Linking [$(TARGET_OS)] -> $$@"
	$$(CXX) $$^ -o $$@ $$(LDFLAGS)
endef

endif

$(foreach stem,$(STEMS),$(eval $(call BUILD_TARGET,$(stem))))

clean:
	rm -rf .build

.PHONY: all clean

endif
EOF
  fi

  cat << 'EOF' > flake.nix
{
  description = "Environnement C++ (Linux + Windows Cross-Compilation)";
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  };
  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      mingwPkgs = pkgs.pkgsCross.mingwW64;
    in {
      devShells.${system}.default = pkgs.mkShell {
        packages = [
          pkgs.gnumake
          pkgs.cmake
          pkgs.gdb
          mingwPkgs.stdenv.cc
          mingwPkgs.buildPackages.binutils
        ];
      };
    };
}
EOF

else
  if [ -z "$FILENAME" ]; then
    FILENAME="${BASENAME}.${EXTENSION}"
  fi

  PACKAGES=""
  BOILERPLATE=""

  case "$EXTENSION" in
    py)
      detected_imports=$(grep -rIhE '^(import|from)\s+[a-zA-Z0-9_]' --include="*.py" . 2>/dev/null | awk '{print $2}' | cut -d. -f1 | sort -u)
      py_modules=""
      for mod in $detected_imports; do
        case "$mod" in
          pandas|numpy|requests|matplotlib|scipy|tensorflow|torch|torchvision)
            py_modules="$py_modules $mod"
            ;;
          sklearn)
            py_modules="$py_modules scikit-learn"
            ;;
        esac
      done

      if [ -n "$py_modules" ]; then
        PACKAGES="(python3.withPackages (ps: with ps; [ $py_modules ]))"
      else
        PACKAGES="python3"
      fi
      BOILERPLATE="print(\"Hello depuis Python !\")"
      ;;
    c)
      PACKAGES="gcc gnumake gdb"
      BOILERPLATE="#include <stdio.h>\n\nint main() {\n    printf(\"Hello depuis C !\\n\");\n    return 0;\n}"
      ;;
    js)
      PACKAGES="nodejs"
      BOILERPLATE="console.log(\"Hello depuis JS !\");"
      ;;
    java)
      PACKAGES="jdk"
      BOILERPLATE="public class $BASENAME {\n    public static void main(String[] args) {\n        System.out.println(\"Hello depuis Java !\");\n    }\n}"
      ;;
    *)
      echo "❌ Extension .$EXTENSION non supportée."
      exit 1
      ;;
  esac

  if [ ! -f "$FILENAME" ]; then
    echo -e "$BOILERPLATE" > "$FILENAME"
  fi

  cat << EOF > flake.nix
{
  description = "Environnement auto-généré pour $EXTENSION";
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  };
  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.\${system};
    in {
      devShells.\${system}.default = pkgs.mkShell {
        packages = with pkgs; [
          $PACKAGES
        ];
      };
    };
}
EOF
fi

echo "unset TMPDIR\nuse flake" > .envrc
direnv allow || echo "👉 Pense à faire 'direnv allow' si nécessaire."

echo "✅ Environnement projet prêt !"
