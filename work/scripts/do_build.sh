#!/bin/bash

if [ ! -e "lib" ]
then
	echo "You must run this script from the root of the project."
	exit 1
fi

python3 ./work/scripts/flutter_check.py ./work/data/project.json

if [ $? -ne 0 ]
then
	echo "Flutter check failed"
	exit 1
fi

# Base directory
BASE_DIR=$(pwd)

# read the "package" value from work/data/project.json
PACKAGE=$(grep '"package"' work/data/project.json | sed -E "s/.*\"package\": \"([^\"]+)\".*/\1/")

# the last part of the package is the app name
APP_NAME=$(echo $PACKAGE | sed -E "s/.*\.([a-z0-9_]+)$/\1/")

echo "Package: $PACKAGE - $APP_NAME"

echo "Switching to prod environment"
cd lib/config
if [ -e env.dart.prod ]
then
	rm env.dart
	ln -s env.dart.prod env.dart
fi
cd $BASE_DIR


if [ -e lib/main.dart.prod ]
then
	cd lib
	cp main.dart main.dart.dev
	cp main.dart.prod main.dart
	cd -
fi

if [ "x$1" == "x" ]
then
	flutter build apk
	cp build/app/outputs/flutter-apk/app-release.apk /ramdisk/$APP_NAME.apk
else
	flutter build apk --debug
	cp build/app/outputs/flutter-apk/app-debug.apk /ramdisk/$APP_NAME-debug.apk
fi

echo "Switching to dev environment"

cd lib/config

if [ -e env.dart.dev ]
then
	rm env.dart
	ln -s env.dart.dev env.dart
fi
cd $BASE_DIR

if [ -e lib/main.dart.dev ]
then
	cd lib
	cp main.dart.dev main.dart
	cd -
fi