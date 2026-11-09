#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import shutil
import subprocess
from pathlib import Path

import pytest


def test_directories_exist():
    """Check if the organized directories exist."""
    assert os.path.isdir("/home/user/organized/low_error"), "Directory /home/user/organized/low_error is missing."
    assert os.path.isdir("/home/user/organized/high_error"), "Directory /home/user/organized/high_error is missing."


def test_files_moved_correctly():
    """Check if the CSV files were moved to the correct directories."""
    low_error_files = ["dataset_A.csv", "dataset_B.csv"]
    high_error_files = ["dataset_C.csv"]

    for filename in low_error_files:
        filepath = f"/home/user/organized/low_error/{filename}"
        assert os.path.isfile(filepath), f"File {filename} should be in /home/user/organized/low_error/."
        assert not os.path.exists(f"/home/user/datasets/{filename}"), f"File {filename} should have been moved from /home/user/datasets/."

    for filename in high_error_files:
        filepath = f"/home/user/organized/high_error/{filename}"
        assert os.path.isfile(filepath), f"File {filename} should be in /home/user/organized/high_error/."
        assert not os.path.exists(f"/home/user/datasets/{filename}"), f"File {filename} should have been moved from /home/user/datasets/."


def test_metrics_txt_content():
    """Check if metrics.txt contains the correct output formatted properly."""
    metrics_file = "/home/user/organized/metrics.txt"
    assert os.path.isfile(metrics_file), f"File {metrics_file} is missing."

    expected_lines = [
        "dataset_A.csv: m=2.0000, b=1.0000, MSE=0.0000",
        "dataset_B.csv: m=2.1000, b=0.6000, MSE=0.1750",
        "dataset_C.csv: m=-1.4000, b=5.1000, MSE=12.0500"
    ]

    with open(metrics_file, "r") as f:
        actual_lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(actual_lines) == len(expected_lines), "metrics.txt does not have the correct number of lines."

    for expected, actual in zip(expected_lines, actual_lines):
        assert actual == expected, f"Expected line '{expected}', but got '{actual}' in metrics.txt."


def discover_artifacts():
    roots = [Path("/home/user"), Path("/workspace"), Path("/root"), Path("/tmp")]
    skipped = {".cache", ".cargo", ".rustup", ".sdkman", ".git", "node_modules", "__pycache__"}
    sources = []
    scripts = []

    for root in roots:
        if not root.exists():
            continue
        for current, dirs, files in os.walk(root):
            dirs[:] = [d for d in dirs if d not in skipped]
            current_path = Path(current)
            for name in files:
                path = current_path / name
                if str(path).startswith("/tests/") or str(path).startswith("/logs/"):
                    continue
                if path.suffix.lower() in {".cpp", ".cc", ".cxx"}:
                    sources.append(path)
                    continue
                try:
                    prefix = path.read_bytes()[:256]
                except OSError:
                    continue
                if path.suffix.lower() == ".sh" or prefix.startswith(b"#!/bin/bash") or prefix.startswith(b"#!/bin/sh") or prefix.startswith(b"#!/usr/bin/env bash"):
                    scripts.append(path)

    return sorted(set(sources)), sorted(set(scripts))


def ols(rows):
    n = len(rows)
    sx = sum(x for x, _ in rows)
    sy = sum(y for _, y in rows)
    sxy = sum(x * y for x, y in rows)
    sx2 = sum(x * x for x, _ in rows)
    m = (n * sxy - sx * sy) / (n * sx2 - sx * sx)
    b = (sy - m * sx) / n
    mse = sum((y - (m * x + b)) ** 2 for x, y in rows) / n
    return m, b, mse


def reset_dynamic_inputs(datasets):
    data_dir = Path("/home/user/datasets")
    organized = Path("/home/user/organized")
    shutil.rmtree(data_dir, ignore_errors=True)
    shutil.rmtree(organized / "low_error", ignore_errors=True)
    shutil.rmtree(organized / "high_error", ignore_errors=True)
    try:
        (organized / "metrics.txt").unlink()
    except FileNotFoundError:
        pass

    data_dir.mkdir(parents=True, exist_ok=True)
    organized.mkdir(parents=True, exist_ok=True)
    for filename, rows in datasets.items():
        with (data_dir / filename).open("w") as f:
            f.write("x,y\n")
            for x, y in rows:
                f.write(f"{x},{y}\n")


