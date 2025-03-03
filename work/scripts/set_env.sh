#!/bin/bash

if [ "x$1" == "x--prod" ]
then
	prod=1
else
	prod=0
fi

if [ ! -e "lib" ]
then
	cd ..
fi

if [ ! -e "lib" ]
then
	echo "Lanciare lo script dalla root del progetto"
	exit 1
fi

cd lib/config
rm -f env.dart

if [ $prod == "1" ]
then
	ln -s env.dart.prod env.dart
else
	ln -s env.dart.dev env.dart
fi
