"""Minimal PNG read/write so export can split packed maps without Pillow."""

from __future__ import annotations

import struct
import zlib
from pathlib import Path


def _chunk(kind: bytes, data: bytes) -> bytes:
    c = kind + data
    return struct.pack(">I", len(data)) + c + struct.pack(">I", zlib.crc32(c) & 0xFFFFFFFF)


def write_rgba(path: Path, width: int, height: int, pixels: bytes) -> None:
    """`pixels` is top-down RGBA8, `width * height * 4` bytes."""
    if len(pixels) != width * height * 4:
        raise ValueError(f"rgba length {len(pixels)} != {width * height * 4}")
    _write(path, width, height, 6, pixels, 4)


def write_rgb(path: Path, width: int, height: int, pixels: bytes) -> None:
    if len(pixels) != width * height * 3:
        raise ValueError(f"rgb length {len(pixels)} != {width * height * 3}")
    _write(path, width, height, 2, pixels, 3)


def write_gray_as_rgb(path: Path, width: int, height: int, gray: bytes) -> None:
    """One channel expanded to RGB (visu samples `.r` on roughness / metal / alpha)."""
    if len(gray) != width * height:
        raise ValueError(f"gray length {len(gray)} != {width * height}")
    rgb = bytearray(width * height * 3)
    for i, v in enumerate(gray):
        o = i * 3
        rgb[o] = v
        rgb[o + 1] = v
        rgb[o + 2] = v
    write_rgb(path, width, height, bytes(rgb))


def _write(path: Path, width: int, height: int, color: int, pixels: bytes, bpp: int) -> None:
    raw = b""
    row = width * bpp
    for y in range(height):
        raw += b"\x00" + pixels[y * row : (y + 1) * row]
    ihdr = struct.pack(">IIBBBBB", width, height, 8, color, 0, 0, 0)
    path.write_bytes(
        b"\x89PNG\r\n\x1a\n"
        + _chunk(b"IHDR", ihdr)
        + _chunk(b"IDAT", zlib.compress(raw, 9))
        + _chunk(b"IEND", b"")
    )


def read(path: Path) -> tuple[int, int, int, bytes]:
    """Return width, height, bytes-per-pixel, top-down pixels (1 / 3 / 4 bpp)."""
    data = path.read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError(f"{path}: not a PNG")
    i = 8
    width = height = color = 0
    idat = b""
    while i < len(data):
        n = int.from_bytes(data[i : i + 4], "big")
        kind = data[i + 4 : i + 8]
        chunk = data[i + 8 : i + 8 + n]
        i += 12 + n
        if kind == b"IHDR":
            width, height, bit, color, *_ = struct.unpack(">IIBBBBB", chunk)
            if bit != 8 or color not in (0, 2, 4, 6):
                raise ValueError(f"{path}: unsupported png")
        elif kind == b"IDAT":
            idat += chunk
        elif kind == b"IEND":
            break
    bpp = {0: 1, 2: 3, 4: 2, 6: 4}[color]
    raw = zlib.decompress(idat)
    stride = width * bpp
    rows: list[bytearray] = []
    off = 0
    for _y in range(height):
        filt = raw[off]
        off += 1
        row = bytearray(raw[off : off + stride])
        off += stride
        _paeth_unfilter(filt, row, rows[-1] if rows else None, bpp)
        rows.append(row)
    return width, height, bpp, b"".join(rows)


def channel(pixels: bytes, bpp: int, index: int) -> bytes:
    if index < 0 or index >= bpp:
        raise ValueError(f"channel {index} not in 0..{bpp - 1}")
    return bytes(pixels[i] for i in range(index, len(pixels), bpp))


def _paeth_unfilter(filt: int, row: bytearray, prev: bytearray | None, bpp: int) -> None:
    if filt == 0:
        return
    prior = prev if prev is not None else bytes(len(row))
    if filt == 1:
        for x in range(bpp, len(row)):
            row[x] = (row[x] + row[x - bpp]) & 255
        return
    if filt == 2:
        for x in range(len(row)):
            row[x] = (row[x] + prior[x]) & 255
        return
    if filt == 3:
        for x in range(len(row)):
            left = row[x - bpp] if x >= bpp else 0
            row[x] = (row[x] + ((left + prior[x]) // 2)) & 255
        return
    if filt == 4:
        for x in range(len(row)):
            a = row[x - bpp] if x >= bpp else 0
            b = prior[x]
            c = prior[x - bpp] if x >= bpp else 0
            p = a + b - c
            pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
            pr = a if pa <= pb and pa <= pc else (b if pb <= pc else c)
            row[x] = (row[x] + pr) & 255
        return
    raise ValueError(f"png filter {filt}")
