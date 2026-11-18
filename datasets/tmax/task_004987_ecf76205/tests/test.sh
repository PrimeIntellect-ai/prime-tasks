#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/verify_task.py
import json
import math
import os
import re
import struct
import subprocess
import sys
import zlib

import numpy as np
import pandas as pd

PROJECT_DIR = "/home/user/rust-etl"
MAIN_RS = os.path.join(PROJECT_DIR, "src/main.rs")
DATA_FILE = os.path.join(PROJECT_DIR, "data.csv")
METRICS_FILE = os.path.join(PROJECT_DIR, "metrics.json")
PLOT_FILE = os.path.join(PROJECT_DIR, "plot.png")


def canonical_frame():
    rng = np.random.RandomState(42)
    x_corr = rng.randn(200, 3)
    y = (x_corr[:, 0] * 3.0 + x_corr[:, 1] * 2.0 +
         x_corr[:, 2] * 1.0 + rng.randn(200) * 0.5)
    x_noise = rng.randn(200, 7)
    x = np.hstack([x_corr, x_noise])
    frame = pd.DataFrame(x, columns=[f"f{i}" for i in range(10)])
    frame["target"] = y
    return frame


def expected_mse(frame, components):
    x = frame[[f"f{i}" for i in range(10)]].to_numpy(dtype=float)
    y = frame["target"].to_numpy(dtype=float)
    centered = x - x.mean(axis=0)
    _, _, vt = np.linalg.svd(centered, full_matrices=False)
    transformed = centered @ vt[:components].T
    design = np.column_stack([np.ones(len(y)), transformed])
    coefficients = np.linalg.lstsq(design, y, rcond=None)[0]
    predictions = design @ coefficients
    return float(np.mean((y - predictions) ** 2))


def run(command, timeout=300):
    result = subprocess.run(
        command,
        cwd=PROJECT_DIR,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=timeout,
    )
    assert result.returncode == 0, (
        f"Command failed: {' '.join(command)}\n"
        f"STDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
    )
    return result


def remove_outputs():
    for path in (METRICS_FILE, PLOT_FILE):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass


def read_metrics(expected):
    assert os.path.exists(METRICS_FILE), f"{METRICS_FILE} not found. Did you output the metrics?"
    with open(METRICS_FILE, "r", encoding="utf-8") as handle:
        try:
            data = json.load(handle)
        except json.JSONDecodeError as exc:
            raise AssertionError(f"{METRICS_FILE} is not valid JSON: {exc}")
    assert isinstance(data, dict) and set(data) == {"mse"}, "metrics.json must contain exactly the key 'mse'."
    value = data["mse"]
    assert isinstance(value, (int, float)) and not isinstance(value, bool), "The value of 'mse' must be a number."
    value = float(value)
    assert math.isfinite(value), "The value of 'mse' must be finite."
    assert abs(value - expected) <= max(1e-3, abs(expected) * 1e-5), (
        f"metrics.json reports MSE {value}, but the independently calculated MSE is {expected}."
    )
    return value


def validate_png():
    assert os.path.exists(PLOT_FILE), f"{PLOT_FILE} not found. Did you generate the plot?"
    size = os.path.getsize(PLOT_FILE)
    assert size > 1000, f"{PLOT_FILE} is too small ({size} bytes). The plotting backend may not have been finalized."
    with open(PLOT_FILE, "rb") as handle:
        raw = handle.read()
    assert raw[:8] == b"\x89PNG\r\n\x1a\n", f"{PLOT_FILE} does not have a valid PNG header."

    offset = 8
    chunks = []
    idat = bytearray()
    saw_iend = False
    while offset < len(raw):
        assert offset + 12 <= len(raw), "Truncated PNG chunk."
        length = struct.unpack(">I", raw[offset:offset + 4])[0]
        kind = raw[offset + 4:offset + 8]
        end = offset + 12 + length
        assert end <= len(raw), "Truncated PNG chunk data."
        payload = raw[offset + 8:offset + 8 + length]
        stored_crc = struct.unpack(">I", raw[offset + 8 + length:end])[0]
        actual_crc = zlib.crc32(kind)
        actual_crc = zlib.crc32(payload, actual_crc) & 0xffffffff
        assert stored_crc == actual_crc, f"Invalid CRC in PNG chunk {kind!r}."
        chunks.append((kind, payload))
        if kind == b"IDAT":
            idat.extend(payload)
        if kind == b"IEND":
            saw_iend = True
            assert length == 0, "Invalid PNG IEND chunk."
            assert end == len(raw), "Unexpected data after PNG IEND chunk."
            break
        offset = end

    assert chunks and chunks[0][0] == b"IHDR", "PNG is missing its initial IHDR chunk."
    assert saw_iend, "PNG is missing IEND; the backend was not finalized."
    assert idat, "PNG contains no image data."
    ihdr = chunks[0][1]
    assert len(ihdr) == 13, "Invalid PNG IHDR."
    width, height = struct.unpack(">II", ihdr[:8])
    assert width > 0 and height > 0, "PNG dimensions are invalid."
    try:
        pixels = zlib.decompress(bytes(idat))
    except zlib.error as exc:
        raise AssertionError(f"PNG image data is corrupt: {exc}")
    assert len(pixels) > height, "PNG decompressed image data is incomplete."


