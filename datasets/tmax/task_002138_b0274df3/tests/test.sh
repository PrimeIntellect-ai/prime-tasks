#!/bin/bash
mkdir -p /logs/verifier

if (
    set -e
    project=/home/user/ode_fitter

    test -d "$project"
    test -f "$project/Cargo.toml"

    cd "$project"
    cargo metadata --no-deps --format-version 1 > /tmp/ode_fitter_metadata.json

    python3 - <<'PY'
import json
import os

project = os.path.realpath('/home/user/ode_fitter')
with open('/tmp/ode_fitter_metadata.json', 'r', encoding='utf-8') as f:
    metadata = json.load(f)

packages = [
    p for p in metadata.get('packages', [])
    if os.path.realpath(os.path.dirname(p['manifest_path'])) == project
]
assert packages, 'Cargo metadata contains no package rooted at /home/user/ode_fitter'
assert any('bin' in target.get('kind', []) for p in packages for target in p.get('targets', [])), \
    'The Rust project has no binary target'
assert any(dep.get('name') == 'plotters' for p in packages for dep in p.get('dependencies', [])), \
    'The project does not declare the required plotters dependency'
PY

    # Outputs must be produced by the submitted Rust executable, not left behind
    # as precomputed files.
    rm -f "$project/final_u.txt" "$project/trajectory.png"
    timeout 600 cargo build
    timeout 300 cargo run --quiet

    test -f "$project/final_u.txt"
    test -f "$project/trajectory.png"

    cat > /tmp/test_final_state.py <<'PY'
import collections
import math
import os
import re
import struct
import zlib


def transpose(mat):
    return [list(row) for row in zip(*mat)]


def mat_mul(A, B):
    return [[sum(a * b for a, b in zip(A_row, B_col)) for B_col in zip(*B)] for A_row in A]


def add_mat(A, B):
    return [[A[i][j] + B[i][j] for j in range(len(A[0]))] for i in range(len(A))]


def invert_3x3(m):
    det = (m[0][0] * (m[1][1] * m[2][2] - m[2][1] * m[1][2]) -
           m[0][1] * (m[1][0] * m[2][2] - m[1][2] * m[2][0]) +
           m[0][2] * (m[1][0] * m[2][1] - m[1][1] * m[2][0]))
    return [
        [(m[1][1] * m[2][2] - m[2][1] * m[1][2]) / det,
         (m[0][2] * m[2][1] - m[0][1] * m[2][2]) / det,
         (m[0][1] * m[1][2] - m[0][2] * m[1][1]) / det],
        [(m[1][2] * m[2][0] - m[1][0] * m[2][2]) / det,
         (m[0][0] * m[2][2] - m[0][2] * m[2][0]) / det,
         (m[1][0] * m[0][2] - m[0][0] * m[1][2]) / det],
        [(m[1][0] * m[2][1] - m[2][0] * m[1][1]) / det,
         (m[2][0] * m[0][1] - m[0][0] * m[2][1]) / det,
         (m[0][0] * m[1][1] - m[1][0] * m[0][1]) / det]
    ]


def get_expected_u():
    X = [
        [1.0, 2.0, 2.001],
        [1.0, 3.0, 3.002],
        [1.0, 4.0, 4.001],
        [1.0, 5.0, 5.003],
        [1.0, 6.0, 6.002]
    ]
    y = [[4.1], [6.2], [8.0], [10.1], [11.9]]
    X_T = transpose(X)
    X_T_X = mat_mul(X_T, X)
    lam = 0.05
    A = add_mat(X_T_X, [[lam, 0.0, 0.0], [0.0, lam, 0.0], [0.0, 0.0, lam]])
    theta_mat = mat_mul(invert_3x3(A), mat_mul(X_T, y))
    theta = [theta_mat[0][0], theta_mat[1][0], theta_mat[2][0]]

    u = 1.0
    t = 0.0
    dt = 0.001
    for _ in range(int(10.0 / dt)):
        du = theta[0] * u + theta[1] * math.sin(t) + theta[2] * math.cos(t)
        u += du * dt
        t += dt
    return u


def paeth(a, b, c):
    p = a + b - c
    pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
    if pa <= pb and pa <= pc:
        return a
    if pb <= pc:
        return b
    return c


def decode_png(path):
    with open(path, 'rb') as f:
        data = f.read()

    assert data[:8] == b'\x89PNG\r\n\x1a\n', f'File {path} is not a valid PNG file.'
    pos = 8
    ihdr = None
    palette = None
    idat = bytearray()
    saw_iend = False

    while pos < len(data):
        assert pos + 12 <= len(data), 'Truncated PNG chunk'
        length = struct.unpack('>I', data[pos:pos + 4])[0]
        kind = data[pos + 4:pos + 8]
        end = pos + 12 + length
        assert end <= len(data), 'Truncated PNG chunk data'
        payload = data[pos + 8:pos + 8 + length]
        expected_crc = struct.unpack('>I', data[pos + 8 + length:end])[0]
        assert (zlib.crc32(kind + payload) & 0xffffffff) == expected_crc, 'Invalid PNG chunk CRC'

        if kind == b'IHDR':
            assert ihdr is None and length == 13, 'Invalid PNG IHDR'
            ihdr = struct.unpack('>IIBBBBB', payload)
        elif kind == b'PLTE':
            assert length % 3 == 0, 'Invalid PNG palette'
            palette = [tuple(payload[i:i + 3]) for i in range(0, length, 3)]
        elif kind == b'IDAT':
            idat.extend(payload)
        elif kind == b'IEND':
            assert length == 0, 'Invalid PNG IEND'
            saw_iend = True
            pos = end
            break
        pos = end

    assert ihdr is not None and idat and saw_iend and pos == len(data), 'Incomplete PNG structure'
    width, height, depth, color_type, compression, filtering, interlace = ihdr
    assert (width, height) == (800, 600), f'PNG dimensions are {width}x{height}, expected 800x600'
    assert depth == 8, 'PNG must use 8-bit samples'
    assert compression == 0 and filtering == 0 and interlace == 0, 'Unsupported PNG encoding'

    channels = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}.get(color_type)
    assert channels is not None, f'Unsupported PNG color type {color_type}'
    raw = zlib.decompress(bytes(idat))
    stride = width * channels
    assert len(raw) == height * (stride + 1), 'PNG decompressed data has the wrong size'

    rows = []
    previous = bytearray(stride)
    offset = 0
    for _ in range(height):
        filter_type = raw[offset]
        source = raw[offset + 1:offset + 1 + stride]
        offset += stride + 1
        assert filter_type <= 4, 'Invalid PNG scanline filter'
        row = bytearray(stride)
        for i, value in enumerate(source):
            left = row[i - channels] if i >= channels else 0
            above = previous[i]
            upper_left = previous[i - channels] if i >= channels else 0
            if filter_type == 0:
                prediction = 0
            elif filter_type == 1:
                prediction = left
            elif filter_type == 2:
                prediction = above
            elif filter_type == 3:
                prediction = (left + above) // 2
            else:
                prediction = paeth(left, above, upper_left)
            row[i] = (value + prediction) & 255
        rows.append(row)
        previous = row

    def rgb_at(x, y):
        row = rows[y]
        i = x * channels
        if color_type == 0:
            return (row[i], row[i], row[i])
        if color_type == 2:
            return tuple(row[i:i + 3])
        if color_type == 3:
            assert palette is not None and row[i] < len(palette), 'Invalid palette index'
            return palette[row[i]]
        if color_type == 4:
            return (row[i], row[i], row[i])
        return tuple(row[i:i + 3])

    return width, height, rgb_at


