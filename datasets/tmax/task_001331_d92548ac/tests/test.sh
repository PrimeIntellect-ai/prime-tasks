#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_c_source_file_exists():
    file_path = "/home/user/dedup.c"
    assert os.path.isfile(file_path), f"The C source file {file_path} is missing."

def test_cleaned_products_file_exists():
    file_path = "/home/user/cleaned_products.txt"
    assert os.path.isfile(file_path), f"The output file {file_path} is missing."

def test_cleaned_products_content():
    file_path = "/home/user/cleaned_products.txt"
    assert os.path.isfile(file_path), f"The output file {file_path} is missing."

    expected_lines = [
        "apple iphone 14",
        "samsung galaxy s23",
        "google pixel 7",
        "sony xperia 1",
        "oneplus 11"
    ]

    with open(file_path, "r") as f:
        actual_lines = [line.strip("\n") for line in f.readlines()]

    # Strip any trailing empty lines if present
    while actual_lines and actual_lines[-1] == "":
        actual_lines.pop()

    assert actual_lines == expected_lines, f"The contents of {file_path} do not match the expected deduplicated output."
TEST_EOF

cat << 'TEST_EOF' > /tmp/test_behavior.py
import os
import random
import re
import string
import subprocess

SOURCE = "/home/user/dedup.c"
BINARY = "/tmp/dedup_verifier_binary"
INPUT = "/home/user/products.txt"
OUTPUT = "/home/user/cleaned_products.txt"


def normalize(value):
    value = value.strip(" ")
    value = re.sub(r" +", " ", value)
    return "".join(chr(ord(c) + 32) if "A" <= c <= "Z" else c for c in value)


def distance(a, b):
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


def oracle(raw_lines):
    accepted = []
    for raw in raw_lines:
        item = normalize(raw)
        if all(distance(item, old) > 1 for old in accepted):
            accepted.append(item)
    return accepted


def run_case(raw_lines):
    with open(INPUT, "w", encoding="utf-8", newline="\n") as f:
        for line in raw_lines:
            f.write(line + "\n")

    if os.path.lexists(OUTPUT):
        os.unlink(OUTPUT)

    completed = subprocess.run(
        [BINARY], cwd="/home/user", stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, timeout=5, text=True
    )
    assert completed.returncode == 0, (
        f"Compiled program exited with status {completed.returncode}: "
        f"{completed.stderr}"
    )
    assert os.path.isfile(OUTPUT), "Compiled program did not create cleaned_products.txt"

    with open(OUTPUT, "r", encoding="utf-8") as f:
        actual = f.read().splitlines()
    expected = oracle(raw_lines)
    assert actual == expected, f"Program output {actual!r}, expected {expected!r}"


def main():
    assert os.path.isfile(SOURCE), f"The C source file {SOURCE} is missing."
    compiled = subprocess.run(
        ["gcc", "-O2", SOURCE, "-o", BINARY],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20, text=True
    )
    assert compiled.returncode == 0, f"dedup.c did not compile: {compiled.stderr}"
    assert os.path.isfile(BINARY) and os.access(BINARY, os.X_OK)

    original = [
        "  Apple iPhone 14",
        "apple iphone  14",
        "Samsung Galaxy S23",
        "Samsvng Galaxy S23",
        "google pixel 7",
        "Google Pixel  7",
        "Sony Xperia 1",
        "sony xperib 1",
        "  oneplus 11  ",
    ]
    run_case(original)

    run_case([
        "   Alpha   Widget   ",
        "ALPHA WIDGET",
        "alpha widgit",
        "Beta Tool",
        " beta   tools ",
        "Gamma",
        "gamm",
        "Delta Product",
    ])

    # This case checks that comparisons are made only against accepted entries:
    # 'bat' is discarded as a duplicate of 'cat', while 'bad' must be accepted.
    run_case([
        "CAT",
        " bat ",
        "bad",
        "  LONG    PRODUCT NAME ",
        "long product namf",
        "another-item",
        "another_item",
        "final product",
    ])

    rng = random.Random(917263)
    raw = []
    alphabet = string.ascii_lowercase
    for index in range(18):
        left = "".join(rng.choice(alphabet) for _ in range(5 + index % 3))
        right = "".join(rng.choice(alphabet) for _ in range(4 + index % 4))
        base = left + " " + right
        raw.append("  " + base.upper() + "  ")
        raw.append(left + "   " + right)
        position = rng.randrange(len(base))
        replacement = "z" if base[position] != "z" else "y"
        raw.append(base[:position] + replacement + base[position + 1:])
    run_case(raw)


if __name__ == "__main__":
    main()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1 && python3 /tmp/test_behavior.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
