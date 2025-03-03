#!/usr/bin/env python3

"""
This script checks various Flutter files and configurations
for building Android and iOS app.

The script takes in input a JSON file with the main info aboutr the app
and verifies if everything is correct.
"""

import argparse
import json
import os

# Create the arg parser. We take in input:
# - the path to the JSON file with the app info

parser = argparse.ArgumentParser(description="Check Flutter app.")
parser.add_argument(
    "app_info",
    metavar="app_info",
    type=str,
    help="path to the JSON file with the app info",
)

# add ios skip flag
parser.add_argument(
    "--skip-ios",
    action="store_true",
    help="skip iOS checks",
)

# add android skip flag
parser.add_argument(
    "--skip-android",
    action="store_true",
    help="skip Android checks",
)

parser.add_argument(
    "--skip-kotlin",
    action="store_true",
    help="skip Kotlin checks",
)

args = parser.parse_args()


# Check that version.dart and pubspec.yaml have the same version number

VERSION_DART = ""
VERSION_PUBSPEC = ""

# Read the version number from version.dart
for line in open("lib/config/version.dart").readlines():
    if "APP_VERSION" in line:
        if "'" in line:
            VERSION_DART = line.split("'")[1]
        elif '"' in line:
            VERSION_DART = line.split('"')[1]
        break

# Read the version number from pubspec.yaml
for line in open("pubspec.yaml").readlines():
    if line.startswith("version:"):
        VERSION_PUBSPEC = line.split(":")[1].strip()
        break

if VERSION_DART != VERSION_PUBSPEC:
    print("Error: version number in version.dart and pubspec.yaml are different")
    print("       version.dart: %s" % VERSION_DART)
    print("       pubspec.yaml: %s" % VERSION_PUBSPEC)
    exit(1)


# Read the JSON file

app_info = json.load(open(args.app_info))

# Check the app name in AndroidManifest.xml

if not args.skip_android:
    android_manifest = open("android/app/src/main/AndroidManifest.xml").read()
    if app_info["name"] not in android_manifest:
        print("Error: app name not found in main / AndroidManifest.xml (android:label)")
        print("       check: android/app/src/main/AndroidManifest.xml")
        exit(1)

    android_debug_manifest = open("android/app/src/debug/AndroidManifest.xml").read()
    if app_info["name"] not in android_manifest:
        print(
            "Error: app name not found in debug / AndroidManifest.xml (android:label)"
        )
        print("       check: android/app/src/debug/AndroidManifest.xml")
        exit(1)

    # Check the package name in AndroidManifest.xml

    if app_info["package"] not in android_manifest:
        print("Error: package name not found in main / AndroidManifest.xml (package)")
        print("       check: android/app/src/main/AndroidManifest.xml")
        exit(1)

    if app_info["package"] not in android_debug_manifest:
        print("Error: package name not found in debug / AndroidManifest.xml (package)")
        print("       check: android/app/src/debug/AndroidManifest.xml")
        exit(1)

    if not args.skip_kotlin:
        # Now check if the package name is reflected in the folder structure
        # Get the directory tree of the android folder

        android_dir_tree = os.walk("android/app/src/main/kotlin/")

        split_package = app_info["package"].split(".")

        # Check if the package name is reflected in the folder structure
        # We check if the package name is in the folder structure
        # and if the folder structure is the same as the package name

        for root, dirs, files in android_dir_tree:
            for dir in dirs:
                if dir not in split_package:
                    print(
                        f"Error: package name not found in folder structure (android/app/src/main/kotlin/{dir})"
                    )
                    exit(1)

        # Check if MainActivity.kt is in the correct folder

        if "MainActivity.kt" not in files:
            print("Error: MainActivity.kt not found in android/app/src/main/kotlin/")
            exit(1)

        # Check if MainActivity.kt contains the correct package name

        dname = "android/app/src/main/kotlin/%s" % app_info["package"].replace(".", "/")

        main_activity = open("%s/MainActivity.kt" % dname).read()

        if app_info["package"] not in main_activity:
            print(
                "Error: package name not found in MainActivity.kt (package %s)"
                % app_info["package"]
            )
            exit(1)

        # Check if MainActivity.kt contains FlutterFragmentActivity
        if "FlutterFragmentActivity" not in main_activity:
            print("Error: FlutterFragmentActivity not found in MainActivity.kt")
            print(
                "       check: android/app/src/main/kotlin/%s/MainActivity.kt" % dname
            )
            exit(1)

    # Check if build.gradle contains the keystoreProperties directives

    build_gradle = open("android/app/build.gradle").read()

    if "keystoreProperties" not in build_gradle:
        print("Error: keystoreProperties not found in android/app/build.gradle")
        print(
            """
    Open android/app/build.gradle and add the following lines before the android { ... } block:

    def keystoreProperties = new Properties()
    def keystorePropertiesFile = rootProject.file('key.properties')
    if (keystorePropertiesFile.exists()) {
        keystoreProperties.load(new FileInputStream(keystorePropertiesFile))
    }
    """
        )
        exit(1)

    # check if build.gradle contains the signingConfigs directives

    if "signingConfigs {" not in build_gradle:
        print("Error: signingConfigs not found in android/app/build.gradle")
        print(
            """
    Open android/app/build.gradle and add the following lines inside the android { ... } block,
    DELETE buildTypes { ... } block and replace everything with:

        signingConfigs {
        release {
            keyAlias keystoreProperties['keyAlias']
            keyPassword keystoreProperties['keyPassword']
            storeFile keystoreProperties['storeFile'] ? file(keystoreProperties['storeFile']) : null
            storePassword keystoreProperties['storePassword']
        }
        }

        buildTypes {
            release {
                signingConfig signingConfigs.release
            }
        }

    """
        )
        exit(1)

    # Check if build.gradle contains the correct applicationId

    if app_info["package"] not in build_gradle:
        print(
            "Error: package name not found in android/app/build.gradle (applicationId %s)"
            % app_info["package"]
        )
        exit(1)

    # Check if build.gradle has a real number in versionCode
    if "flutterVersionCode.toInteger()" in build_gradle:
        print("Error: versionCode must be a real number in android/app/build.gradle")
        print(
            "       check: android/app/build.gradle  - change flutterVersionCode.toInteger() to a real number"
        )
        exit(1)


if not args.skip_ios:
    # Check the app name in Info.plist
    info_plist = open("ios/Runner/Info.plist").read()
    if app_info["name"] not in info_plist:
        print(
            "Error: app name not found in Info.plist (CFBundleDisplayName / CFBundleName)"
        )
        print("       check: ios/Runner/Info.plist")
        exit(1)

    # Check the app name also in ios/Runner.xcodeproj/project.pbxproj

    # We check using the ios-package key
    pname = app_info.get("ios-package", app_info["package"])

    project_pbxproj = open("ios/Runner.xcodeproj/project.pbxproj").read()

    if pname not in project_pbxproj:
        print(
            "Error: app name '%s' not found in ios/Runner.xcodeproj/project.pbxproj (PRODUCT_NAME and PRODUCT_BUNDLE_IDENTIFIER)"
            % pname
        )
        exit(1)
