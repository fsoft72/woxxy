#!/bin/bash

# This script is called to create a new release of the project.
#
# It changes versions in the project files, creates a new commit
# and then switches to the 'publish' branch and merges the new

# if the flag '--new' is provided, it will create a new release
# otherwise, it will just update the versionCode in android/app/build.gradle
# and compile the app

# Usage:
# ./do_publish.sh --new

if [ ! -e "lib" ]
then
    echo "You must run this script from the root of the project."
    exit 1
fi

# Check that the flag '--new' is provided
newFlag=$1
if [ "$newFlag" != "" ]; then
    if [ "$newFlag" != "--new" ]; then
        echo "Usage: ./do_publish.sh --new"
        exit 1
    fi
fi
# This script only works if we are on the 'master' branch

# Check the current branch
branch=$(git rev-parse --abbrev-ref HEAD)
if [ "$branch" != "master" ]; then
    echo "You must be on the 'master' branch to publish a new release."
    exit 1
fi

# Check that key.properties exists
if [ ! -f "android/key.properties" ]; then
    echo "You must create the file android/key.properties before publishing a new release."
    exit 1
fi

# Check that key.properties storeFile exists and points to a real file
STORE_FILE=$(grep "storeFile=" android/key.properties | sed -E "s/storeFile=(.*)/\1/")
if [ ! -f "$STORE_FILE" ]; then
    echo "The file $STORE_FILE does not exist. Please check the storeFile in android/key.properties."
    exit 1
fi

# Running the check script from the root of the project
python3 ./work/scripts/flutter_check.py ./work/data/project.json --skip-ios --skip-kotlin

if [ $? -ne 0 ]
then
	echo "Flutter check failed"
	exit 1
fi

# read the "package" value from work/data/project.json
PACKAGE=$(grep '"package"' work/data/project.json | sed -E "s/.*\"package\": \"([^\"]+)\".*/\1/")

# the last part of the package is the app name
APP_NAME=$(echo $PACKAGE | sed -E "s/.*\.([a-z0-9_]+)$/\1/")

echo "Package: $PACKAGE - $APP_NAME"

echo "Switching to prod environment"
cd lib/config
rm env.dart
ln -s env.dart.prod env.dart
cd -

rm -Rf build

# We create a new VERSION only if the flag '--new' is provided
if [ "x$newFlag" == "x--new" ]; then
    # Get the current version from pubspec.yaml
    VERSION=$(grep "version:" pubspec.yaml | sed -E "s/.*version: ([0-9.]+).*/\1/")

    # Ask for the app version (default to the current version)
    read -p "App version ($VERSION): " NEW_VERSION
    NEW_VERSION=${NEW_VERSION:-$VERSION}

    # if NEW_VERSION == VERSION, we increment the latest number
    # so 1.0.0 becomes 1.0.1
    if [ "$NEW_VERSION" == "$VERSION" ]; then
        # Get the last number
        LAST_NUMBER=$(echo $VERSION | sed -E "s/.*\.([0-9]+)$/\1/")
        # Increment the last number
        NEW_LAST_NUMBER=$(($LAST_NUMBER + 1))
        # Replace the last number with the new one
        NEW_VERSION=$(echo $VERSION | sed -E "s/(.*\.[0-9]+)\.[0-9]+$/\1.$NEW_LAST_NUMBER/")
    fi

    echo "Creating new release $NEW_VERSION..."

    # Update the version in pubspec.yaml
    sed -i -E "s/^version: [0-9.]+/version: $NEW_VERSION/" pubspec.yaml
else
    VERSION=$(grep "version:" pubspec.yaml | sed -E "s/.*version: ([0-9.]+).*/\1/")
    NEW_VERSION=$VERSION
fi


# Update the versionCode in android/app/build.gradle
# The versionCode is incremented by 1 since the last release

# Get the current versionCode
VERSION_CODE=$(grep "versionCode [0-9]" android/app/build.gradle | sed -E "s/.*versionCode ([0-9]+).*/\1/")
# Increment the versionCode
let NEW_VERSION_CODE=$VERSION_CODE+1
echo "New versionCode: $NEW_VERSION_CODE"
# Replace the versionCode
sed -i -E "s/versionCode [0-9]+/versionCode $NEW_VERSION_CODE/" android/app/build.gradle

# Update the version in lib/config/env.dart
sed -i -E "s/const String APP_VERSION =.*/const String APP_VERSION = '$NEW_VERSION';/" lib/config/version.dart

# Compile the app
flutter build appbundle --release

# Get date in this format 20230323-1200
DATE=$(date +%Y%m%d-%H%M)
cp build/app/outputs/bundle/release/app-release.aab "/ramdisk/$APP_NAME-$DATE.aab"

rm -Rf build

echo "Switching to dev environment"
cd lib/config
rm -f env.dart
ln -s env.dart.dev env.dart
cd -
