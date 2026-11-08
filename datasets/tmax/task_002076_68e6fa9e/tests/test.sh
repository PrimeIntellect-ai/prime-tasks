#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import ast
import csv
import math
import os
import re
import secrets
import struct
import subprocess
import zlib

import numpy as np
from scipy.stats import gamma

DATA = "/home/user/data/observations.txt"
WORK = "/home/user/workspace"
FIT = os.path.join(WORK, "fit_model.py")
VALIDATE = os.path.join(WORK, "validate.R")
PARAMS = os.path.join(WORK, "params.csv")
KS = os.path.join(WORK, "ks_stat.txt")
PLOT = os.path.join(WORK, "cdf_plot.png")


def run_as_user(command):
    subprocess.run(
        ["runuser", "-u", "user", "--"] + command,
        cwd=WORK,
        check=True,
        timeout=90,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )


def remove_outputs():
    for path in (PARAMS, KS, PLOT):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass


def run_pipeline():
    remove_outputs()
    run_as_user(["python3", FIT])
    assert os.path.isfile(PARAMS), "fit_model.py did not create params.csv"
    run_as_user(["Rscript", VALIDATE])


def read_params():
    assert os.path.isfile(PARAMS), f"File {PARAMS} is missing."
    with open(PARAMS, newline="") as f:
        rows = list(csv.reader(f))
    assert len(rows) >= 2, f"{PARAMS} does not have enough rows."
    header = [h.strip() for h in rows[0]]
    assert header == ["shape", "scale"], (
        f"Header in {PARAMS} is incorrect. Expected ['shape', 'scale'], got {header}."
    )
    assert len(rows[1]) >= 2, "The parameter row must contain shape and scale."
    shape = float(rows[1][0])
    scale = float(rows[1][1])
    assert math.isfinite(shape) and shape > 0
    assert math.isfinite(scale) and scale > 0
    return shape, scale


def expected_ks(data, shape, scale):
    values = np.sort(np.asarray(data, dtype=float))
    cdf = gamma.cdf(values, shape, loc=0, scale=scale)
    n = len(values)
    d_plus = np.max(np.arange(1, n + 1) / n - cdf)
    d_minus = np.max(cdf - np.arange(0, n) / n)
    return float(max(d_plus, d_minus))


def check_ks(expected=None):
    assert os.path.isfile(KS), f"File {KS} is missing."
    with open(KS) as f:
        content = f.read()
    assert re.fullmatch(r"[0-9]+\.[0-9]{4}\n?", content), (
        "ks_stat.txt must contain only a statistic rounded to exactly four decimal places."
    )
    value = float(content.strip())
    if expected is not None:
        assert content.strip() == f"{expected:.4f}", (
            f"KS statistic {content.strip()} does not match the recomputed value {expected:.4f}."
        )
    return value


