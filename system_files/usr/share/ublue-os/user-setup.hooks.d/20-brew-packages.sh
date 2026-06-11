#!/usr/bin/bash

source /usr/lib/ublue/setup-services/libsetup.sh

version-script brew-packages-dx user 1 || exit 1

set -x

BREW_BIN="/home/linuxbrew/.linuxbrew/bin/brew"

if [[ ! -x "$BREW_BIN" ]]; then
    echo "Homebrew not found at $BREW_BIN, skipping brew package installation"
    exit 0
fi

eval "$("$BREW_BIN" shellenv)"

brew bundle --file=/usr/share/ublue-os/homebrew/bazzite-dx.Brewfile --no-lock
