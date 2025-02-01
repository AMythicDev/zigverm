#!/bin/bash

set -e

VERSION="0.6.1"

if [[ -z $ZIGVERM_ROOT_DIR ]]; then
  ZIGVERM_ROOT_DIR=$HOME/.zigverm
fi

if [[ -f $ZIGVERM_ROOT_DIR/bin/zigverm ]]; then
  echo "zigverm already available at $ZIGVERM_ROOT_DIR. Exitting now" 1>&2;
  exit 0;
fi

mkdir -p "$ZIGVERM_ROOT_DIR"/{downloads,installs,bin}

OS="$(uname -s | awk '{print tolower($0)}')"
ARCH="$(uname -m | awk '{print tolower($0)}')"

if [ "${OS}" = "darwin" ]; then
  if [ "${ARCH}" = "x86_64" ] && [ "$(sysctl -in sysctl.proc_translated)" = "1" ]; then
    ARCH="arm64"
  fi
  OS="macos"
fi

if  [ "${ARCH}" = "arm64" ]; then
  ARCH="aarch64"
fi

curl -L https://github.com/AMythicDev/zigverm/releases/download/v${VERSION}/zigverm-${VERSION}-"${ARCH}-${OS}".zip > /tmp/zigverm.zip
unzip /tmp/zigverm.zip -d /tmp/

mv /tmp/zigverm-${VERSION}-"${ARCH}-${OS}"/zigverm "$ZIGVERM_ROOT_DIR/bin"
mv /tmp/zigverm-${VERSION}-"${ARCH}-${OS}"/zig "$ZIGVERM_ROOT_DIR/bin"

echo "Installing zig stable"
"$ZIGVERM_ROOT_DIR"/bin/zigverm install stable
echo "Setting default version to stable"
"$ZIGVERM_ROOT_DIR"/bin/zigverm override default stable

if ! [[ -x "$(command -v zigverm)" ]]; then
    DEFAULT_SHELL=$(getent passwd "$USER" | awk -F: '{ print($NF) } ' | awk -F/ '{ print ($NF) }')

    case $DEFAULT_SHELL in
    "bash")
        # shellcheck disable=SC2016
        echo 'export PATH=$PATH:'"$ZIGVERM_ROOT_DIR/bin" >> "$HOME/.bashrc"
        ;;
    "zsh")
        # shellcheck disable=SC2016
        echo 'export PATH=$PATH:'"$ZIGVERM_ROOT_DIR/bin" >> "$HOME/.zshrc"
        ;;
    "fish")
        # shellcheck disable=SC2016
        echo 'set -x PATH=$PATH:'"$ZIGVERM_ROOT_DIR/bin" >> "${XDG_CONFIG_HOME:-$HOME/.config}/fish/config.fish"
        ;;
    *)
        echo "Cannot write to shell rc file. Unknown shell" 1>&2;
        echo "You need to manually add {$ZIGVERM_ROOT_DIR}/bin to ensure zigverm can be called from anywhere."
        ;;
    esac

    # shellcheck disable=SC2016
    echo 'export PATH=$PATH:'"$ZIGVERM_ROOT_DIR"/bin/ >> "$HOME"/.profile
fi

echo -e "\033[0;33;1mzigverm installed successfully\nPlease restart your terminal for changes to take effect.\033[0m"
