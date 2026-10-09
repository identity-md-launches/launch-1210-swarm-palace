#!/usr/bin/env python3
"""Validate delivered PNGs; compose review-only thumbnails using ffmpeg.

The logos themselves were drawn by image generation. This script never draws or
modifies them; it validates bytes and places resized copies onto QA proof sheets.
Requires Python 3's standard library and the system ffmpeg, no pip packages.
"""

import hashlib
import json
from pathlib import Path
import struct
import subprocess
import zlib


ROOT = Path(__file__).resolve().parents[1]
PROOFS = ROOT / "artifacts" / "previews"


def inspect_png(path):
    data = path.read_bytes()
    assert data[:8] == b"\x89PNG\r\n\x1a\n", f"{path}: PNG signature"
    offset = 8
    ihdr = None
    saw_end = False
    chunks = []
    while offset < len(data):
        size = struct.unpack_from(">I", data, offset)[0]
        kind = data[offset + 4:offset + 8]
        payload = data[offset + 8:offset + 8 + size]
        crc = struct.unpack_from(">I", data, offset + 8 + size)[0]
        assert zlib.crc32(kind + payload) & 0xFFFFFFFF == crc, f"{path}: invalid CRC"
        chunks.append(kind)
        if kind == b"IHDR":
            ihdr = struct.unpack(">IIBBBBB", payload)
        offset += size + 12
        if kind == b"IEND":
            assert size == 0 and offset == len(data), f"{path}: trailing bytes"
            saw_end = True
            break
    assert saw_end and ihdr is not None and b"IDAT" in chunks, f"{path}: incomplete PNG"
    assert ihdr[:4] == (1024, 1024, 8, 2), f"{path}: expected opaque 1024-square RGB8"
    assert b"tRNS" not in chunks, f"{path}: transparency is not allowed"
    return {
        "path": str(path.relative_to(ROOT)),
        "width": ihdr[0], "height": ihdr[1], "opaque": True,
        "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest(),
    }


def thumbnail(path, size):
    pixels = subprocess.check_output([
        "ffmpeg", "-hide_banner", "-loglevel", "error", "-i", str(path),
        "-vf", f"scale={size}:{size}:flags=lanczos", "-frames:v", "1",
        "-pix_fmt", "rgb24", "-f", "rawvideo", "pipe:1",
    ])
    assert len(pixels) == size * size * 3
    return pixels


def write_png(path, width, height, pixels):
    def chunk(kind, payload):
        return (struct.pack(">I", len(payload)) + kind + payload
                + struct.pack(">I", zlib.crc32(kind + payload) & 0xFFFFFFFF))
    scanlines = b"".join(
        b"\0" + pixels[row * width * 3:(row + 1) * width * 3]
        for row in range(height)
    )
    path.write_bytes(b"\x89PNG\r\n\x1a\n"
                     + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
                     + chunk(b"IDAT", zlib.compress(scanlines, 9)) + chunk(b"IEND", b""))


def paste(pixels, width, source, size, left, top, circle=False):
    for y in range(size):
        for x in range(size):
            # Only the review crop has an antialiased circular mask.
            coverage = 1.0
            if circle:
                coverage = sum(
                    (x + (sx + 0.5) / 4 - size / 2) ** 2
                    + (y + (sy + 0.5) / 4 - size / 2) ** 2 <= (size / 2) ** 2
                    for sy in range(4) for sx in range(4)
                ) / 16
            at = ((top + y) * width + left + x) * 3
            src = (y * size + x) * 3
            for channel in range(3):
                pixels[at + channel] = round(
                    source[src + channel] * coverage + pixels[at + channel] * (1 - coverage)
                )


def main():
    paths = [ROOT / "logos" / f"logo-{i}.png" for i in range(1, 6)]
    selected = ROOT / "artifacts" / "logo.png"
    report = [inspect_png(path) for path in paths + [selected]]
    assert selected.read_bytes() == paths[0].read_bytes(), "selection differs from option 1"
    PROOFS.mkdir(parents=True, exist_ok=True)
    white, dark = bytes((255, 255, 255)), bytes((23, 18, 27))
    width, height = 640, 224
    sheet = bytearray(white * (width * 112) + dark * (width * 112))
    for i, path in enumerate(paths):
        small = thumbnail(path, 64)
        paste(sheet, width, small, 64, i * 128 + 32, 24)
        paste(sheet, width, small, 64, i * 128 + 32, 136)
    write_png(PROOFS / "options-at-64.png", width, height, sheet)
    width, height = 320, 80
    sheet = bytearray((white * 160 + dark * 160) * height)
    small = thumbnail(selected, 32)
    paste(sheet, width, small, 32, 64, 24, circle=True)
    paste(sheet, width, small, 32, 224, 24, circle=True)
    write_png(PROOFS / "selected-at-32.png", width, height, sheet)
    (ROOT / "artifacts" / "asset-check.json").write_text(json.dumps({
        "images": report,
        "generator": "built-in image generation (gpt-image)",
        "draftsGenerated": 5,
        "draftsDiscarded": 0,
        "selectedOption": 1,
        "export": "ffmpeg Lanczos resize from generated 1254x1254 to 1024x1024 RGB PNG",
        "reviewProofs": ["artifacts/previews/options-at-64.png", "artifacts/previews/selected-at-32.png"],
    }, indent=2) + "\n")
    print(json.dumps({"validPNGs": len(report), "size": "1024x1024", "opaque": True,
                      "selectedMatchesOption1": True, "reviewProofsWritten": True}))


if __name__ == "__main__":
    main()
