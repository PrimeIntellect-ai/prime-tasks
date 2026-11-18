#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/verify_task.py
import json
import os
import re
import shutil
import subprocess
import sys
import uuid

SCRIPT = "/home/user/clean_data.py"
RAW_DIR = "/home/user/raw_data"
OUTPUT = "/home/user/processed_sample.json"

EXPECTED_OUTPUT = {
    "tech": {
        "data01.txt": ["i", "love", "python", "programming"],
        "data03.txt": ["windows", "is", "an", "os", "linux", "is", "too"],
        "data05.txt": ["caf", "and", "python"]
    },
    "other": {
        "data02.txt": ["some", "random", "text"],
        "data04.txt": ["machine", "learning", "is", "fun"],
        "data06.txt": ["a", "ai", "bowl", "is", "good"]
    }
}

def run_submission():
    result = subprocess.run(
        [sys.executable, SCRIPT],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, (
        f"clean_data.py exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )

def load_output():
    assert os.path.exists(OUTPUT), f"Output file {OUTPUT} is missing."
    assert os.path.isfile(OUTPUT), f"{OUTPUT} is not a file."
    try:
        with open(OUTPUT, "r", encoding="utf-8") as f:
            return json.load(f)
    except json.JSONDecodeError as e:
        raise AssertionError(f"Failed to parse {OUTPUT} as JSON: {e}") from e
    except Exception as e:
        raise AssertionError(f"Error reading {OUTPUT}: {e}") from e

def assert_exact_output(data, expected):
    assert isinstance(data, dict), "The JSON output must be a dictionary."
    assert set(data.keys()) == {"tech", "other"}, (
        "The JSON output must have exactly two keys: 'tech' and 'other'."
    )

    tech_data = data["tech"]
    expected_tech = expected["tech"]
    assert set(tech_data.keys()) == set(expected_tech.keys()), (
        f"Expected tech files {list(expected_tech.keys())}, "
        f"but got {list(tech_data.keys())}."
    )
    for filename, tokens in expected_tech.items():
        assert tech_data[filename] == tokens, (
            f"Tokens for {filename} in 'tech' do not match expected."
        )

    other_data = data["other"]
    expected_other = expected["other"]
    assert set(other_data.keys()) == set(expected_other.keys()), (
        f"Expected other files {list(expected_other.keys())}, "
        f"but got {list(other_data.keys())}."
    )
    for filename, tokens in expected_other.items():
        assert other_data[filename] == tokens, (
            f"Tokens for {filename} in 'other' do not match expected."
        )

    assert data == expected, (
        "The overall JSON structure does not match the expected output exactly."
    )

def derive_expected(directory):
    categories = {"tech": {}, "other": {}}
    for filename in os.listdir(directory):
        path = os.path.join(directory, filename)
        if not filename.endswith(".txt") or not os.path.isfile(path):
            continue
        raw = open(path, "rb").read()
        try:
            text = raw.decode("utf-8")
        except UnicodeDecodeError:
            text = raw.decode("iso-8859-1")
        normalized = re.sub(r"[^a-z0-9 ]", " ", text.lower())
        tokens = [token for token in normalized.split(" ") if token]
        category = "tech" if "python" in tokens or "linux" in tokens else "other"
        categories[category][filename] = tokens

    return {
        category: {
            filename: categories[category][filename]
            for filename in sorted(categories[category])[:3]
        }
        for category in ("tech", "other")
    }

assert os.path.exists(SCRIPT), f"Required script {SCRIPT} is missing."
assert os.path.isfile(SCRIPT), f"{SCRIPT} is not a regular file."

# Force the submitted script to generate the output from the original files,
# then retain all of the original verifier's exact output assertions.
if os.path.lexists(OUTPUT):
    os.remove(OUTPUT)
run_submission()
assert_exact_output(load_output(), EXPECTED_OUTPUT)

# Replace the inputs temporarily with unpredictable cases so a fixed JSON cannot
# pass. These exercise UTF-8 and ISO-8859-1 decoding, normalization, exact-token
# classification, filename sorting, and three-per-category sampling.
backup = RAW_DIR + ".verifier_backup_" + uuid.uuid4().hex
os.rename(RAW_DIR, backup)
os.mkdir(RAW_DIR)
try:
    cases = [
        b"PYTHON, alpha\tBETA\n",
        b"Linux-based systems 42.",
        b"Caf\xe9 and PYTHON.",
        "A valid UTF-8 café uses linux!".encode("utf-8"),
        b"python linux extra tech entry",
        b"pythonic and linuxlike are not exact tokens",
        b"Spacing---test and digits 123.",
        b"A\xe7ai bowl is good.",
        "Symbols © disappear; ordinary words remain.".encode("utf-8"),
        b"Just another OTHER document!",
    ]
    for content in cases:
        filename = uuid.uuid4().hex + ".txt"
        with open(os.path.join(RAW_DIR, filename), "wb") as f:
            f.write(content)
    with open(os.path.join(RAW_DIR, uuid.uuid4().hex + ".dat"), "wb") as f:
        f.write(b"python must not be read from a non-txt file")

    expected_dynamic = derive_expected(RAW_DIR)
    assert len(expected_dynamic["tech"]) == 3
    assert len(expected_dynamic["other"]) == 3

    if os.path.lexists(OUTPUT):
        os.remove(OUTPUT)
    run_submission()
    assert_exact_output(load_output(), expected_dynamic)
finally:
    shutil.rmtree(RAW_DIR, ignore_errors=True)
    os.rename(backup, RAW_DIR)
    # Leave the requested artifact generated from the original dataset.
    if os.path.lexists(OUTPUT):
        os.remove(OUTPUT)
    subprocess.run(
        [sys.executable, SCRIPT],
        cwd="/home/user",
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        timeout=20,
    )
PY_EOF

if python3 /tmp/verify_task.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
