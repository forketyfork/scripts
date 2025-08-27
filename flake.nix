{
  description = "Collection of utility scripts with comprehensive dependencies";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            # Core system tools
            bash
            coreutils
            findutils
            gnugrep
            gnused
            gawk
            
            # Audio processing
            ffmpeg
            
            # Video downloads
            yt-dlp
            
            # Encryption
            age
            
            # Cloud storage
            rclone
            
            # Shell tools
            shfmt
            shellcheck
            
            # Git
            git
            
            # Python 3.12 (for coremltools compatibility)
            python312
            python312Packages.pip
            python312Packages.virtualenv
            
            # macOS specific (conditionally included)
            terminal-notifier
            
            # Development tools
            direnv
          ];

          shellHook = ''
            echo "🚀 Scripts development environment loaded!"
            echo ""
            echo "Available tools:"
            echo "  Audio: ffmpeg, whisper.cpp (build required)"
            echo "  Video: yt-dlp"
            echo "  Crypto: age"
            echo "  Cloud: rclone"
            echo "  Shell: shfmt, shellcheck"
            echo "  Python: $(python3 --version) (Python 3.12 for coremltools compatibility)"
            echo ""
            echo "Note: whisper.cpp needs to be built separately in ~/dev/github/ggml-org/whisper.cpp"
            echo "Run ./whisper-rebuild.sh to build it with Core ML support"
            echo ""
            
            # Set up git hooks if not already configured
            if [ ! -f .git/hooks/pre-commit ]; then
              echo "Setting up git hooks..."
              git config --local core.hooksPath hooks
            fi
            
            # Create .env file template if it doesn't exist
            if [ ! -f .env ]; then
              echo "Creating .env template..."
              cat > .env << 'EOF'
# GitHub token for artifact_downloads.py (optional but recommended)
# Get from: https://github.com/settings/tokens
GITHUB_TOKEN=your_token_here

# Zettelkasten vault directory (for backup scripts)
ZETTELKASTEN_DIR=$HOME/Documents/Zettelkasten

# Google Drive remote for rclone (configure with: rclone config)
GDRIVE_REMOTE=gdrive:backups
EOF
              echo "Please edit .env with your configuration"
            fi
          '';
        };

        # Make individual scripts available as packages
        packages = {
          sr = pkgs.writeShellApplication {
            name = "sr";
            runtimeInputs = with pkgs; [ ffmpeg python312 python312Packages.virtualenv ];
            text = builtins.readFile ./sr.sh;
          };
          
          backup-zettelkasten = pkgs.writeShellApplication {
            name = "backup-zettelkasten";
            runtimeInputs = with pkgs; [ age rclone terminal-notifier ];
            text = builtins.readFile ./backup-zettelkasten.sh;
          };
          
          decrypt-zettelkasten = pkgs.writeShellApplication {
            name = "decrypt-zettelkasten";
            runtimeInputs = with pkgs; [ age ];
            text = builtins.readFile ./decrypt-zettelkasten.sh;
          };
          
          youtube-to-srt = pkgs.writeShellApplication {
            name = "youtube-to-srt";
            runtimeInputs = with pkgs; [ yt-dlp ffmpeg ];
            text = builtins.readFile ./youtube-to-srt.sh;
          };
          
          bookmarks = pkgs.writeShellApplication {
            name = "bookmarks";
            runtimeInputs = with pkgs; [ ];
            text = builtins.readFile ./bookmarks.sh;
          };
          
          whisper-rebuild = pkgs.writeShellApplication {
            name = "whisper-rebuild";
            runtimeInputs = with pkgs; [ git python312 python312Packages.virtualenv python312Packages.pip ];
            text = builtins.readFile ./whisper-rebuild.sh;
          };
        };
      }
    );
}