def dynamic_state_is_correct(datasets):
    data_dir = Path("/home/user/datasets")
    organized = Path("/home/user/organized")
    metrics = organized / "metrics.txt"
    if not (organized / "low_error").is_dir() or not (organized / "high_error").is_dir() or not metrics.is_file():
        return False

    expected_lines = []
    expected_low = []
    expected_high = []
    for filename in sorted(datasets):
        m, b, mse = ols(datasets[filename])
        expected_lines.append(f"{filename}: m={m:.4f}, b={b:.4f}, MSE={mse:.4f}")
        (expected_low if mse < 1.0 else expected_high).append(filename)

    try:
        actual_lines = [line.strip() for line in metrics.read_text().splitlines() if line.strip()]
    except OSError:
        return False
    if actual_lines != expected_lines:
        return False

    low_files = sorted(p.name for p in (organized / "low_error").iterdir() if p.is_file())
    high_files = sorted(p.name for p in (organized / "high_error").iterdir() if p.is_file())
    if low_files != sorted(expected_low) or high_files != sorted(expected_high):
        return False
    return not any(data_dir.glob("*.csv"))


def test_compilable_automated_pipeline_on_unseen_csvs():
    sources, scripts = discover_artifacts()
    assert sources, "No submitted C++ source file was found."
    assert scripts, "No accompanying shell script was found."

    compilable = []
    for index, source in enumerate(sources):
        output = Path(f"/tmp/verifier_cpp_{index}")
        result = subprocess.run(
            ["g++", "-O2", "-std=c++17", str(source), "-o", str(output)],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
        if result.returncode == 0 and output.is_file():
            compilable.append(source)
    assert compilable, "No submitted C++ source file compiles successfully with g++ -O2."

    # Use unpredictable filenames and values so fixture-specific moves and constants cannot pass.
    token = secrets.token_hex(4)
    offset = secrets.choice([0.37, 0.63, 1.17, 1.43])
    datasets = {
        f"alpha_{token}.csv": [(-2, -3.0 + offset), (0, 1.0 + offset), (2, 5.0 + offset), (5, 11.0 + offset)],
        f"middle_{token}.csv": [(-1, 4.12), (0, 2.81), (1, 2.17), (3, -0.24), (6, -3.08)],
        f"zeta_{token}.csv": [(-2, 1.0), (-1, 8.0), (1, -5.0), (2, 10.0), (4, -7.0)],
    }

    source_dirs = {p.parent.resolve() for p in compilable}
    plausible_scripts = []
    for script in scripts:
        try:
            text = script.read_text(errors="ignore")
        except OSError:
            continue
        nearby_source = script.parent.resolve() in source_dirs
        pipeline_words = "datasets" in text and "organized" in text
        source_reference = any(src.name in text for src in compilable)
        if nearby_source or pipeline_words or source_reference:
            plausible_scripts.append(script)

    assert plausible_scripts, "No shell script appears to automate the submitted C++ data pipeline."

    errors = []
    for script in plausible_scripts:
        reset_dynamic_inputs(datasets)
        try:
            result = subprocess.run(
                ["bash", str(script)],
                cwd=str(script.parent),
                env={**os.environ, "HOME": "/home/user"},
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=30,
            )
        except (subprocess.TimeoutExpired, OSError) as exc:
            errors.append(f"{script}: {exc}")
            continue

        if result.returncode == 0 and dynamic_state_is_correct(datasets):
            return
        errors.append(f"{script}: exit={result.returncode}, stdout={result.stdout[-300:]!r}, stderr={result.stderr[-300:]!r}")

    pytest.fail("No submitted shell script correctly processed the unseen CSV files. " + " | ".join(errors))
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
