#!/usr/bin/env bash


export DEBIAN_FRONTEND=noninteractive

symlink() {
  # A symlink function that makes sure the target symlink's parent path
  # exists.

  # Expand ~ to $HOME if present
  local source="${1/#\~/$HOME}"
  local target="${2/#\~/$HOME}"

  [[ -e ${target} ]] && echo "'${target}' exists, skipping" && return

  mkdir -p "$(dirname ${target})"
  ln -s "${source}" "${target}"
}


install_prerequisites() {
  if [[ $(uname) == "Linux" ]]; then
    echo "Installing prerequisites"
    sudo -E apt -yqq update
    sudo -E apt -yqq install \
        curl \
        git \
        python3-launchpadlib \
        software-properties-common
  fi
}


setup_dotfiles_repo() {
  # Here's a nice place to add binaries
  local local_bin="${HOME}/.local/bin"
  mkdir -p "${local_bin}"

  # Set up the dotfiles repository
  local workspace_dir="${HOME}/workspace"
  local dotfiles_dir="${workspace_dir}/dotfiles"
  mkdir -p "${workspace_dir}"

  # Attempt to clone the repo if it doesnt exist on disk yet
  if [[ -d "${dotfiles_dir}" ]]; then
    echo "dotfiles folder already exists, skipping"
  else
    {
      git clone --recursive git@github.com:philipforget/dotfiles.git "${dotfiles_dir}"
    } || {
      echo "Unable to clone via ssh, falling back to https"
      git clone --recursive https://github.com/philipforget/dotfiles.git "${dotfiles_dir}"
    }
  fi

  # Set up symlinks
  symlink "${dotfiles_dir}/aliases" ~/.aliases
  symlink "${dotfiles_dir}/aliases_linux" ~/.aliases_linux
  symlink "${dotfiles_dir}/aliases_mac" ~/.aliases_mac
  symlink "${dotfiles_dir}/bash_custom" ~/.bash_custom
  symlink "${dotfiles_dir}/bash_linux" ~/.bash_linux
  symlink "${dotfiles_dir}/bash_mac" ~/.bash_mac
  symlink "${dotfiles_dir}/distraction" ~/.distraction
  symlink "${dotfiles_dir}/tmux" ~/.config/tmux
  symlink "${dotfiles_dir}/vim" ~/.vim
  symlink "${dotfiles_dir}/nvim" ~/.config/nvim
  symlink "${dotfiles_dir}/xmodmap" ~/.xmodmap
  symlink "${dotfiles_dir}/mise.toml" ~/.config/mise/config.toml

  symlink "${dotfiles_dir}/sync-authorized-keys" "${local_bin}/sync-authorized-keys"

  # Delete the system-installed .gitconfig first if it exists
  rm "${HOME}/.gitconfig" || 1
  symlink "${dotfiles_dir}/gitconfig" ~/.gitconfig

  if [[ $(uname) == "Darwin" ]]; then
    # Mac only symlinks
    symlink "${dotfiles_dir}/com.knollsoft.Rectangle.plist" "${HOME}/Library/Preferences/com.knollsoft.Rectangle.plist"
    symlink "${dotfiles_dir}/docker_config.mac.json" ~/.docker/config.json
  fi
  if [[ $(uname) == "Linux" ]]; then
    # Linux only symlinks
    symlink "${dotfiles_dir}/docker_config.json" ~/.docker/config.json
  fi

  # Add sourcing of ~/.bash_custom to .bashrc and .profile if not present
  if ! grep -Fxq 'source ~/.bash_custom' "${HOME}/.bashrc"; then
    echo 'source ~/.bash_custom' >>"${HOME}/.bashrc"
  fi
  if ! grep -Fxq 'source ~/.bash_custom' "${HOME}/.profile"; then
    echo 'source ~/.bash_custom' >>"${HOME}/.profile"
  fi
}