def write_frame(frame):
    frame.to_csv(DATA_FILE, index=False)


def execute_and_check(frame, expected, require_low=False):
    write_frame(frame)
    remove_outputs()
    run(["cargo", "run", "--quiet"])
    value = read_metrics(expected)
    if require_low:
        assert value < 2.0, f"MSE is {value}, but it must be strictly less than 2.0."
    validate_png()


assert os.path.isdir(PROJECT_DIR), f"{PROJECT_DIR} does not exist."
assert os.path.isfile(MAIN_RS), f"{MAIN_RS} not found."
assert os.path.isfile(DATA_FILE), f"{DATA_FILE} not found."

canonical = canonical_frame()
provided = pd.read_csv(DATA_FILE)
assert list(provided.columns) == list(canonical.columns) and provided.shape == canonical.shape, "data.csv structure was changed."
assert np.allclose(provided.to_numpy(dtype=float), canonical.to_numpy(dtype=float), rtol=0, atol=1e-12), "The provided data.csv was modified."

mses = [expected_mse(canonical, k) for k in range(1, 11)]
qualifying = [k for k, mse in enumerate(mses, start=1) if mse < 2.0]
assert qualifying, "Internal verifier error: no PCA component count reaches the required MSE."
minimal_components = qualifying[0]
assert minimal_components >= 3

with open(MAIN_RS, "r", encoding="utf-8") as handle:
    source = handle.read()
# Ignore comments so verifier-specific dummy text cannot satisfy this assertion.
source_without_comments = re.sub(r"/\*.*?\*/", "", source, flags=re.S)
source_without_comments = re.sub(r"//[^\n]*", "", source_without_comments)
calls = re.findall(r"\bPca\s*::\s*params\s*\(\s*(\d+)\s*\)", source_without_comments)
assert len(calls) == 1, "src/main.rs must contain one actual Pca::params(<integer>) configuration call."
selected_components = int(calls[0])
assert selected_components >= 3, "The PCA component count must be at least 3."
assert selected_components == minimal_components, (
    f"Pca::params must use the minimal component count that gives MSE < 2.0: "
    f"expected {minimal_components}, found {selected_components}."
)

# Preserve the required build and editable in-project test assertions.
run(["cargo", "build"])
write_frame(canonical)
run(["cargo", "test"])

try:
    canonical_expected = mses[selected_components - 1]
    execute_and_check(canonical, canonical_expected, require_low=True)

    # Exercise the built pipeline on a second input and derive its answer independently,
    # preventing a prewritten or hard-coded metrics.json from passing.
    challenge = canonical.copy()
    x = challenge[[f"f{i}" for i in range(10)]].to_numpy(dtype=float)
    challenge["target"] = 1.5 * x[:, 0] - 2.2 * x[:, 3] + 0.8 * x[:, 7] + 0.15 * np.sin(np.arange(len(x)))
    challenge_expected = expected_mse(challenge, selected_components)
    execute_and_check(challenge, challenge_expected)
finally:
    # Leave the requested final artifacts generated from the original provided dataset.
    write_frame(canonical)
    remove_outputs()
    final_result = subprocess.run(
        ["cargo", "run", "--quiet"], cwd=PROJECT_DIR,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=300
    )
    if final_result.returncode != 0:
        print(final_result.stdout)
        print(final_result.stderr, file=sys.stderr)

assert final_result.returncode == 0, "Final cargo run on the original dataset failed."
final_mse = read_metrics(mses[selected_components - 1])
assert final_mse < 2.0, f"Final MSE is {final_mse}, but it must be strictly less than 2.0."
validate_png()
PY_EOF

if python3 /tmp/verify_task.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
