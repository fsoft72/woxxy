#!/usr/bin/env python3

"""
This script uses PIL to copy work/gfx/logo.png in
android/app/src/main/res/drawable-* folders as splash.png
with the correct size for each folder.
"""

import os
from PIL import Image

# Create a dictionary with the sizes of the splash.png files
sizes = {
    "hdpi": 396,
    "mdpi": 264,
    "xhdpi": 528,
    "xxhdpi": 792,
    "xxxhdpi": 1057,
}

# Get the path of the logo
logo_path = os.path.join(os.getcwd(), "work", "gfx", "logo.png")

# Get the path of the android project
android_path = os.path.join(os.getcwd(), "android")

# Get the path of the res folder
res_path = os.path.join(android_path, "app", "src", "main", "res")

# Get the path of the drawable folders
drawable_folders = [
    os.path.join(res_path, folder)
    for folder in os.listdir(res_path)
    if folder.startswith("drawable")
]

# Load the logo
logo = Image.open(logo_path)

# Get original size of the logo
original_size = logo.size

# Cycle through the drawable folders
for drawable_folder in drawable_folders:
    bname = os.path.basename(drawable_folder)
    if bname.find("-") == -1:
        continue

    # Get the path of the splash.png file
    splash_path = os.path.join(drawable_folder, "splash.png")

    # Get the size of the splash.png file
    width = sizes.get(bname.split("-")[1])

    if not width:
        continue

    # Calculate the new size of the logo based on the width of the splash.png
    size = (width, int(width * original_size[1] / original_size[0]))

    # Resize the logo
    resized_logo = logo.resize(size)

    # Save the resized logo as splash.png
    resized_logo.save(splash_path)
