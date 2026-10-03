"""Generate Flutter launcher icons from logo.png. Requires Pillow."""

import json
from pathlib import Path

from PIL import Image, ImageOps

ROOT = Path(__file__).resolve().parent.parent
source = Image.open(ROOT / "logo.png").convert("RGBA")
# Ignore the source's almost-transparent halo when measuring the visible logo.
bounds = source.getchannel("A").point(lambda alpha: 255 if alpha > 20 else 0).getbbox()
if bounds is None:
    raise ValueError("logo.png has no visible pixels")
left, top, right, bottom = bounds
logo = source.crop((max(0, left - 4), max(0, top - 4), min(source.width, right + 4), min(source.height, bottom + 4)))


def render(size, fraction, transparent=False):
    canvas = Image.new("RGBA", (size, size), (255, 255, 255, 0 if transparent else 255))
    content = ImageOps.contain(logo, (round(size * fraction),) * 2, Image.Resampling.LANCZOS)
    canvas.alpha_composite(content, ((size - content.width) // 2, (size - content.height) // 2))
    return canvas if transparent else canvas.convert("RGB")


def save(image, path):
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path, optimize=True)


master = render(1024, 0.84)
save(master, ROOT / "mobile/assets/app-icon.png")
res = ROOT / "mobile/android/app/src/main/res"
for density, scale in {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}.items():
    save(master.resize((int(48 * scale),) * 2, Image.Resampling.LANCZOS), res / f"mipmap-{density}/ic_launcher.png")
    # Adaptive icons use a 108dp layer; the 64dp logo fits inside its safe zone.
    save(render(int(108 * scale), 64 / 108, transparent=True), res / f"mipmap-{density}/ic_launcher_foreground.png")

ios = ROOT / "mobile/ios/Runner/Assets.xcassets/AppIcon.appiconset"
for item in json.loads((ios / "Contents.json").read_text())["images"]:
    size = round(float(item["size"].split("x")[0]) * float(item["scale"].removesuffix("x")))
    save(master.resize((size, size), Image.Resampling.LANCZOS), ios / item["filename"])

web = ROOT / "mobile/web"
for size in (192, 512):
    save(master.resize((size, size), Image.Resampling.LANCZOS), web / f"icons/Icon-{size}.png")
    save(render(size, 0.76), web / f"icons/Icon-maskable-{size}.png")
save(master.resize((32, 32), Image.Resampling.LANCZOS), web / "favicon.png")
print("Generated Android, iOS and Flutter Web icons from logo.png")
