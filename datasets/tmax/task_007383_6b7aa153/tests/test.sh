#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import math
import os
import random
import re
import struct
import subprocess
import zlib

import numpy as np

SCRIPT = "/home/user/heat_sim.py"
INPUT = "/home/user/input.pdb"
PNG = "/home/user/z_profile.png"
TXT = "/home/user/max_temp.txt"

ORIGINAL_COORDS = [
    (-1.424, -2.193, 0.218),
    (0.039, -2.221, 0.245),
    (0.556, -0.814, 0.509),
    (1.455, -0.612, 1.328),
    (0.592, -3.155, 1.306),
    (-0.038, 0.147, -0.198),
    (0.360, 1.543, 0.007),
    (0.267, 2.368, -1.272),
    (-0.569, 2.115, -2.138),
    (-0.457, 2.164, 1.143),
    (0.063, 3.856, 1.503),
]

ORIGINAL_PDB = """ATOM      1  N   ALA A   1      -1.424  -2.193   0.218  1.00 13.90           N  
ATOM      2  CA  ALA A   1       0.039  -2.221   0.245  1.00 13.11           C  
ATOM      3  C   ALA A   1       0.556  -0.814   0.509  1.00 13.56           C  
ATOM      4  O   ALA A   1       1.455  -0.612   1.328  1.00 14.12           O  
ATOM      5  CB  ALA A   1       0.592  -3.155   1.306  1.00 13.50           C  
ATOM      6  N   CYS A   2      -0.038   0.147  -0.198  1.00 12.39           N  
ATOM      7  CA  CYS A   2       0.360   1.543   0.007  1.00 12.63           C  
ATOM      8  C   CYS A   2       0.267   2.368  -1.272  1.00 11.87           C  
ATOM      9  O   CYS A   2      -0.569   2.115  -2.138  1.00 12.60           O  
ATOM     10  CB  CYS A   2      -0.457   2.164   1.143  1.00 12.98           C  
ATOM     11  SG  CYS A   2       0.063   3.856   1.503  1.00 14.71           S  
"""


def compute_expected(coords):
    N = 20
    dx = 1.0
    T = np.zeros((N, N, N), dtype=float)
    for x, y, z in coords:
        ix = max(0, min(N - 1, int(math.floor(x + 10.0))))
        iy = max(0, min(N - 1, int(math.floor(y + 10.0))))
        iz = max(0, min(N - 1, int(math.floor(z + 10.0))))
        T[ix, iy, iz] = 100.0

    alpha = 0.1
    dt = dx ** 2 / (6.0 * alpha)
    for _ in range(500):
        T_new = T.copy()
        laplacian = (
            T[2:, 1:-1, 1:-1] + T[:-2, 1:-1, 1:-1]
            + T[1:-1, 2:, 1:-1] + T[1:-1, :-2, 1:-1]
            + T[1:-1, 1:-1, 2:] + T[1:-1, 1:-1, :-2]
            - 6.0 * T[1:-1, 1:-1, 1:-1]
        ) / (dx ** 2)
        T_new[1:-1, 1:-1, 1:-1] = (
            T[1:-1, 1:-1, 1:-1] + alpha * dt * laplacian
        )
        T = T_new
    return float(np.max(T))


def compute_expected_max_temp():
    return compute_expected(ORIGINAL_COORDS)


def make_pdb(coords):
    lines = []
    for i, (x, y, z) in enumerate(coords, 1):
        lines.append(
            f"ATOM  {i:5d}  C   GLY A{i:4d}    "
            f"{x:8.3f}{y:8.3f}{z:8.3f}  1.00 10.00           C  \n"
        )
    return "".join(lines)


