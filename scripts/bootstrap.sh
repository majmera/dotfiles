#!/usr/bin/env bash
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${DOTFILES_DIR}"

echo "==> Stowing dotfiles packages..."
PACKAGES=(bash config devin emacs tmux zsh)
for pkg in "${PACKAGES[@]}"; do
    if [[ -d "$pkg" ]]; then
        echo "  - Stowing $pkg"
        stow -R "$pkg"
    fi
done

echo "==> Setting up plugins..."

# Tmux: Clone TPM if not already installed
if [[ ! -d "${HOME}/.tmux/plugins/tpm" ]]; then
    echo "  - Cloning TPM (Tmux Plugin Manager)..."
    git clone https://github.com/tmux-plugins/tpm "${HOME}/.tmux/plugins/tpm" || true
    if [[ -f "${HOME}/.tmux/plugins/tpm/bin/install_plugins" ]]; then
        echo "  - Installing Tmux plugins..."
        "${HOME}/.tmux/plugins/tpm/bin/install_plugins" || true
    fi
fi

# Herdr: Install herdr plugins if herdr is installed
if command -v herdr >/dev/null 2>&1; then
    echo "  - Installing Herdr plugins..."
    herdr plugin install -y dwarvesf/herdr-quicklook || true
else
    echo "  - Note: herdr not installed yet. When installed, run:"
    echo "      herdr plugin install -y dwarvesf/herdr-quicklook"
fi

echo "==> Dotfiles setup complete!"
echo "Note:"
echo "  - Emacs will auto-install ELPA/MELPA packages on its first launch."
echo "  - Zsh will auto-install Zinit and plugins on its first launch."
