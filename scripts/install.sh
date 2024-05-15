#!/bin/sh

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

curl -L https://github.com/AMythicDev/zigvm/releases/download/v0.1.0/zigvm-0.1.0-${ARCH}-${OS} > $ZIGVM_ROOT_DIR/bin/zigvm
chmod 755 $ZIGVM_ROOT_DIR/bin/zigvm 

$ZIGVM_ROOT_DIR/bin/zigvm install stable

DEFAULT_SHELL=$(getent passwd arijit | awk -F: '{ print($NF) } ' | awk -F/ '{ print ($NF) }')

case DEFAULT_SHELL in
  "bash")
    echo 'export PATH=$PATH:'$ZIGVM_ROOT_DIR/bin/ >> $HOME/.bashrc
    ;;
  "zsh")
    echo 'export PATH=$PATH:'$ZIGVM_ROOT_DIR/bin/ >> $HOME/.zshrc
    ;;
  *)
    echo "Cannot write to shell rc file. Unknown shell" 1>&2;
esac

echo 'export PATH=$PATH:'$ZIGVM_ROOT_DIR/bin/ >> $HOME/.profile

echo "zigvm installed successfully"
echo "Please restart your terminal for changes to take effect."
