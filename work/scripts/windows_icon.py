from PIL import Image
import os


def create_ico():
    # Get the path to the assets folder
    script_dir = os.path.dirname(os.path.abspath(__file__))
    root_dir = os.path.dirname(os.path.dirname(script_dir))
    assets_path = os.path.join(root_dir, "assets", "icons")

    # Load the PNG image
    png_path = os.path.join(assets_path, "head.png")
    if not os.path.exists(png_path):
        print(f"Error: {png_path} not found")
        return

    img = Image.open(png_path)

    # Convert to RGBA if not already
    img = img.convert("RGBA")

    # Create ICO file with multiple sizes
    icon_sizes = [(16, 16), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)]

    ico_path = os.path.join(assets_path, "head.ico")
    img.save(ico_path, format="ICO", sizes=icon_sizes)
    print(f"Created ICO file at: {ico_path}")


if __name__ == "__main__":
    create_ico()
