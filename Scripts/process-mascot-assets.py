#!/usr/bin/env python3
"""Slice the approved Ben Dragon sheets and derive the macOS app icon."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Dict, Tuple

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parent.parent
PRIMARY_SOURCE = ROOT / "Resources/DesignSources/ben-dragon-sprite-sheet-transparent.png"
MASCOT_DIR = ROOT / "Resources/Mascot"
APP_ICON = ROOT / "Resources/AppIcon.png"

SHEETS = [
    (
        PRIMARY_SOURCE,
        [
            "logo",
            "idle",
            "listening",
            "thinking",
            "working",
            "waitingApproval",
            "success",
            "error",
            "sleep",
        ],
    ),
    (
        ROOT / "Resources/DesignSources/ben-dragon-ambient-everyday-transparent.png",
        [
            "cameraReady",
            "cameraShutter",
            "walkLeft",
            "walkRight",
            "teaHold",
            "teaSip",
            "daydream",
            "cloudWatch",
            "rest",
        ],
    ),
    (
        ROOT / "Resources/DesignSources/ben-dragon-ambient-hobbies-transparent.png",
        [
            "read",
            "music",
            "waterFlower",
            "snack",
            "stretch",
            "sketch",
            "rain",
            "stargaze",
            "bubbles",
        ],
    ),
]


def alpha_bounds(image: Image.Image) -> Tuple[int, int, int, int]:
    alpha = image.getchannel("A")
    bounds = alpha.point(lambda value: 255 if value > 8 else 0).getbbox()
    if bounds is None:
        raise RuntimeError("sprite cell is fully transparent")
    return bounds


def magenta_pixel_count(image: Image.Image) -> int:
    count = 0
    pixels = image.get_flattened_data() if hasattr(image, "get_flattened_data") else image.getdata()
    for red, green, blue, alpha in pixels:
        if alpha > 8 and red > 220 and blue > 180 and green < 90:
            count += 1
    return count


def slice_sheet(sheet: Image.Image, cells: list[str]) -> Dict[str, Dict[str, object]]:
    if sheet.width != sheet.height or sheet.width % 3:
        raise RuntimeError("sprite sheet must be a square 3x3 grid")
    if len(cells) != 9:
        raise RuntimeError("sprite sheet must declare exactly 9 cells")
    cell_size = sheet.width // 3
    MASCOT_DIR.mkdir(parents=True, exist_ok=True)
    report: Dict[str, Dict[str, object]] = {}

    for index, name in enumerate(cells):
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
    report: Dict[str, Dict[str, object]] = {}
    cell_sizes = set()
    for source, cells in SHEETS:
        sheet = Image.open(source).convert("RGBA")
        cell_sizes.add(sheet.width // 3)
        report.update(slice_sheet(sheet, cells))

    logo = Image.open(MASCOT_DIR / "ben-dragon-logo.png").convert("RGBA")
    make_app_icon(logo)

    manifest = {
        "schemaVersion": 2,
        "sources": [source.relative_to(ROOT).as_posix() for source, _ in SHEETS],
        "cellSizes": sorted(cell_sizes),
        "states": report,
        "appIcon": APP_ICON.relative_to(ROOT).as_posix(),
    }
    if any(item["magentaPixels"] for item in report.values()):
        raise RuntimeError("visible chroma-key pixels remain in a sliced asset")
    (MASCOT_DIR / "manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print("Processed {} Ben Dragon cells and {}".format(len(report), APP_ICON))


if __name__ == "__main__":
    main()