def test_final_u_txt_value():
    txt_path = '/home/user/ode_fitter/final_u.txt'
    assert os.path.exists(txt_path), f'File {txt_path} does not exist.'
    assert os.path.isfile(txt_path), f'Path {txt_path} is not a file.'
    content_bytes = open(txt_path, 'rb').read()
    assert re.fullmatch(rb'[+-]?\d+\.\d{4}\n?', content_bytes), \
        'final_u.txt must contain only one finite floating-point number formatted to 4 decimal places'
    actual_u = float(content_bytes.decode('ascii').strip())
    expected_u = get_expected_u()
    assert abs(actual_u - expected_u) <= 0.01, \
        f'Value in {txt_path} ({actual_u}) deviates from expected ({expected_u:.4f}) by more than 0.01.'


def test_trajectory_png_exists_and_contains_plot():
    png_path = '/home/user/ode_fitter/trajectory.png'
    assert os.path.exists(png_path), f'File {png_path} does not exist.'
    assert os.path.isfile(png_path), f'Path {png_path} is not a file.'
    width, height, rgb_at = decode_png(png_path)

    # Determine the canvas color, then look inside the plotting region for a
    # long, vertically varying run of ink after removing full grid/axis lines.
    sampled = [rgb_at(x, y) for y in range(0, height, 4) for x in range(0, width, 4)]
    background = collections.Counter(sampled).most_common(1)[0][0]
    x0, x1 = width // 10, width * 9 // 10
    y0, y1 = height // 10, height * 9 // 10

    ink = set()
    for y in range(y0, y1):
        for x in range(x0, x1):
            pixel = rgb_at(x, y)
            if sum((pixel[c] - background[c]) ** 2 for c in range(3)) > 20 ** 2:
                ink.add((x, y))

    assert len(ink) >= 500, 'PNG does not contain enough rendered plot content'
    row_counts = collections.Counter(y for x, y in ink)
    col_counts = collections.Counter(x for x, y in ink)
    dense_rows = {y for y, n in row_counts.items() if n > (x1 - x0) * 0.55}
    dense_cols = {x for x, n in col_counts.items() if n > (y1 - y0) * 0.55}
    curve_ink = [(x, y) for x, y in ink if y not in dense_rows and x not in dense_cols]
    assert len(curve_ink) >= 300, 'PNG contains axes/grid but no substantial trajectory line'
    xs = {x for x, y in curve_ink}
    ys = [y for x, y in curve_ink]
    assert len(xs) >= int((x1 - x0) * 0.45), 'Trajectory does not span the time axis'
    assert max(ys) - min(ys) >= int((y1 - y0) * 0.15), 'Trajectory has no meaningful vertical variation'
PY

    python3 -m pytest /tmp/test_final_state.py -x --tb=short
); then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
