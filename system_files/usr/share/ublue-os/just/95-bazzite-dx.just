# vim: set ft=make :

# Configure docker,incus-admin,libvirt, container manager, serial permissions
[group('system')]
dx-group:
    #!/usr/bin/pkexec bash
    append_group() {
        local group_name="$1"
        if ! grep -q "^$group_name:" /etc/group; then
            echo "Appending $group_name to /etc/group"
            grep "^$group_name:" /usr/lib/group | sudo tee -a /etc/group > /dev/null
        fi
    }

    GROUPS_ADD=("docker" "incus-admin" "libvirt" "dialout")

    for GROUP_ADD in "${GROUPS_ADD[@]}" ; do
        append_group $GROUP_ADD
        usermod -aG $GROUP_ADD {{ `id -un` }}
    done

    echo "Reboot system and log back in to use docker, libvirt, incus, and serial connections."

# Install fonts from brew
install-fonts:
    #!/usr/bin/bash
    echo "Installing extra fonts..."
    brew bundle --file=/usr/share/ublue-os/homebrew/bazzite-dx-fonts.Brewfile

# Install local AI tools (llmman) from brew
install-ai-tools:
    #!/usr/bin/bash
    echo "Installing local AI tools..."
    brew bundle --file=/usr/share/ublue-os/homebrew/bazzite-dx-ai.Brewfile

# Manage 1Password and 1Password CLI, including the Firefox Flatpak integration. Options: status | install | uninstall
[group("apps")]
install-1password ACTION="":
    #!/usr/bin/env bash
    set -euo pipefail

    if [[ $(id -u) -eq 0 ]]; then
        echo >&2 "ERROR: Do not run this with sudo"
        exit 1
    fi

    source /usr/lib/ujust/ujust.sh

    # Ensure Homebrew is available in non-interactive shells
    if ! command -v brew >/dev/null 2>&1 && [ -x /home/linuxbrew/.linuxbrew/bin/brew ]; then
        eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
    fi

    CASKS=(1password-gui-linux 1password-cli-linux)

    brew_package() {
        local pkg="$1"
        [[ -d /home/linuxbrew/.linuxbrew/Caskroom/$pkg ]]
    }

    get_status_token() {
        if brew_package 1password-gui-linux && brew_package 1password-cli-linux; then
            echo "install"
        else
            echo "uninstall"
        fi
    }

    get_current_status() {
        if brew_package 1password-gui-linux && brew_package 1password-cli-linux; then
            echo "Installed"
        elif brew_package 1password-gui-linux || brew_package 1password-cli-linux; then
            echo "Partially Installed"
        else
            echo "Not Installed"
        fi
    }

    install_1password() {
        changed=0
        brew_packages=()
        for pkg in "${CASKS[@]}"; do
            if brew_package "$pkg"; then
                echo "$pkg is already installed, skipping."
            else
                brew_packages+=("$pkg")
            fi
        done

        if [ ${#brew_packages[@]} -gt 0 ]; then
            brew trust ublue-os/tap
            brew tap ublue-os/tap
            echo "Installing: ${brew_packages[*]}"
            sudo -v || exit 1
            env -u SUDO_ASKPASS brew install --cask "${brew_packages[@]}"
            changed=1
        fi

        # The CLI cask makes op root:onepassword-cli with setgid so the desktop app
        # accepts it for app integration; re-check in case it was changed since
        local op_bin
        op_bin="$(readlink -f /home/linuxbrew/.linuxbrew/bin/op)"
        if [[ $(stat -c '%U:%G %a' "$op_bin") != "root:onepassword-cli 2755" ]]; then
            echo "Fixing ownership of $op_bin for 1Password app integration"
            getent group onepassword-cli > /dev/null || sudo groupadd onepassword-cli
            sudo chown root:onepassword-cli "$op_bin"
            sudo chmod 2755 "$op_bin"
            changed=1
        fi

        # 1Password only talks to browsers it trusts. Flatpak browsers start BrowserSupport
        # through flatpak-session-helper or, via the WebExtensions portal (default in the
        # Firefox Flatpak), through xdg-native-messaging-proxy
        local allowed_browsers="/etc/1password/custom_allowed_browsers"
        for allowed in flatpak-session-helper xdg-native-messaging-proxy; do
            if ! grep -qxF "$allowed" "$allowed_browsers" 2>/dev/null; then
                echo "Allowing $allowed in $allowed_browsers"
                sudo install -d -m 0755 /etc/1password
                printf '%s\n' "$allowed" | sudo tee -a "$allowed_browsers" > /dev/null
                sudo chmod 0644 "$allowed_browsers"
                changed=1
            fi
        done

        # The portal's proxy runs on the host and reads the regular ~/.mozilla manifest,
        # which the cask and the 1Password app write; nothing is needed inside the sandbox
        if flatpak info org.mozilla.firefox &>/dev/null \
            && [[ ! -f $HOME/.mozilla/native-messaging-hosts/com.1password.1password.json ]]; then
            echo "{{ YELLOW }}Warning:{{ NORMAL }} Firefox native messaging manifest is missing, start the 1Password app once to create it." >&2
        fi

        if [[ $changed -eq 1 ]]; then
            echo 'Complete.'
        else
            echo "No changes were made."
        fi
        echo '{{ YELLOW }}See https://support.1password.com/connect-1password-browser-app/{{ NORMAL }}'
    }

    uninstall_1password() {
        brew_packages=()
        for pkg in "${CASKS[@]}"; do
            if brew_package "$pkg"; then
                brew_packages+=("$pkg")
            fi
        done

        if [ ${#brew_packages[@]} -gt 0 ]; then
            echo "Uninstalling: ${brew_packages[*]}"
            sudo -v || exit 1
            env -u SUDO_ASKPASS brew remove --cask "${brew_packages[@]}"
            echo 'Complete.'
        else
            echo "1Password is not installed."
        fi
    }

    OPTION="{{ ACTION }}"
    if [[ "$OPTION" == "help" ]]; then
        echo "Usage: ujust install-1password <option>"
        echo "  <option>: Specify the quick option to skip the prompt"
        echo "  Use 'status' to print the current portal token"
        echo "  Use 'install' to install 1Password and 1Password CLI"
        echo "  Use 'uninstall' to uninstall 1Password and 1Password CLI"
        exit 0
    elif [[ "$OPTION" == "status" ]]; then
        get_status_token
        exit 0
    elif [[ "$OPTION" == "install" ]]; then
        install_1password
        exit 0
    elif [[ "$OPTION" == "uninstall" ]]; then
        uninstall_1password
        exit 0
    elif [[ -z "$OPTION" ]]; then
        current_status=$(get_current_status)
        echo "${bold}1Password${normal}"
        echo "Current status: $current_status"
        OPTION=$(ugum choose "Install" "Uninstall" "Exit without changes")
        case "$OPTION" in
            "Install")
                install_1password
                ;;
            "Uninstall")
                uninstall_1password
                ;;
            *)
                echo "No changes made."
                ;;
        esac
        exit 0
    fi
