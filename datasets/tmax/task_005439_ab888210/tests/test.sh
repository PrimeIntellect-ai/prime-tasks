#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
from pathlib import Path
import secrets
import subprocess

import pytest

CLEANER = Path("/home/user/cleaner")
INPUT = Path("/home/user/sensor_data.csv")
OUTPUT = Path("/home/user/cleaned_data.csv")

CANONICAL_INPUT = (
    "temp,pressure,humidity,vibration\n"
    "10.0,101.2,45.0,0.5\n"
    "12.0,101.5,41.0,0.6\n"
    "14.0,101.1,37.0,0.5\n"
    "16.0,100.9,,0.4\n"
    "18.0,100.8,29.0,0.5\n"
    "20.0,100.5,25.0,0.6\n"
)

EXPECTED_CANONICAL = (
    "temp,pressure,humidity,vibration\n"
    "10.0,101.2,45.0,0.5\n"
    "12.0,101.5,41.0,0.6\n"
    "14.0,101.1,37.0,0.5\n"
    "16.0,100.9,33.0,0.4\n"
    "18.0,100.8,29.0,0.5\n"
    "20.0,100.5,25.0,0.6"
)


def run_cleaner():
    if OUTPUT.exists():
        OUTPUT.unlink()
    result = subprocess.run(
        ["cargo", "run", "--quiet", "--manifest-path", str(CLEANER / "Cargo.toml")],
        cwd=str(CLEANER),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=120,
    )
    assert result.returncode == 0, f"The Rust cleaner failed to compile or run:\n{result.stdout}"
    assert OUTPUT.exists(), "The Rust cleaner ran but did not create /home/user/cleaned_data.csv"
    assert OUTPUT.is_file(), "/home/user/cleaned_data.csv is not a regular file"


def pearson(xs, ys):
    mx = sum(xs) / len(xs)
    my = sum(ys) / len(ys)
    numerator = sum((x - mx) * (y - my) for x, y in zip(xs, ys))
    dx = sum((x - mx) ** 2 for x in xs)
    dy = sum((y - my) ** 2 for y in ys)
    return numerator / math.sqrt(dx * dy)


def expected_output(rows):
    feature_names = ["temp", "pressure", "vibration"]
    complete = [row for row in rows if row["humidity"] is not None]
    ys = [row["humidity"] for row in complete]
    correlations = {
        name: pearson([row[name] for row in complete], ys)
        for name in feature_names
    }
    selected = max(feature_names, key=lambda name: abs(correlations[name]))
    xs = [row[selected] for row in complete]
    mean_x = sum(xs) / len(xs)
    mean_y = sum(ys) / len(ys)
    slope = sum((x - mean_x) * (y - mean_y) for x, y in zip(xs, ys)) / sum(
        (x - mean_x) ** 2 for x in xs
    )
    intercept = mean_y - slope * mean_x

    lines = ["temp,pressure,humidity,vibration"]
    for row in rows:
        humidity = row["humidity"]
        if humidity is None:
            humidity = slope * row[selected] + intercept
        lines.append(
            f'{row["temp"]:.1f},{row["pressure"]:.1f},{humidity:.1f},{row["vibration"]:.1f}'
        )
    return "\n".join(lines)


def make_case(selected_feature):
    rng = secrets.SystemRandom()
    count = 12
    missing = set(rng.sample(range(count), 2))

    while True:
        values = {
            "temp": [v / 10.0 for v in rng.sample(range(80, 500), count)],
            "pressure": [v / 10.0 for v in rng.sample(range(700, 1300), count)],
            "vibration": [v / 10.0 for v in rng.sample(range(1, 300), count)],
        }
        slope = rng.choice([-3, -2, -1, 1, 2, 3])
        intercept = rng.randint(-30, 30)
        full_y = [slope * x + intercept for x in values[selected_feature]]
        complete_indices = [i for i in range(count) if i not in missing]
        complete_y = [full_y[i] for i in complete_indices]

        acceptable = True
        for name in ("temp", "pressure", "vibration"):
            if name == selected_feature:
                continue
            corr = pearson([values[name][i] for i in complete_indices], complete_y)
            if abs(corr) >= 0.80:
                acceptable = False
                break
        if acceptable:
            break

    rows = []
    for i in range(count):
        rows.append({
            "temp": values["temp"][i],
            "pressure": values["pressure"][i],
            "humidity": None if i in missing else full_y[i],
            "vibration": values["vibration"][i],
        })
    return rows


def write_input(rows):
    lines = ["temp,pressure,humidity,vibration"]
    for row in rows:
        humidity = "" if row["humidity"] is None else f'{row["humidity"]:.1f}'
        lines.append(
            f'{row["temp"]:.1f},{row["pressure"]:.1f},{humidity},{row["vibration"]:.1f}'
        )
    INPUT.write_text("\n".join(lines) + "\n")


def test_cleaned_data_exists_and_correct():
    # Preserve the original final-state assertions.
    file_path = "/home/user/cleaned_data.csv"
    assert os.path.exists(file_path), f"The output file {file_path} is missing. Did the Rust program run and save the file?"
    assert os.path.isfile(file_path), f"The path {file_path} is not a file."
    with open(file_path, "r") as f:
        actual_content = f.read().strip()
    assert actual_content == EXPECTED_CANONICAL, (
        f"The content of {file_path} does not match the expected final state.\n"
        f"Expected:\n{EXPECTED_CANONICAL}\n\nActual:\n{actual_content}\n"
        "Ensure the missing value is correctly imputed and all numbers are formatted to one decimal place."
    )

    # Require an actual Cargo-based Rust implementation.
    assert CLEANER.exists() and CLEANER.is_dir(), "/home/user/cleaner must be a Rust project directory"
    assert (CLEANER / "Cargo.toml").is_file(), "/home/user/cleaner/Cargo.toml is missing"
    rust_sources = [p for p in CLEANER.rglob("*.rs") if p.is_file() and p.stat().st_size > 0]
    assert rust_sources, "/home/user/cleaner contains no non-empty Rust source files"

    # Restore the supplied dataset and prove the program itself regenerates the required fixed output.
    INPUT.write_text(CANONICAL_INPUT)
    run_cleaner()
    assert OUTPUT.read_text().strip() == EXPECTED_CANONICAL

    # Exercise every possible predictor position on unpredictable datasets. Expected answers are
    # independently derived from Pearson correlation and least-squares regression.
    for selected_feature in ("temp", "pressure", "vibration"):
        rows = make_case(selected_feature)
        expected = expected_output(rows)
        write_input(rows)
        run_cleaner()
        actual = OUTPUT.read_text().strip()
        assert actual == expected, (
            f"Incorrect output when humidity is most strongly correlated with {selected_feature}.\n"
            f"Expected:\n{expected}\n\nActual:\n{actual}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
