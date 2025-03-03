#!/usr/bin/env python3

"""
This script takes images from work/gfx/ios/6_7
and creates the images for 6.5" in the 6_5 folder and 5_5 folder
using PIL
"""

import os
from PIL import Image

# Create the list of images to process

images = os.listdir("work/gfx/ios/screens")

# List of target directories and resolutions
targets = {
    "6_7": (1290, 2796),
    "6_5": (1242, 2688),
    "5_5": (1242, 2208),
}

for target, size in targets.items():
    # Create the output folder if it does not exist

    dest_path = f"work/gfx/ios/{target}"

    if not os.path.exists(dest_path):
        os.makedirs(dest_path)

    # Process the images

    for image in images:
        if image.startswith("."):
            continue

        # Open the image

        im = Image.open(f"work/gfx/ios/screens/{image}")

        # Resize the image

        im = im.resize(size)

        # Save the image
        im.save(f"{dest_path}/{image}")
