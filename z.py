#!/usr/bin/env python

import sys
import subprocess
import os
import shutil


VERSION = "0.1.0"


def make_release():
    targets = [
        "aarch64-macos",
        "x86_64-macos",
        "aarch64-linux",
        "x86_64-linux",
        "x86-linux",
        "x86_64-windows",
        "x86-windows",
    ]
    if not os.path.exists("releases"):
        os.mkdir("releases")

    for target in targets:
        print(f"Building for {target}")
        target_dir = "zigvm-" + VERSION + "-" + target
        subprocess.run(["zig", "build", "install", "--prefix", "releases/",
                       "--prefix-exe-dir", target_dir, "--release=safe",
                        f"-Dtarget={target}"])
        shutil.make_archive("releases/" + target_dir,
                            "zip", "releases/" + target_dir)


def main():
    args = sys.argv

    if args[1] == "run":
        subprocess.run(["zig", "build"])
        subprocess.run(["zig-out/bin/" + args[2]] + args[3:])
    elif args[1] == "make-release":
        make_release()


if __name__ == "__main__":
    main()
