#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import math
import os
import random
import subprocess
import tempfile
import uuid
import pytest

APP_DIR = "/home/user/telemetry_filter"


def run_filter(path):
    return subprocess.run(
        ["cargo", "run", "--release", "--", path],
        cwd=APP_DIR,
        capture_output=True,
        text=True,
        timeout=30,
    )


def frame_count():
    res = subprocess.run(
        [
            "ffprobe", "-v", "error", "-count_frames",
            "-select_streams", "v:0",
            "-show_entries", "stream=nb_read_frames",
            "-of", "default=nokey=1:noprint_wrappers=1",
            "/app/sync_feed.mp4",
        ],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert res.returncode == 0, f"Could not inspect reference video: {res.stderr}"
    value = res.stdout.strip()
    assert value.isdigit() and int(value) > 0, f"Invalid frame count from ffprobe: {value!r}"
    return int(value)


def pearson(xs, ys):
    if len(xs) != len(ys) or not xs:
        return float("nan")
    if not all(math.isfinite(x) for x in xs + ys):
        return float("nan")
    mx = sum(xs) / len(xs)
    my = sum(ys) / len(ys)
    dx = [x - mx for x in xs]
    dy = [y - my for y in ys]
    denom = math.sqrt(sum(x*x for x in dx) * sum(y*y for y in dy))
    if denom == 0:
        return float("nan")
    return sum(x*y for x, y in zip(dx, dy)) / denom


def write_csv(path, xs, ys):
    with open(path, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["timestamp", "sensor_alpha", "sensor_beta"])
        for i, (x, y) in enumerate(zip(xs, ys)):
            writer.writerow([i, format(x, ".17g"), format(y, ".17g")])


def expected_for(xs, ys, frames):
    r = pearson(xs, ys)
    return "VALID" if len(xs) == frames and math.isfinite(r) and r >= 0.85 else "INVALID"


def test_telemetry_filter():
    app_dir = APP_DIR
    assert os.path.isdir(app_dir), f"Directory {app_dir} does not exist. Did you create the cargo project?"
    assert os.path.isfile(os.path.join(app_dir, "Cargo.toml")), "Cargo.toml does not exist in the requested project."

    clean_dir = "/app/corpora/clean"
    evil_dir = "/app/corpora/evil"

    clean_files = sorted([os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if f.endswith('.csv')])
    evil_files = sorted([os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if f.endswith('.csv')])

    assert len(clean_files) > 0, "No clean files found in corpus."
    assert len(evil_files) > 0, "No evil files found in corpus."

    # Preserve the original build and corpus checks.
    build_res = subprocess.run(["cargo", "build", "--release"], cwd=app_dir, capture_output=True, text=True)
    assert build_res.returncode == 0, f"Cargo build failed:\n{build_res.stderr}"

    failed_clean = []
    for fp in clean_files:
        res = run_filter(fp)
        out = res.stdout.strip().splitlines()[-1] if res.stdout.strip() else ""
        if out != "VALID":
            failed_clean.append(os.path.basename(fp))

    failed_evil = []
    for fp in evil_files:
        res = run_filter(fp)
        out = res.stdout.strip().splitlines()[-1] if res.stdout.strip() else ""
        if out != "INVALID":
            failed_evil.append(os.path.basename(fp))

    errors = []
    if failed_clean:
        errors.append(f"{len(failed_clean)} of {len(clean_files)} clean modified/rejected: {', '.join(failed_clean)}")
    if failed_evil:
        errors.append(f"{len(failed_evil)} of {len(evil_files)} evil bypassed: {', '.join(failed_evil)}")
    if errors:
        pytest.fail(" | ".join(errors))

    # Exercise newly generated, neutrally located inputs. Expected answers are
    # derived from the actual video frame count and Pearson definition.
    frames = frame_count()
    rng = random.Random(os.urandom(32))
    base_x = [rng.uniform(-100.0, 100.0) for _ in range(frames)]
    strong_y = [2.75*x + rng.uniform(-2.0, 2.0) for x in base_x]
    independent_y = [rng.uniform(-100.0, 100.0) for _ in range(frames)]
    negative_y = [-x for x in base_x]
    constant_y = [4.0 for _ in range(frames)]

    cases = [
        (base_x, strong_y),
        (base_x, independent_y),
        (base_x, negative_y),
        (base_x, constant_y),
        (base_x[:-1], strong_y[:-1]),
        (base_x + [rng.random()], strong_y + [rng.random()]),
    ]
    rng.shuffle(cases)

    with tempfile.TemporaryDirectory(prefix="telemetry_checks_") as tmp:
        for xs, ys in cases:
            path = os.path.join(tmp, f"{uuid.uuid4().hex}.csv")
            write_csv(path, xs, ys)
            expected = expected_for(xs, ys, frames)
            res = run_filter(path)
            assert res.returncode == 0, f"Program failed for generated input: {res.stderr}"
            assert res.stdout in (expected, expected + "\n"), (
                f"Generated input expected {expected}, got stdout {res.stdout!r}. "
                "Output must contain only VALID or INVALID."
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
