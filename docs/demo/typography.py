"""Render the original demo's text from fonts at the export resolution.

Matching against the baseline frames keeps text changes, occlusion, and view
transitions in the original animation. No OCR runs during export.
"""

import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont


def row_background(pixels):
    # Use the flat surface color, excluding old antialiasing and compression
    # halos around letters. Quantiles or medians can turn dense strokes into
    # horizontal bands when clearing the old glyphs.
    colors, counts = np.unique(pixels.reshape(-1, 3), axis=0, return_counts=True)
    surface = colors[counts.argmax()]
    rows = []
    for row in pixels:
        colors, counts = np.unique(row, axis=0, return_counts=True)
        color = colors[counts.argmax()]
        rows.append(color if np.abs(color - surface).max() < 12 else surface)
    return np.asarray(rows)[:, None, :]


class RetinaTypography:
    def __init__(self, animation, scale, hud_mask, sans_font, mono_font):
        self.scale = scale
        self.runs = []
        records = json.loads(Path(__file__).with_name("text.json").read_text())
        fonts = {}
        references = {}
        for record in records:
            index = record["frame"]
            if index not in references:
                animation.seek(index)
                reference = animation.convert("RGB")
                references[index] = (reference, hud_mask(reference).getbbox()[0])
            reference, origin = references[index]
            box = tuple(record["box"])
            sample = np.asarray(reference.crop(box)).astype(np.int16)
            background = row_background(sample)
            contrast = np.abs(sample - background).max(axis=2)
            ink = contrast > max(12, contrast.max() * 0.2)
            ys, xs = np.where(ink)
            if not len(xs):
                raise ValueError(f"No reference glyphs for {record['text']}")
            bounds = (xs.min(), ys.min(), xs.max() + 1, ys.max() + 1)
            strongest = contrast >= np.quantile(contrast[ink], 0.9)
            color = tuple(np.median(sample[strongest], axis=0).astype(int))
            key = record.get("font", "sans")
            if key not in fonts:
                mono = key.startswith("mono")
                font = ImageFont.truetype(str(mono_font if mono else sans_font), 128,
                                          index=1 if mono and key.endswith("bold") else 0)
                if not mono and key.endswith("bold"):
                    font.set_variation_by_name("Semibold")
                fonts[key] = font
            font = fonts[key]
            glyph_box = font.getbbox(record["text"])
            glyph = Image.new("L", (glyph_box[2] - glyph_box[0], glyph_box[3] - glyph_box[1]))
            ImageDraw.Draw(glyph).text((-glyph_box[0], -glyph_box[1]), record["text"], font=font, fill=255)
            glyph = glyph.resize(((bounds[2] - bounds[0]) * scale,
                                  (bounds[3] - bounds[1]) * scale), Image.Resampling.LANCZOS)
            clean = np.repeat(background, box[2] - box[0], axis=1).astype(np.uint8)
            patch = Image.fromarray(clean).resize(((box[2] - box[0]) * scale,
                                                  (box[3] - box[1]) * scale), Image.Resampling.BILINEAR)
            patch.paste(color, (int(bounds[0]) * scale, int(bounds[1]) * scale), glyph)
            self.runs.append((record, sample, origin, patch))

    def render(self, frame, current_origin):
        result = frame.resize((frame.width * self.scale, frame.height * self.scale), Image.Resampling.LANCZOS)
        pixels = np.asarray(frame).astype(np.int16)
        painted = set()
        for record, sample, origin, patch in self.runs:
            x0, y0, x1, y1 = record["box"]
            shift = current_origin - origin if record.get("hud") else 0
            x0, x1 = x0 + shift, x1 + shift
            if x0 < 0 or x1 > frame.width:
                continue
            key = (x0, y0, x1, y1)
            if key in painted:
                continue
            current = pixels[y0:y1, x0:x1]
            # Repaint only when the baseline glyphs are present. During fades,
            # scrolling, pointer overlap, or occlusion, retain that exact frame.
            if np.abs(current - sample).mean() > 1.25:
                continue
            painted.add(key)
            result.paste(patch, (x0 * self.scale, y0 * self.scale))
        return result
