#!/usr/bin/env python3
"""Slice the approved Ben Dragon sheet and derive the macOS app icon."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Dict, Tuple

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "Resources/DesignSources/ben-dragon-sprite-sheet-transparent.png"
MASCOT_DIR = ROOT / "Resources/Mascot"
APP_ICON = ROOT / "Resources/AppIcon.png"

CELLS = [
    "logo",
    "idle",
    "listening",
    "thinking",
    "working",
    "waitingApproval",
    "success",
    "error",
    "sleep",
]


def alpha_bounds(image: Image.Image) -> Tuple[int, int, int, int]:
    alpha = image.getchannel("A")
    bounds = alpha.point(lambda value: 255 if value > 8 else 0).getbbox()
    if bounds is None:
        raise RuntimeError("sprite cell is fully transparent")
    return bounds


def magenta_pixel_count(image: Image.Image) -> int:
    count = 0
    for red, green, blue, alpha in image.getdata():
        if alpha > 8 and red > 220 and blue > 180 and green < 90:
            count += 1
    return count


def slice_sheet(sheet: Image.Image) -> Dict[str, Dict[str, object]]:
    if sheet.width != sheet.height or sheet.width % 3:
        raise RuntimeError("sprite sheet must be a square 3x3 grid")
    cell_size = sheet.width // 3
    MASCOT_DIR.mkdir(parents=True, exist_ok=True)
    report: Dict[str, Dict[str, object]] = {}

    for index, name in enumerate(CELLS):
        column = index % 3
        row = index // 3
        cell = sheet.crop((
            column * cell_size,
            row * cell_size,
            (column + 1) * cell_size,
            (row + 1) * cell_size,
        ))
        output = MASCOT_DIR / "ben-dragon-{}.png".format(name)
        cell.save(output, format="PNG", optimize=True)
        bounds = alpha_bounds(cell)
        report[name] = {
            "file": output.name,
            "size": [cell.width, cell.height],
            "alphaBounds": list(bounds),
            "opaqueBoundsSize": [bounds[2] - bounds[0], bounds[3] - bounds[1]],
            "magentaPixels": magenta_pixel_count(cell),
        }
    return report


def make_app_icon(logo_cell: Image.Image) -> None:
    canvas = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
    rounded_mask = Image.new("L", canvas.size, 0)
    mask_draw = ImageDraw.Draw(rounded_mask)
    mask_draw.rounded_rectangle((42, 42, 982, 982), radius=220, fill=255)

    background = Image.new("RGBA", canvas.size)
    pixels = background.load()
    for y in range(1024):
        progress = y / 1023
        red = round(18 + 2 * progress)
        green = round(35 + 18 * progress)
        blue = round(42 + 8 * progress)
        for x in range(1024):
            pixels[x, y] = (red, green, blue, 255)
    canvas.paste(background, (0, 0), rounded_mask)

    draw = ImageDraw.Draw(canvas)
    draw.rounded_rectangle((58, 58, 966, 966), radius=205, outline=(91, 225, 165, 120), width=8)
    accent = (39, 115, 177, 150)
    for x, y, size in [(116, 178, 34), (150, 144, 18), (854, 188, 28), (886, 220, 14),
                       (114, 840, 22), (878, 824, 36)]:
        draw.rectangle((x, y, x + size, y + size), fill=accent)

    bounds = alpha_bounds(logo_cell)
    character = logo_cell.crop(bounds)
    character = character.resize((character.width * 2, character.height * 2), Image.Resampling.NEAREST)
    x = (1024 - character.width) // 2
    y = (1024 - character.height) // 2 + 34
    canvas.alpha_composite(character, (x, y))
    canvas.save(APP_ICON, format="PNG", optimize=True)


def main() -> None:
    sheet = Image.open(SOURCE).convert("RGBA")
    report = slice_sheet(sheet)
    logo = Image.open(MASCOT_DIR / "ben-dragon-logo.png").convert("RGBA")
    make_app_icon(logo)

    manifest = {
        "schemaVersion": 1,
        "source": SOURCE.relative_to(ROOT).as_posix(),
        "cellSize": sheet.width // 3,
        "states": report,
        "appIcon": APP_ICON.relative_to(ROOT).as_posix(),
    }
    if any(item["magentaPixels"] for item in report.values()):
        raise RuntimeError("visible chroma-key pixels remain in a sliced asset")
    (MASCOT_DIR / "manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print("Processed {} Ben Dragon cells and {}".format(len(CELLS), APP_ICON))


if __name__ == "__main__":
    main()