setup_system() {
  # Here's a nice place to add binaries
  local local_bin="${HOME}/.local/bin"
  mkdir -p "${local_bin}"

  if [[ $(uname) == "Darwin" ]]; then
    # On MacOS, install and use brew package manager
    if ! which brew &>/dev/null; then
      echo 'Installing brew package manager: https://brew.sh/'
      echo 'Requires user password'
      /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    fi

    echo "Installing packages with brew"
    brew install \
      age \
      bash \
      bash-completion \
      git \
      git-lfs \
      mise \
      mosh \
      ripgrep \
      shellcheck \
      sops \
      tmux \
      vim

    git lfs install

    brew install --cask \
      1password \
      docker \
      google-chrome \
      microsoft-remote-desktop \
      rectangle \
      signal \
      wezterm

    # Set the brew-installed bash as the default shell
    brew_bash="$(brew --prefix)/bin/bash"
    # Bail early if ${brew_bash} doesn't exist for any reason
    if [[ ! -f "${brew_bash}" ]]; then
      echo "Unable to set brew-installed bash as shell!"
    else
      echo "Adding ${brew_bash} to /etc/shells if not present"
      grep "${brew_bash}" /etc/shells &>/dev/null || echo "${brew_bash}" | sudo tee -a /etc/shells
      if [[ "${SHELL}" != "${brew_bash}" ]]; then
        chsh -s "${brew_bash}" "$(whoami | xargs echo -n)"
      fi
    fi

    # Add ssh agent to system keychain on first unlock
    ssh_agent_config="AddKeysToAgent yes"
    grep "${ssh_agent_config}" ~/.ssh/config &>/dev/null || echo "${ssh_agent_config}" >>~/.ssh/config

  else
    if grep -qE "Ubuntu|Debian|Raspbian" /etc/issue; then
      echo "Installing required packages"
      # Use sudo -E to inherit our current environment, including
      # DEBIAN_FRONTEND set above
      sudo -E apt-get -qq update
      sudo -E apt-get -qq install -y \
        --no-install-recommends \
        age \
        bash-completion \
        build-essential \
        curl \
        curl \
        dnsutils \
        git \
        git-lfs \
        libbz2-dev \
        libffi-dev \
        liblzma-dev \
        libncursesw5-dev \
        libreadline-dev \
        libsqlite3-dev \
        libssl-dev \
        libxml2-dev \
        libxmlsec1-dev \
        llvm \
        ripgrep \
        shellcheck \
        tk-dev \
        tmux \
        vim-nox \
        xz-utils \
        zlib1g-dev

      git lfs install

      # Install sops from github releases
      curl -L \
        https://github.com/getsops/sops/releases/download/v3.8.1/sops-v3.8.1.linux.amd64 \
        -o "${local_bin}/sops" && chmod +x "${local_bin}/sops"

    fi
  fi
}

setup_mise() {
  # Install mise from their install script
  curl https://mise.run | sh
  eval "$(${HOME}/.local/bin/mise activate bash)"
  mise trust ~/.config/mise/config.toml

  mise plugin add usage
  mise use -g python@3.12

  mise install -y neovim
  mise use -g neovim

  python3 -m pip install \
    ipython \
    requests
}

sync_public_keys() {
  mkdir -p "${HOME}/.ssh"
  curl -L "https://github.com/${1}" >>"${HOME}/.ssh/authorized_keys"
}

init() {
  install_prerequisites

  local github_username="${1:-philipforget}"
  sync_public_keys "${github_username}"

  setup_system
  setup_dotfiles_repo
  setup_mise

  exec bash
}

# When piping in from stdin (eg curl), BASH_SOURCE[0] will be unset, and
# when executing via ./init.sh or bash init.sh, BASH_SOURCE[0] and ${0}
# will be equal
if [ "${BASH_SOURCE[0]}" == "${0}" ] || [ -z "${BASH_SOURCE[0]}" ]; then
  # Tell bash to fail immediately on any error as well as unset variables
  set -eu -o pipefail
  init "$@"
fi
