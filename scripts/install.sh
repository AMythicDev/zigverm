#!/bin/sh

if [[ -z $ZIGVM_ROOT_DIR ]]; then
  ZIGVM_ROOT_DIR=$HOME/.zigvm/
fi

mkdir -p $ZIGVM_ROOT_DIR/{downloads,installs,bin}

OS=${uname -s | awk '{print tolower($0)}'}
ARCH=${uname -m | awk '{print tolower($0)}'}

curl -L https://github.com/AMythicDev/zigvm/releases/download/v0.1.0/zigvm-0.1.0-${ARCH}-${OS} > $ZIGVM_ROOT_DIR/bin/zigvm
chmod 755 $ZIGVM_ROOT_DIR/bin/zigvm 

DEFAULT_SHELL=${getent passwd arijit | awk -F: '{ print($NF) } ' | awk -F/ '{ print ($NF) }'}

case DEFAULT_SHELL in
  "bash")
    echo 'export $PATH=$PATH:'$ZIGVM_ROOT_DIR/bin/ >> $HOME/.bashrc
    ;;
  "zsh")
    echo 'export $PATH=$PATH:'$ZIGVM_ROOT_DIR/bin/ >> $HOME/.zshrc
    ;;
  *)
    echo "Cannot write to shell rc file. Unknown shell" 1>&2;
esac

echo 'export $PATH=$PATH:'$ZIGVM_ROOT_DIR/bin/ >> $HOME/.profile

