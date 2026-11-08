#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import string
import subprocess
import tempfile
import pytest

PIN_FILE = "/home/user/cracked_pin.txt"
SOURCE_FILE = "/home/user/path_filter.c"
BINARY_FILE = "/home/user/path_filter"


def run_filter(binary, value):
    try:
        return subprocess.run(
            [binary, value], capture_output=True, timeout=2, check=False
        ).returncode
    except Exception as exc:
        pytest.fail(f"Could not execute {binary!r} on {value!r}: {exc}")


def test_cracked_pin():
    assert os.path.exists(PIN_FILE), f"Expected file {PIN_FILE} does not exist."
    with open(PIN_FILE, "r") as f:
        pin = f.read().strip()
    assert pin == "7482", f"Incorrect PIN. Expected '7482', got '{pin}'."


def test_path_filter_binary_exists():
    assert os.path.exists(BINARY_FILE), f"Compiled binary {BINARY_FILE} does not exist."
    assert os.path.isfile(BINARY_FILE), f"{BINARY_FILE} is not a regular file."
    assert os.access(BINARY_FILE, os.X_OK), f"File {BINARY_FILE} is not executable."
    with open(BINARY_FILE, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{BINARY_FILE} is not a compiled ELF binary."


def test_c_source_exists_and_compiles():
    assert os.path.exists(SOURCE_FILE), f"Expected C source {SOURCE_FILE} does not exist."
    assert os.path.isfile(SOURCE_FILE), f"{SOURCE_FILE} is not a regular file."
    assert os.path.getsize(SOURCE_FILE) > 0, f"C source {SOURCE_FILE} is empty."
    output = "/tmp/path_filter_from_source"
    result = subprocess.run(
        ["gcc", "-std=c11", "-O2", "-Wall", "-Wextra", SOURCE_FILE, "-o", output],
        capture_output=True,
        text=True,
        timeout=15,
        check=False,
    )
    assert result.returncode == 0, f"C source does not compile:\n{result.stderr}"
    assert os.access(output, os.X_OK), "Compiled C source did not produce an executable."


def test_adversarial_corpus():
    clean_dir = "/app/corpus/clean/"
    evil_dir = "/app/corpus/evil/"

    assert os.path.exists(clean_dir), f"Clean corpus directory missing at {clean_dir}"
    assert os.path.exists(evil_dir), f"Evil corpus directory missing at {evil_dir}"

    clean_failed = []
    clean_total = 0
    for filename in sorted(os.listdir(clean_dir)):
        filepath = os.path.join(clean_dir, filename)
        if os.path.isfile(filepath):
            clean_total += 1
            with open(filepath, "r") as f:
                content = f.read()
            if run_filter(BINARY_FILE, content) != 0:
                clean_failed.append(filename)

    evil_failed = []
    evil_total = 0
    for filename in sorted(os.listdir(evil_dir)):
        filepath = os.path.join(evil_dir, filename)
        if os.path.isfile(filepath):
            evil_total += 1
            with open(filepath, "r") as f:
                content = f.read()
            if run_filter(BINARY_FILE, content) != 1:
                evil_failed.append(filename)

    errors = []
    if evil_failed:
        errors.append(f"{len(evil_failed)} of {evil_total} evil bypassed: {', '.join(evil_failed)}")
    if clean_failed:
        errors.append(f"{len(clean_failed)} of {clean_total} clean modified: {', '.join(clean_failed)}")
    if errors:
        pytest.fail(" | ".join(errors))


def random_word(min_len=5, max_len=14):
    alphabet = string.ascii_letters + string.digits + "_-"
    return "".join(secrets.choice(alphabet) for _ in range(min_len + secrets.randbelow(max_len - min_len + 1)))


def generated_cases():
    clean = []
    evil = []

    extensions = ["txt", "pdf", "jpg", "png", "csv", "json", "tar.gz", "log"]
    for _ in range(45):
        base = random_word()
        ext = secrets.choice(extensions)
        clean.append(f"{base}.{ext}")
        clean.append(f"{random_word()}/{base}.{ext}")

    for _ in range(15):
        clean.append(f".{random_word()}")
        clean.append(f"{random_word()}..{random_word()}.txt")

    dot_pairs = ["..", ".%2e", ".%2E", "%2e.", "%2E.", "%2e%2e", "%2E%2E", "%2e%2E"]
    separators = ["/", "\\", "%2f", "%2F", "%5c", "%5C"]
    for _ in range(100):
        traversal = secrets.choice(dot_pairs) + secrets.choice(separators)
        evil.append(random_word() + "/" + traversal + random_word() + ".txt")

    for _ in range(25):
        evil.append(random_word() + "%00." + secrets.choice(extensions))
        evil.append(random_word() + "\\0" + random_word())

    for _ in range(20):
        evil.append(random_word() + ("." * (4 + secrets.randbelow(5))) + "//" + random_word())

    secrets.SystemRandom().shuffle(clean)
    secrets.SystemRandom().shuffle(evil)
    return clean, evil


def test_randomized_general_filter_behavior():
    rebuilt = "/tmp/path_filter_from_source"
    assert os.path.exists(rebuilt), "Rebuilt C executable is missing."
    clean, evil = generated_cases()

    for binary in (BINARY_FILE, rebuilt):
        clean_failures = [value for value in clean if run_filter(binary, value) != 0]
        evil_failures = [value for value in evil if run_filter(binary, value) != 1]
        assert not clean_failures, f"{binary} rejected generated clean names, including {clean_failures[:5]!r}"
        assert not evil_failures, f"{binary} allowed generated traversal vectors, including {evil_failures[:5]!r}"


def test_exactly_one_argument_contract():
    for binary in (BINARY_FILE, "/tmp/path_filter_from_source"):
        no_arg = subprocess.run([binary], capture_output=True, timeout=2, check=False)
        two_args = subprocess.run([binary, "safe.txt", "extra.txt"], capture_output=True, timeout=2, check=False)
        assert no_arg.returncode != 0, f"{binary} accepted zero filename arguments."
        assert two_args.returncode != 0, f"{binary} accepted more than one filename argument."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
