#!/usr/bin/env python

import sys
import subprocess
import os
import zipfile

VERSION = "0.2.0"

def make_release():
    targets = [
        ["aarch64", "macos"],
        ["x86_64", "macos"],
        ["aarch64", "linux"],
        ["x86_64", "linux"],
        ["x86", "linux"],
        ["x86_64", "windows"],
        ["x86", "windows"],
    ]
    if not os.path.exists("releases"):
        os.mkdir("releases")

    for target in targets:
        print(f"Building for {target}")
        target_str = f"{target[0]}-{target[1]}"
        target_dir = "zigvm-" + VERSION + "-" + target_str
        subprocess.run(["zig", "build", "install", "--prefix", "releases/",
                       "--prefix-exe-dir", target_dir, "--release=safe",
                        f"-Dtarget={target_str}"])

        with zipfile.ZipFile("releases/"+target_dir+".zip", "w") as z:
            z.write("releases/"+target_dir, target_dir);
            if target[1] == "windows":
                exe_ext = ".exe"
            else:
                exe_ext = ""

            z.write("releases/"+target_dir+"/zigvm" +
                    exe_ext, target_dir+"/zigvm")
            z.write("releases/"+target_dir+"/zig"+exe_ext, target_dir+"/zig")


def main():
    args = sys.argv

    if args[1] == "make-release":
        make_release()


if __name__ == "__main__":
    main()
