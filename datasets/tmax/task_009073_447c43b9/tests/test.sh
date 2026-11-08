#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import re
import secrets
import subprocess
from pathlib import Path

import pytest

HOME = Path("/home/user")


def run_make():
    for path in (HOME / "cleaned.txt", HOME / "localization_report.csv"):
        path.unlink(missing_ok=True)
    result = subprocess.run(
        ["make", "-B"], cwd=HOME, text=True, capture_output=True, timeout=120
    )
    assert result.returncode == 0, (
        f"make failed\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


@pytest.fixture(scope="module", autouse=True)
def build_pipeline():
    makefile = HOME / "Makefile"
    assert makefile.is_file(), f"{makefile} does not exist. A Makefile is required."

    go_files = list(HOME.rglob("*.go"))
    assert go_files, "No Go source file was created under /home/user."

    dry_run = subprocess.run(
        ["make", "-n", "-B", "all"],
        cwd=HOME,
        text=True,
        capture_output=True,
        timeout=30,
    )
    assert dry_run.returncode == 0, (
        f"The required all target is missing or invalid:\n{dry_run.stderr}"
    )
    commands = dry_run.stdout + "\n" + dry_run.stderr
    assert re.search(r"\bgo\s+(?:run|build)\b", commands), (
        "The all target must compile and run the Go matching stage using go run or go build."
    )

    run_make()


def test_makefile_exists():
    makefile_path = "/home/user/Makefile"
    assert os.path.isfile(makefile_path), f"{makefile_path} does not exist. A Makefile is required."


def test_cleaned_txt_content():
    cleaned_path = "/home/user/cleaned.txt"
    assert os.path.isfile(cleaned_path), f"{cleaned_path} does not exist. Make sure Stage 1 creates this file."

    expected_lines = [
        "hello world",
        "save file",
        "delete items",
        "user profiles",
        "save game"
    ]

    with open(cleaned_path, "r") as f:
        actual_lines = [line.strip() for line in f.read().strip().splitlines()]

    assert actual_lines == expected_lines, (
        f"Content of {cleaned_path} does not match expected output.\n"
        f"Expected: {expected_lines}\n"
        f"Got: {actual_lines}"
    )


def test_localization_report_csv_content():
    csv_path = "/home/user/localization_report.csv"
    assert os.path.isfile(csv_path), f"{csv_path} does not exist. Make sure the Go program generates this file."

    expected_content = (
        "CleanedSource,BestMatchTarget,Distance,RollingAvg\n"
        "hello world,hola mundo,0,0.00\n"
        "save file,guardar archivo,0,0.00\n"
        "delete items,eliminar elemento,1,0.33\n"
        "user profiles,perfil de usuario,1,0.67\n"
        "save game,guardar archivo,3,1.67"
    )

    with open(csv_path, "r") as f:
        actual_content = f.read().strip()

    assert actual_content == expected_content, (
        f"Content of {csv_path} does not match expected output.\n"
        f"Expected:\n{expected_content}\n"
        f"Got:\n{actual_content}"
    )


def levenshtein(a, b):
    previous = list(range(len(b) + 1))
    for i, ca in enumerate(a, 1):
        current = [i]
        for j, cb in enumerate(b, 1):
            current.append(min(
                current[-1] + 1,
                previous[j] + 1,
                previous[j - 1] + (ca != cb),
            ))
        previous = current
    return previous[-1]


def clean_lines(text):
    result = []
    seen = set()
    for line in text.splitlines():
        cleaned = " ".join(line.strip().lower().split())
        if cleaned not in seen:
            seen.add(cleaned)
            result.append(cleaned)
    return result


def expected_rows(cleaned, tm):
    distances = []
    rows = [["CleanedSource", "BestMatchTarget", "Distance", "RollingAvg"]]
    for source in cleaned:
        best_index = min(range(len(tm)), key=lambda i: levenshtein(source, tm[i]["source"]))
        distance = levenshtein(source, tm[best_index]["source"])
        distances.append(distance)
        window = distances[max(0, len(distances) - 3):]
        rows.append([
            source,
            tm[best_index]["target"],
            str(distance),
            f"{sum(window) / len(window):.2f}",
        ])
    return rows


def test_pipeline_recomputes_for_changed_inputs():
    tm_path = HOME / "tm.json"
    strings_path = HOME / "new_strings.txt"
    original_tm = tm_path.read_bytes()
    original_strings = strings_path.read_bytes()

    token = secrets.token_hex(6)
    tm = [
        {"source": f"{token} cat", "target": "first tie target"},
        {"source": f"{token} cut", "target": "second tie target"},
        {"source": f"alpha {token}", "target": "exact target"},
        {"source": f"kitten {token}", "target": "kitten target"},
    ]
    new_text = (
        f"  {token.upper()} COT  \n"
        f"Alpha    {token.upper()}\n"
        f"{token} cot\n"
        f"sitting {token}\n"
    )

    try:
        tm_path.write_text(json.dumps(tm), encoding="utf-8")
        strings_path.write_text(new_text, encoding="utf-8")
        run_make()

        cleaned = clean_lines(new_text)
        assert (HOME / "cleaned.txt").read_text(encoding="utf-8").splitlines() == cleaned

        with (HOME / "localization_report.csv").open(newline="", encoding="utf-8") as f:
            actual_rows = list(csv.reader(f))
        assert actual_rows == expected_rows(cleaned, tm)
    finally:
        tm_path.write_bytes(original_tm)
        strings_path.write_bytes(original_strings)


TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
