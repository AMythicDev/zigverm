#!/usr/bin/env python

import sys
import subprocess
import os
import zipfile
from multiprocessing import Pool


def make_release_tarballs():
    VERSION = None
    if VERSION is None:
        process = subprocess.run(
            ["zig", "build", "run-zigverm", "--", "--version"],
            check=True,
            capture_output=True,
        )
        VERSION = process.stdout.decode("utf-8").strip()

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

        with Pool(processes=len(targets)) as pool:
            for target in targets:
                pool.apply_async(make_target_release, [target, VERSION])

            pool.close()
            pool.join()


def make_target_release(target: str, version: str):
    try:
        print(f"Building for {target}")
        target_str = f"{target[0]}-{target[1]}"
        target_dir = "zigverm-" + version + "-" + target_str
        subprocess.run(
            [
                "zig",
                "build",
                "install",
                "--prefix",
                "releases/",
                "--prefix-exe-dir",
                target_dir,
                "--release=safe",
                f"-Dtarget={target_str}",
            ],
            check=True,
            stderr=subprocess.DEVNULL,
        )
        subprocess.run(
            [
                "zig",
                "build",
                "install",
                "--prefix",
                "releases/",
                "--prefix-exe-dir",
                target_dir,
                "--release=safe",
                f"-Dtarget={target_str}",
            ],
            check=True,
            stderr=subprocess.DEVNULL,
        )

        with zipfile.ZipFile(
            "releases/" + target_dir + ".zip",
            "w",
            compression=zipfile.ZIP_DEFLATED,
        ) as z:
            z.write("releases/" + target_dir, target_dir)
            if target[1] == "windows":
                exe_ext = ".exe"
            else:
                exe_ext = ""

            z.write(
                "releases/" + target_dir + "/zigverm" + exe_ext, target_dir + "/zigverm"
            )
            z.write("releases/" + target_dir + "/zig" + exe_ext, target_dir + "/zig")
            z.write("LICENSE", target_dir + "/LICENSE")
            z.write("README.md", target_dir + "/README")
    except subprocess.CalledProcessError as e:
        eprint(
            "\n\n====================================================================================================="
        )
        eprint(
            f"ERROR: Build failed for target '{target}' with exit code {e.returncode}"
        )
        eprint(
            "========================================================================================================="
        )


def eprint(text: str):
    print(f"\x1b[33m{text}", file=sys.stderr)


def main():
    args = sys.argv

    if args[1] == "make-release":
        make_release_tarballs()
    else:
        eprint(f"invalid usage. No such subcommand '{args[1]}'")


if __name__ == "__main__":
    main()
