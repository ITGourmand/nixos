{ pkgs, ... }: {

  programs.bash.shellAliases = {
    ll = "ls -la --color=auto";
    gcm = "git commit -m";
    scode = "sudo code --user-data-dir --no-sandbox";
  };

  home.packages = [
    (pkgs.writeScriptBin "nix-show" ''
      #!/usr/bin/env bash
      find . -type f -name "*.nix" | while read -r file; do
          echo "$file:"
          cat "$file"
          echo
      done
    '')

    # --- TON NOUVEAU GÉNÉRATEUR D'ENVIRONNEMENT INTELLIGENT ---
    (pkgs.writeShellScriptBin "setup-env" ''
      if [ -z "$1" ]; then
        echo "❌ Usage: setup-env mon_fichier.ext (supporte .py, .c, .cpp, .js, .java)"
        exit 1
      fi

      FILENAME="$1"
      EXTENSION="''${FILENAME##*.}"
      BASENAME="''${FILENAME%.*}"

      if [ -f flake.nix ]; then
        echo "⚠️ Un fichier flake.nix existe déjà ici. Abandon."
        exit 1
      fi

      PACKAGES=""
      BOILERPLATE=""

      # --- SCANNER DE DÉPENDANCES RÉCURSIF ---
      echo "🔍 Analyse récursive du dossier pour détecter les imports..."

      case "$EXTENSION" in
        py)
          # Scan récursif de tous les .py pour trouver les 'import X' ou 'from X import'
          detected_imports=$(grep -rIhE '^(import|from)\s+[a-zA-Z0-9_]' --include="*.py" . 2>/dev/null | awk '{print $2}' | cut -d. -f1 | sort -u)
          
          py_modules=""
          for mod in $detected_imports; do
            case "$mod" in
              # Liste des libs courantes (ajoute tes besoins ici)
              pandas|numpy|requests|matplotlib|scipy|tensorflow|torch|torchvision)
                py_modules="$py_modules $mod"
                ;;
              sklearn)
                py_modules="$py_modules scikit-learn"
                ;;
            esac
          done

          if [ -n "$py_modules" ]; then
            echo "📦 Libs Python détectées :$py_modules"
            PACKAGES="(python3.withPackages (ps: with ps; [ $py_modules ]))"
          else
            PACKAGES="python3"
          fi
          BOILERPLATE="print(\"Hello depuis Python + NixOS !\")"
          ;;

        c|cpp)
          # Scan récursif pour le C/C++ (ex: boost, opencv...)
          extra_libs=""
          if grep -rIq '#include <boost/' --include="*.cpp" --include="*.h" --include="*.c" . 2>/dev/null; then
            echo "📦 Extension C++ détectée : Boost"
            extra_libs="$extra_libs boost"
          fi
          if grep -rIq '#include <opencv2/' --include="*.cpp" --include="*.h" --include="*.c" . 2>/dev/null; then
            echo "📦 Extension C++ détectée : OpenCV"
            extra_libs="$extra_libs opencv"
          fi

          if [ "$EXTENSION" = "c" ]; then
            PACKAGES="gcc gnumake gdb $extra_libs"
            BOILERPLATE="#include <stdio.h>\n\nint main() {\n    printf(\"Hello depuis C !\\n\");\n    return 0;\n}"
          else
            PACKAGES="gcc gnumake cmake gdb $extra_libs"
            BOILERPLATE="#include <iostream>\n\nint main() {\n    std::cout << \"Hello depuis C++ !\\n\";\n    return 0;\n}"
          fi
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

      # --- GÉNÉRATION DES FICHIERS ---

      # 1. Fichier d'exemple si absent
      if [ ! -f "$FILENAME" ]; then
        echo "📝 Création de $FILENAME"
        echo -e "$BOILERPLATE" > "$FILENAME"
      fi

      # 2. Flake Unique et DRY
      echo "❄️ Création du flake.nix..."
      cat << EOF > flake.nix
{
  description = "Environnement auto-généré pour $EXTENSION";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.\''${system};
    in {
      devShells.\''${system}.default = pkgs.mkShell {
        packages = with pkgs; [
          $PACKAGES
        ];
      };
    };
}
EOF

      # 3. Activation Direnv
      echo "⚙️ Configuration de direnv..."
      echo "use flake" > .envrc
      direnv allow || echo "👉 Pense à faire 'direnv allow' si nécessaire."

      echo "✅ Environnement prêt !"
    '')
  ];
}