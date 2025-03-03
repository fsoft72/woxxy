#!/usr/bin/env python3

"""
This script uses PIL to copy work/gfx/app-icon.png to
ios/Runner/Assets.xcassets/AppIcon.appiconset
"""

import os
from PIL import Image

# iOS Sizes
ios_sizes = [
    (20, 1),
    (20, 2),
    (20, 3),
    (29, 1),
    (29, 2),
    (29, 3),
    (40, 1),
    (40, 2),
    (40, 3),
    (60, 2),
    (60, 3),
    (76, 1),
    (76, 2),
    (83.5, 2),
    (1024, 1),
]

# Get the path of the logo
logo_path = os.path.join(os.getcwd(), "work", "gfx", "app-icon.png")

# Get the path of the ios project
ios_path = os.path.join(os.getcwd(), "ios")

# Get the path of the Assets.xcassets folder
assets_path = os.path.join(ios_path, "Runner", "Assets.xcassets")

# Get the path of the AppIcon.appiconset folder
appiconset_path = os.path.join(assets_path, "AppIcon.appiconset")

# Load the logo
logo = Image.open(logo_path)

# Cycle through the iOS sizes
for ios_size in ios_sizes:
    # Calculate the new size of the logo based on the width of the splash.png
    size = (
        int(ios_size[0] * ios_size[1]),
        int(ios_size[0] * ios_size[1]),
    )

    print("Creating:", size)

    # Resize the logo
    resized_logo = logo.resize(size)

    # Convert the logo to RGB
    resized_logo = resized_logo.convert("RGB")

    # Create the path of the splash.png file
    splash_path = os.path.join(
        appiconset_path,
        "Icon-App-"
        + str(ios_size[0])
        + "x"
        + str(ios_size[0])
        + "@"
        + str(ios_size[1])
        + "x.jpg",
    )

    # Save the resized logo
    resized_logo.save(splash_path)
