#!/usr/bin/env python3

"""
This script builds the Windows executable for the Woxxy app, reading the APP_VERSION from the lib/config/version.dart file.
This scripts runs the following commands to build the Windows executable:

- flutter clean
- flutter pub get
- flutter build linux --release

then it creates a tar.bz2 the release folder as 'woxxy-$APP_VERSION-linux-x64.tar.bz2' and moves it to the Desktop.

This script must be run from the root of the project.
"""

import os

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

    FINAL_ZIP = f"woxxy-{APP_VERSION}-linux-x64.tar.bz2"


def build_linux():
    os.system("flutter clean")
    os.system("flutter pub get")
    os.system("flutter build linux --release")


def zip_release_folder():
    BASE_DIR = "build/linux/x64/release/bundle"

    # save the current directory
    current_dir = os.getcwd()

    if not os.path.exists(BASE_DIR):
        print("Release folder not found. Please run the build_linux() function first.")
        exit(1)

    os.chdir(BASE_DIR)

    os.system(f"tar cvfj {current_dir}/{FINAL_ZIP} .")
    os.chdir(current_dir)


def move_zip_to_desktop():
    if os.path.exists(os.path.join(os.path.expanduser("~"), "Desktop", FINAL_ZIP)):
        os.unlink(os.path.join(os.path.expanduser("~"), "Desktop", FINAL_ZIP))

    os.rename(FINAL_ZIP, os.path.join(os.path.expanduser("~"), "Desktop", FINAL_ZIP))


if __name__ == "__main__":
    get_app_version()
    build_linux()
    zip_release_folder()
    move_zip_to_desktop()
