#!/bin/sh

VERSION = "0.2.0"

if [[ -z $ZIGVM_ROOT_DIR ]]; then
  ZIGVM_ROOT_DIR=$HOME/.zigvm
fi

if [[ -f $ZIGVM_ROOT_DIR/bin/zigvm ]]; then
  echo "zigvm already available at $ZIGVM_ROOT_DIR. Exitting now" 1>&2;
  exit 0;
fi

mkdir -p $ZIGVM_ROOT_DIR/{downloads,installs,bin}

OS=$(uname -s | awk '{print tolower($0)}')
ARCH=$(uname -m | awk '{print tolower($0)}')

curl -L https://github.com/AMythicDev/zigvm/releases/download/v${VERSION}/zigvm-${VERSION}-${ARCH}-${OS}.zip > /tmp/zigvm.zip
unzip /tmp/zigvm.zip -d /tmp/

mv /tmp/zigvm-${VERSION}-${ARCH}-${OS}/zigvm $ZIGVM_ROOT_DIR/bin
mv /tmp/zigvm-${VERSION}-${ARCH}-${OS}/zig $ZIGVM_ROOT_DIR/bin

echo "Installing zig stable"
$ZIGVM_ROOT_DIR/bin/zigvm install stable
echo "Setting default version to stable"
$ZIGVM_ROOT_DIR/bin/zigvm override default stable

DEFAULT_SHELL=$(getent passwd $USER | awk -F: '{ print($NF) } ' | awk -F/ '{ print ($NF) }')

case $DEFAULT_SHELL in
  "bash")
    echo 'export PATH=$PATH:'$ZIGVM_ROOT_DIR/bin >> $HOME/.bashrc
    ;;
  "zsh")
    echo 'export PATH=$PATH:'$ZIGVM_ROOT_DIR/bin >> $HOME/.zshrc
    ;;
  "fish")
    echo 'set -x PATH=$PATH:'$ZIGVM_ROOT_DIR/bin >> ${XDG_CONFIG_HOME:-$HOME/.config}/fish/config.fish
    ;;
  *)
    echo "Cannot write to shell rc file. Unknown shell" 1>&2;
    echo "You need to manually add {$ZIGVM_ROOT_DIR}/bin to ensure zigvm can be called from anywhere."
    ;;
esac

echo 'export PATH=$PATH:'$ZIGVM_ROOT_DIR/bin/ >> $HOME/.profile

echo -e "\033[0;33;1mzigvm installed successfully\nPlease restart your terminal for changes to take effect.\033[0m"
