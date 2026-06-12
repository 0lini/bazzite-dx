#!/usr/bin/bash
set -xeou pipefail

BREWFILE="/usr/share/ublue-os/homebrew/bazzite-dx.Brewfile"
TARBALL="/usr/share/homebrew.tar.zst"
EXTRACT_DIR="/tmp/brew-extract"
REPACK_DIR="/tmp/brew-repack"

# Extract the base homebrew tarball shipped by the base image
mkdir -p "$EXTRACT_DIR"
tar --zstd -xf "$TARBALL" -C "$EXTRACT_DIR"

# Create a non-root user for running brew (brew refuses to run as root)
# Guard against linuxbrew already existing in the base image
id linuxbrew &>/dev/null || useradd -m linuxbrew
mkdir -p /home/linuxbrew

# Populate the user's home with the extracted homebrew
cp -R "$EXTRACT_DIR/home/linuxbrew/.linuxbrew" /home/linuxbrew/
chown -R linuxbrew:linuxbrew /home/linuxbrew/

# Install packages — allow partial failures so a single bad package
# doesn't abort the entire image build
runuser -u linuxbrew -- env \
    HOME=/home/linuxbrew \
    USER=linuxbrew \
    HOMEBREW_NO_AUTO_UPDATE=1 \
    HOMEBREW_NO_ANALYTICS=1 \
    HOMEBREW_NO_ENV_HINTS=1 \
    /home/linuxbrew/.linuxbrew/bin/brew bundle \
    --file="$BREWFILE" \
    --no-lock || echo "Warning: some brew packages failed to install"

# Re-pack the modified homebrew, preserving the original tarball structure
mkdir -p "$REPACK_DIR/home/linuxbrew"
cp -R /home/linuxbrew/.linuxbrew "$REPACK_DIR/home/linuxbrew/"
tar --zstd -cf "${TARBALL}.new" -C "$REPACK_DIR" home
mv "${TARBALL}.new" "$TARBALL"

# Cleanup — failures here must not abort the build
userdel -r linuxbrew 2>/dev/null || true
rm -rf "$EXTRACT_DIR" "$REPACK_DIR"
