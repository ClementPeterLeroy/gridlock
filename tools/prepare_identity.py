"""Development-only exports. Requires Pillow, resvg-py, and imageio-ffmpeg.

The supplied video is the only logo/icon source in this checkout. Reuse its
final artwork; keep the dark grid opaque because the MP4 has no alpha channel.
"""

from pathlib import Path
import xml.etree.ElementTree as ET
from PIL import Image, ImageDraw
import imageio_ffmpeg
import resvg_py

ROOT = Path(__file__).resolve().parents[1] / "content" / "px"


def main():
    ET.register_namespace("", "http://www.w3.org/2000/svg")
    for old, new in (("blue", "sapphire"), ("red", "crimson"),
                     ("green", "emerald"), ("violet", "violet")):
        tree = ET.parse(ROOT / f"{old}_victory.svg")
        root = tree.getroot()
        root.set("aria-label", f"{new.title()} text-free victory template")
        for parent in root.iter():
            for child in list(parent):
                if child.tag.endswith("}text"):
                    parent.remove(child)
                elif child.tag.endswith("}title"):
                    child.text = f"{new.title()} trophy template"
        svg = "\n".join(line.rstrip() for line in ET.tostring(root, encoding="unicode").splitlines()).rstrip() + "\n"
        (ROOT / f"{new}_victory.svg").write_text(svg, encoding="utf-8")
        (ROOT / f"{new}_victory.png").write_bytes(
            resvg_py.svg_to_bytes(svg_string=svg, width=900, height=520))

    frames = imageio_ffmpeg.read_frames(str(ROOT / "gridlock_startup_storyboard.mp4"))
    try:
        meta = next(frames)
        last = None
        for frame in frames:
            last = frame
    finally:
        frames.close()
    image = Image.frombytes("RGB", meta["size"], last)
    image.crop((36, 118, 924, 422)).save(ROOT / "gridlock_logo.png")
    # Resize existing lock and gem details into a small application icon.
    icon = Image.new("RGB", (128, 128), "white")
    draw = ImageDraw.Draw(icon)
    draw.rectangle((8, 8, 119, 119), fill=(7, 8, 12))
    for coord in range(8, 120, 14):
        draw.line((coord, 8, coord, 119), fill=(67, 54, 30))
        draw.line((8, coord, 119, coord), fill=(67, 54, 30))
    details = [((431, 190, 529, 318), (42, 55), (43, 36)),
               ((441, 117, 519, 195), (24, 24), (52, 8)),
               ((441, 337, 519, 415), (24, 24), (52, 96)),
               ((40, 231, 119, 309), (24, 24), (8, 52)),
               ((841, 231, 920, 309), (24, 24), (96, 52))]
    for box, size, position in details:
        icon.paste(image.crop(box).resize(size, Image.Resampling.LANCZOS), position)
    icon.save(ROOT / "gridlock_icon.png")


if __name__ == "__main__":
    main()
