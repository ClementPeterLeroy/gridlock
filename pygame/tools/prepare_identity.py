"""Development-only exports. Requires Pillow, resvg-py, and imageio-ffmpeg.

Use --stickers-only to preserve the current transparent logo and replacement
icon. The full export also rebuilds the older video-derived branding.
"""

from pathlib import Path
import xml.etree.ElementTree as ET
import sys
from PIL import Image, ImageDraw
import imageio_ffmpeg
import resvg_py

ROOT = Path(__file__).resolve().parents[1] / "content" / "px"


def export_stickers():
    ET.register_namespace("", "http://www.w3.org/2000/svg")
    for old, new in (("blue", "sapphire"), ("red", "crimson"),
                     ("green", "emerald"), ("violet", "violet")):
        tree = ET.parse(ROOT / f"{old}_victory.svg")
        root = tree.getroot()
        root.set("aria-label", f"{new.title()} victory template with WINNER trophy")
        trophy = None
        for parent in root.iter():
            for child in list(parent):
                if child.tag.endswith("}rect") and child.get("x") == "380" and child.get("y") == "361":
                    trophy = parent
                if child.tag.endswith("}text") and (child.text or "").strip() != "WINNER":
                    parent.remove(child)
                elif child.tag.endswith("}title"):
                    child.text = f"{new.title()} trophy template"
        winner = next((node for node in root.iter() if node.tag.endswith("}text")
                       and (node.text or "").strip() == "WINNER"), None)
        if winner is None and trophy is not None:
            winner = ET.SubElement(trophy, "{http://www.w3.org/2000/svg}text")
        if winner is not None:
            winner.attrib.update({"x": "450", "y": "385", "text-anchor": "middle",
                                  "font-family": "Lato,sans-serif", "font-size": "21",
                                  "font-weight": "900", "fill": "#3C344D"})
            winner.text = "WINNER"
        svg = "\n".join(line.rstrip() for line in ET.tostring(root, encoding="unicode").splitlines()).rstrip() + "\n"
        (ROOT / f"{new}_victory.svg").write_text(svg, encoding="utf-8")
        (ROOT / f"{new}_victory.png").write_bytes(
            resvg_py.svg_to_bytes(svg_string=svg, width=900, height=520,
                                  font_files=[str(ROOT.parent / "fonts" / "Lato-Regular.ttf")]))


def main():
    export_stickers()
    if "--stickers-only" in sys.argv:
        return

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