def run_script():
    env = os.environ.copy()
    env["MPLBACKEND"] = "Agg"
    result = subprocess.run(
        ["python3", SCRIPT], cwd="/home/user", env=env,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, timeout=180,
    )
    assert result.returncode == 0, (
        f"heat_sim.py failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def read_temperature():
    assert os.path.isfile(TXT), f"Missing file: {TXT}"
    with open(TXT, "r") as f:
        content = f.read().strip()
    assert re.fullmatch(r"[-+]?\d+\.\d{4}", content), (
        f"{TXT} must contain only a floating point number rounded to 4 decimal places; found: {content!r}"
    )
    value = float(content)
    assert math.isfinite(value), "The maximum temperature is NaN or infinite."
    return value


def validate_png():
    assert os.path.isfile(PNG), f"Missing file: {PNG}"
    assert os.path.getsize(PNG) > 1000, f"{PNG} is empty or too small to be a generated plot."
    with open(PNG, "rb") as f:
        data = f.read()
    assert data.startswith(b"\x89PNG\r\n\x1a\n"), f"{PNG} is not a PNG file."

    pos = 8
    saw_ihdr = saw_idat = saw_iend = False
    while pos + 12 <= len(data):
        length = struct.unpack(">I", data[pos:pos + 4])[0]
        kind = data[pos + 4:pos + 8]
        end = pos + 12 + length
        assert end <= len(data), f"{PNG} contains a truncated PNG chunk."
        payload = data[pos + 8:pos + 8 + length]
        stored_crc = struct.unpack(">I", data[pos + 8 + length:end])[0]
        assert zlib.crc32(kind + payload) & 0xffffffff == stored_crc, f"{PNG} has an invalid PNG checksum."
        if kind == b"IHDR":
            saw_ihdr = True
            width, height = struct.unpack(">II", payload[:8])
            assert width > 0 and height > 0, f"{PNG} has invalid dimensions."
        elif kind == b"IDAT":
            saw_idat = saw_idat or bool(payload)
        elif kind == b"IEND":
            saw_iend = True
            break
        pos = end
    assert saw_ihdr and saw_idat and saw_iend, f"{PNG} is not a complete PNG image."
    return hashlib.sha256(data).digest()


def test_00_script_is_executed_on_unseen_input():
    assert os.path.isfile(SCRIPT), f"Missing script: {SCRIPT}"
    assert os.path.getsize(SCRIPT) > 0, f"Script is empty: {SCRIPT}"

    rng = random.SystemRandom()
    cells = {(3, 3, 3)}
    while len(cells) < 9:
        cells.add((rng.randrange(2, 18), rng.randrange(2, 18), rng.randrange(2, 18)))
    challenge_coords = []
    for ix, iy, iz in cells:
        challenge_coords.append((
            ix - 10.0 + rng.uniform(0.15, 0.85),
            iy - 10.0 + rng.uniform(0.15, 0.85),
            iz - 10.0 + rng.uniform(0.15, 0.85),
        ))
    # Coordinates are written to three decimals, so derive the oracle from those exact values.
    challenge_coords = [tuple(float(f"{v:.3f}") for v in c) for c in challenge_coords]

    try:
        with open(INPUT, "w") as f:
            f.write(make_pdb(challenge_coords))
        for path in (PNG, TXT):
            if os.path.exists(path):
                os.remove(path)
        run_script()
        challenge_actual = read_temperature()
        challenge_expected = round(compute_expected(challenge_coords), 4)
        assert math.isclose(challenge_actual, challenge_expected, rel_tol=1e-3, abs_tol=1e-3), (
            f"On an unseen PDB, expected {challenge_expected:.4f} but got {challenge_actual:.4f}."
        )
        challenge_png_hash = validate_png()
    finally:
        with open(INPUT, "w") as f:
            f.write(ORIGINAL_PDB)

    for path in (PNG, TXT):
        if os.path.exists(path):
            os.remove(path)
    run_script()
    original_png_hash = validate_png()
    assert original_png_hash != challenge_png_hash, "The plot did not change when the molecular input changed."


def test_files_generated():
    assert os.path.exists("/home/user/z_profile.png"), "/home/user/z_profile.png was not generated."
    assert os.path.exists("/home/user/max_temp.txt"), "/home/user/max_temp.txt was not generated."
    validate_png()


def test_max_temp_correct():
    txt_path = "/home/user/max_temp.txt"
    assert os.path.exists(txt_path), f"Missing file: {txt_path}"

    with open(txt_path, "r") as f:
        content = f.read().strip()

    try:
        actual_temp = float(content)
    except ValueError:
        assert False, f"Could not parse the content of {txt_path} as a float. Found: {content}"

    expected_temp = compute_expected_max_temp()

    assert not math.isnan(actual_temp), "The maximum temperature is NaN, indicating numerical instability."
    assert not math.isinf(actual_temp), "The maximum temperature is infinite, indicating numerical instability."

    expected_rounded = round(expected_temp, 4)
    actual_rounded = round(actual_temp, 4)

    assert math.isclose(actual_rounded, expected_rounded, rel_tol=1e-3, abs_tol=1e-3), \
        f"Expected max temperature to be approximately {expected_rounded}, but got {actual_rounded}. Ensure dt is calculated correctly."
    assert re.fullmatch(r"[-+]?\d+\.\d{4}", content), \
        f"Expected exactly 4 digits after the decimal point, but found: {content!r}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
