#!/usr/bin/env python3

"""
This script builds the Windows executable for the Woxxy app, reading the APP_VERSION from the lib/config/version.dart file.
This scripts runs the following commands to build the Windows executable:

- flutter clean
- flutter pub get
- flutter build windows --release

then it zips the release folder as 'woxxy-$APP_VERSION-windows-x64.zip' and moves it to the Desktop.

This script must be run from the root of the project.
"""

import os
import zipfile

APP_VERSION = None
FINAL_ZIP = ""


# check if the script is being run from the root of the project
if not os.path.exists("lib/config/version.dart"):
    print("Please run this script from the root of the project.")
    exit(1)


def get_app_version():
    global APP_VERSION, FINAL_ZIP
    with open("lib/config/version.dart", "r") as f:
        for line in f:
            if "const String APP_VERSION" in line:
                APP_VERSION = line.split("'")[1]
                break

    FINAL_ZIP = f"woxxy-{APP_VERSION}-windows-x64.zip"


def build_windows():
    os.system("flutter clean")
    os.system("flutter pub get")
    os.system("flutter build windows --release")


def zip_release_folder():
    BASE_DIR = "build/windows/x64/runner/Release"
    with zipfile.ZipFile(FINAL_ZIP, "w") as zipf:
        for root, _, files in os.walk(BASE_DIR):
            for file in files:
                print(f"Zipping {os.path.join(root, file)}")
                zipf.write(
                    os.path.join(root, file),
                    os.path.relpath(os.path.join(root, file), BASE_DIR),
                )


def move_zip_to_desktop():
    try:
        os.unlink(os.path.join(os.path.expanduser("~"), "Desktop", FINAL_ZIP))
    except FileNotFoundError:
        pass

    os.rename(FINAL_ZIP, os.path.join(os.path.expanduser("~"), "Desktop", FINAL_ZIP))


if __name__ == "__main__":
    get_app_version()
    build_windows()
    zip_release_folder()
    move_zip_to_desktop()
    print(
        f"Windows executable built and zipped as {FINAL_ZIP} and moved to the Desktop."
    )
