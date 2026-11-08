#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import secrets
import subprocess

PROJECT_DIR = "/home/user/project"
MAKEFILE = os.path.join(PROJECT_DIR, "Makefile")
SCRIPT = "/home/user/build_and_verify.sh"
CHECKSUM_FILE = "/home/user/checksum.txt"
MATH_SOURCE = os.path.join(PROJECT_DIR, "math_utils.c")


def fletcher16(values):
    sum1 = 0
    sum2 = 0
    for value in values:
        sum1 = (sum1 + value) % 255
        sum2 = (sum2 + sum1) % 255
    return (sum2 * 256) + sum1


def original_sequence():
    return [(n * n + 3 * n) % 256 for n in range(1, 51)]


def get_expected_checksum():
    return fletcher16(original_sequence())


def read_sequence():
    seq_path = os.path.join(PROJECT_DIR, "sequence.json")
    assert os.path.isfile(seq_path), "./app did not produce sequence.json"
    with open(seq_path, "r") as f:
        data = json.load(f)
    assert isinstance(data, dict), "sequence.json must contain a JSON object"
    assert set(data) == {"sequence"}, 'sequence.json must contain only the key "sequence"'
    assert isinstance(data["sequence"], list), 'the "sequence" value must be an array'
    assert all(type(v) is int for v in data["sequence"]), "sequence must contain only integers"
    return data["sequence"]


def test_makefile_fixed():
    assert os.path.isfile(MAKEFILE), f"{MAKEFILE} is missing"

    # Run make clean to ensure a fresh build
    subprocess.run(["make", "clean"], cwd=PROJECT_DIR, capture_output=True)

    # Run make
    res = subprocess.run(["make"], cwd=PROJECT_DIR, capture_output=True)
    assert res.returncode == 0, f"make failed with output: {res.stderr.decode()}"

    app_path = os.path.join(PROJECT_DIR, "app")
    assert os.path.isfile(app_path), "make did not produce 'app' executable. The Makefile might not be linking correctly."
    assert os.access(app_path, os.X_OK), "app is not executable"
    with open(app_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "app is not a compiled ELF executable"

    main_obj = os.path.join(PROJECT_DIR, "main.o")
    math_obj = os.path.join(PROJECT_DIR, "math_utils.o")
    assert os.path.isfile(main_obj), "make did not compile main.o"
    assert os.path.isfile(math_obj), "make did not compile math_utils.o"

    main_nm = subprocess.run(["nm", main_obj], capture_output=True, text=True)
    math_nm = subprocess.run(["nm", math_obj], capture_output=True, text=True)
    app_nm = subprocess.run(["nm", app_path], capture_output=True, text=True)
    assert main_nm.returncode == 0 and re.search(r"\bU\s+compute_val$", main_nm.stdout, re.M), "main.o does not reference compute_val"
    assert math_nm.returncode == 0 and re.search(r"\b[Tt]\s+compute_val$", math_nm.stdout, re.M), "math_utils.o does not define compute_val"
    assert app_nm.returncode == 0 and re.search(r"\b[Tt]\s+compute_val$", app_nm.stdout, re.M), "app does not contain the linked compute_val implementation"

    # Run app
    res = subprocess.run(["./app"], cwd=PROJECT_DIR, capture_output=True)
    assert res.returncode == 0, f"./app failed with output: {res.stderr.decode()}"

    seq_path = os.path.join(PROJECT_DIR, "sequence.json")
    assert os.path.isfile(seq_path), "./app did not produce sequence.json"
    assert read_sequence() == original_sequence(), "app generated an incorrect sequence"


def test_script_exists_and_executable():
    assert os.path.isfile(SCRIPT), f"{SCRIPT} is missing"
    assert os.access(SCRIPT, os.X_OK), f"{SCRIPT} is not executable"


def test_checksum_file():
    assert os.path.isfile(CHECKSUM_FILE), f"{CHECKSUM_FILE} is missing"
    with open(CHECKSUM_FILE, "r") as f:
        content = f.read().strip()

    expected = str(get_expected_checksum())
    assert content == expected, f"Expected checksum {expected}, got {content} in {CHECKSUM_FILE}"


def test_script_execution():
    # Exercise the pipeline on a verifier-selected sequence so a fixed checksum
    # cannot pass. The original source and output are restored afterward.
    with open(MATH_SOURCE, "r") as f:
        original_source = f.read()

    while True:
        multiplier = secrets.randbelow(250) + 1
        offset = secrets.randbelow(256)
        expected_sequence = [(multiplier * n + offset) % 256 for n in range(1, 51)]
        expected = fletcher16(expected_sequence)
        if expected != get_expected_checksum():
            break

    replacement = f'''#include "math_utils.h"

int compute_val(int n) {{
    return ({multiplier} * n + {offset}) % 256;
}}
'''

    try:
        with open(MATH_SOURCE, "w") as f:
            f.write(replacement)

        # Remove the checksum file to ensure the script generates it
        if os.path.exists(CHECKSUM_FILE):
            os.remove(CHECKSUM_FILE)

        res = subprocess.run([SCRIPT], capture_output=True)
        assert res.returncode == 0, f"Script {SCRIPT} failed with exit code {res.returncode}. Error output: {res.stderr.decode()}"

        assert read_sequence() == expected_sequence, "the script did not rebuild and run app to generate the verifier-selected sequence"
        assert os.path.isfile(CHECKSUM_FILE), f"Script did not generate {CHECKSUM_FILE}"
        with open(CHECKSUM_FILE, "r") as f:
            content = f.read().strip()

        assert content == str(expected), f"Script generated incorrect checksum. Expected {expected}, got {content}"
    finally:
        with open(MATH_SOURCE, "w") as f:
            f.write(original_source)
        # Return generated artifacts to the task's original state.
        subprocess.run([SCRIPT], capture_output=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
