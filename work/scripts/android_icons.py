#!/usr/bin/env python3

"""
This script uses PIL to copy work/gfx/app-icon.png to
android/app/src/main/res/mipmap-*
"""

import os
from PIL import Image

#  Sizes
icon_sizes = {
    "mipmap-hdpi": 72,
    "mipmap-mdpi": 48,
    "mipmap-xhdpi": 96,
    "mipmap-xxhdpi": 144,
    "mipmap-xxxhdpi": 192,
}

# Get the path of the logo
logo_path = os.path.join(os.getcwd(), "work", "gfx", "app-icon.png")

# Get the path of the ios project
android_path = os.path.join(os.getcwd(), "android")

# Get the path of the Assets.xcassets folder
assets_path = os.path.join(android_path, "app", "src", "main", "res")

# Load the logo
logo = Image.open(logo_path)

# Cycle through the iOS sizes
for name, siz in icon_sizes.items():
    # Calculate the new size of the logo based on the width of the splash.png
    size = ( siz, siz )

    print("Creating:", size)

    # Resize the logo
    resized_logo = logo.resize(size)

    # Convert the logo to RGB
    resized_logo = resized_logo.convert("RGB")

    # Create the path of the splash.png file
    splash_path = os.path.join(
        assets_path,
        name,
        "ic_launcher.png"
    )

    # Save the resized logo
    resized_logo.save(splash_path)

    # Save as foreground
    resized_logo.save(
        os.path.join(
            assets_path,
            name,
            "ic_launcher_fore.png"
        )
    )

    # Save as background
    resized_logo.save(
        os.path.join(
            assets_path,
            name,
            "ic_launcher_back.png"
        )
    )