def check_png():
    assert os.path.isfile(PLOT), f"Plot file {PLOT} is missing."
    raw = open(PLOT, "rb").read()
    assert raw[:8] == b"\x89PNG\r\n\x1a\n", f"File {PLOT} is not a valid PNG file."

    pos = 8
    ihdr = None
    compressed = bytearray()
    while pos + 12 <= len(raw):
        length = struct.unpack(">I", raw[pos:pos + 4])[0]
        kind = raw[pos + 4:pos + 8]
        payload = raw[pos + 8:pos + 8 + length]
        assert len(payload) == length, "Truncated PNG chunk."
        if kind == b"IHDR":
            ihdr = payload
        elif kind == b"IDAT":
            compressed.extend(payload)
        elif kind == b"IEND":
            break
        pos += 12 + length

    assert ihdr is not None and len(ihdr) == 13, "PNG has no valid IHDR."
    width, height, depth, color_type, _, _, interlace = struct.unpack(">IIBBBBB", ihdr)
    assert (width, height) == (800, 600), (
        f"cdf_plot.png is {width}x{height}; expected 800x600 pixels."
    )
    assert depth == 8 and interlace == 0, "Unexpected PNG encoding."
    channels = {0: 1, 2: 3, 4: 2, 6: 4}.get(color_type)
    assert channels is not None and compressed, "PNG has no supported pixel data."

    decoded = zlib.decompress(bytes(compressed))
    stride = width * channels
    assert len(decoded) == height * (stride + 1), "PNG pixel data has an invalid size."
    previous = bytearray(stride)
    colors = set()
    offset = 0
    for _ in range(height):
        filter_type = decoded[offset]
        scan = bytearray(decoded[offset + 1:offset + 1 + stride])
        offset += stride + 1
        assert filter_type in range(5), "Invalid PNG filter."
        for i in range(stride):
            left = scan[i - channels] if i >= channels else 0
            up = previous[i]
            upper_left = previous[i - channels] if i >= channels else 0
            if filter_type == 1:
                scan[i] = (scan[i] + left) & 255
            elif filter_type == 2:
                scan[i] = (scan[i] + up) & 255
            elif filter_type == 3:
                scan[i] = (scan[i] + ((left + up) // 2)) & 255
            elif filter_type == 4:
                p = left + up - upper_left
                pa, pb, pc = abs(p - left), abs(p - up), abs(p - upper_left)
                predictor = left if pa <= pb and pa <= pc else (up if pb <= pc else upper_left)
                scan[i] = (scan[i] + predictor) & 255
        for i in range(0, stride, channels * 200):
            colors.add(bytes(scan[i:i + channels]))
        previous = scan
    assert len(colors) > 1, "The PNG contains no visible plotted content."


def check_python_source():
    assert os.path.isfile(FIT), f"Python script {FIT} is missing."
    source = open(FIT).read()
    tree = ast.parse(source, filename=FIT)
    imported_scipy = False
    has_gamma = False
    has_fit_attribute = False
    has_floc_zero_call = False
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            imported_scipy |= any(alias.name == "scipy" or alias.name.startswith("scipy.") for alias in node.names)
            has_gamma |= any(alias.name.endswith(".gamma") for alias in node.names)
        elif isinstance(node, ast.ImportFrom):
            imported_scipy |= bool(node.module and (node.module == "scipy" or node.module.startswith("scipy.")))
            has_gamma |= any(alias.name == "gamma" for alias in node.names)
        elif isinstance(node, ast.Attribute):
            has_fit_attribute |= node.attr == "fit"
            has_gamma |= node.attr == "gamma"
        elif isinstance(node, ast.Call):
            for keyword in node.keywords:
                if keyword.arg == "floc" and isinstance(keyword.value, ast.Constant) and keyword.value.value == 0:
                    has_floc_zero_call = True
    assert imported_scipy and has_gamma and has_fit_attribute and has_floc_zero_call, (
        "fit_model.py must use scipy.stats.gamma.fit with floc=0."
    )


def check_r_source():
    assert os.path.isfile(VALIDATE), f"R script {VALIDATE} is missing."
    helper = r'''
walk <- function(x) {
  if (is.call(x)) {
    h <- x[[1]]
    if (is.symbol(h)) cat(as.character(h), "\n", sep="")
    else if (is.call(h) && as.character(h[[1]]) %in% c("::", ":::")) cat(as.character(h[[3]]), "\n", sep="")
    args <- as.list(x)[-1]
    if (length(args)) invisible(lapply(args, walk))
  } else if (is.expression(x) || is.pairlist(x)) {
    if (length(x)) invisible(lapply(as.list(x), walk))
  } else if (is.character(x)) {
    cat(x, "\n", sep="")
  }
}
walk(parse(file=commandArgs(TRUE)[1]))
'''
    result = subprocess.run(
        ["Rscript", "-e", helper, VALIDATE],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    tokens = set(result.stdout.splitlines())
    for required in ("ks.test", "pgamma", "ecdf"):
        assert required in tokens, f"validate.R must use R's {required}."


def validate_outputs(data, expected_shape, expected_scale, preserve_original_checks=False):
    shape, scale = read_params()
    if preserve_original_checks:
        assert math.isclose(shape, 2.5186, rel_tol=0.05), f"Shape parameter {shape} is out of expected range."
        assert math.isclose(scale, 1.4552, rel_tol=0.05), f"Scale parameter {scale} is out of expected range."
    assert math.isclose(shape, expected_shape, rel_tol=1e-4, abs_tol=1e-6), (
        f"Shape {shape} does not match scipy.stats.gamma.fit result {expected_shape}."
    )
    assert math.isclose(scale, expected_scale, rel_tol=1e-4, abs_tol=1e-6), (
        f"Scale {scale} does not match scipy.stats.gamma.fit result {expected_scale}."
    )
    ks_expected = expected_ks(data, expected_shape, expected_scale)
    ks_value = check_ks(ks_expected)
    if preserve_original_checks:
        assert math.isclose(ks_value, 0.0163, abs_tol=0.005), (
            f"KS statistic {ks_value} is out of expected range."
        )
    check_png()


def test_complete_executed_pipeline():
    check_python_source()
    check_r_source()
    original_bytes = open(DATA, "rb").read()
    original_data = np.loadtxt(DATA)
    original_fit = gamma.fit(original_data, floc=0)

    try:
        # Execute both requested scripts on the supplied observations and retain
        # all of the original verifier's substantive checks.
        run_pipeline()
        validate_outputs(original_data, original_fit[0], original_fit[2], True)

        # Exercise the scripts on an independently generated dataset so fixed
        # parameters, a fixed KS value, or prebuilt output files cannot pass.
        rng = np.random.default_rng(secrets.randbits(64))
        challenge = rng.gamma(rng.uniform(0.8, 1.3), rng.uniform(2.8, 4.0), 257)
        with open(DATA, "w") as f:
            for value in challenge:
                f.write(f"{value:.17g}\n")
        challenge_fit = gamma.fit(challenge, floc=0)
        run_pipeline()
        validate_outputs(challenge, challenge_fit[0], challenge_fit[2])
    finally:
        with open(DATA, "wb") as f:
            f.write(original_bytes)
        # Leave the requested final artifacts regenerated from the real data.
        run_pipeline()

    validate_outputs(original_data, original_fit[0], original_fit[2], True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
