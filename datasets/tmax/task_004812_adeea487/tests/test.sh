#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import pwd
import random
import re
import subprocess

import pytest

SCRIPT_PATH = "/home/user/prefilter.py"
DECODER_PATH = "/app/legacy_decoder"
USER = pwd.getpwnam("user")


def demote_to_user():
    os.setgroups([])
    os.setgid(USER.pw_gid)
    os.setuid(USER.pw_uid)


def run_prefilter(token, extra_args=()):
    try:
        result = subprocess.run(
            ["python3", SCRIPT_PATH, token, *extra_args],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=2,
            preexec_fn=demote_to_user,
        )
        return result.returncode
    except subprocess.TimeoutExpired:
        return 124


def expected_safe(token):
    if not isinstance(token, str) or len(token) % 2 != 0:
        return False
    if re.fullmatch(r"[0-9a-fA-F]*", token) is None:
        return False
    try:
        data = bytes.fromhex(token)
    except ValueError:
        return False
    if len(data) < 4 or data[:4] != b"TOKN":
        return False

    pos = 4
    while pos < len(data):
        if pos + 3 > len(data):
            return False
        record_type = data[pos]
        value_len = int.from_bytes(data[pos + 1:pos + 3], "big")
        if pos + 3 + value_len > len(data):
            return False
        if record_type == 2 and value_len > 32:
            return False
        pos += 3 + value_len
    return True


@pytest.fixture(scope="session", autouse=True)
def prevent_decoder_oracle():
    # Hidden cases must be parsed by the submitted implementation, not delegated
    # to the unsafe legacy executable.
    old_mode = os.stat(DECODER_PATH).st_mode & 0o7777
    os.chmod(DECODER_PATH, 0o700)
    try:
        yield
    finally:
        os.chmod(DECODER_PATH, old_mode)


def test_prefilter_exists():
    assert os.path.exists(SCRIPT_PATH), f"Missing prefilter script at {SCRIPT_PATH}"
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is not a file"


def test_clean_corpus_preserved():
    clean_dir = "/app/corpus/clean/"
    assert os.path.exists(clean_dir), f"Missing clean corpus directory at {clean_dir}"
    txt_files = glob.glob(os.path.join(clean_dir, "*.txt"))
    assert len(txt_files) > 0, "No clean corpus files found."

    failed_files = []
    for file_path in txt_files:
        with open(file_path, "r") as f:
            hex_token = f.read().strip()
        if run_prefilter(hex_token) != 0:
            failed_files.append(os.path.basename(file_path))

    if failed_files:
        pytest.fail(
            f"{len(failed_files)} of {len(txt_files)} clean modified/rejected: "
            + ", ".join(failed_files[:10])
            + ("..." if len(failed_files) > 10 else "")
        )


def test_evil_corpus_rejected():
    evil_dir = "/app/corpus/evil/"
    assert os.path.exists(evil_dir), f"Missing evil corpus directory at {evil_dir}"
    txt_files = glob.glob(os.path.join(evil_dir, "*.txt"))
    assert len(txt_files) > 0, "No evil corpus files found."

    failed_files = []
    for file_path in txt_files:
        with open(file_path, "r") as f:
            hex_token = f.read().strip()
        if run_prefilter(hex_token) != 1:
            failed_files.append(os.path.basename(file_path))

    if failed_files:
        pytest.fail(
            f"{len(failed_files)} of {len(txt_files)} evil bypassed/accepted: "
            + ", ".join(failed_files[:10])
            + ("..." if len(failed_files) > 10 else "")
        )


def test_unseen_generated_tokens():
    rng = random.SystemRandom()
    exposed = set()
    for directory in ("/app/corpus/clean", "/app/corpus/evil"):
        for path in glob.glob(os.path.join(directory, "*.txt")):
            with open(path, "r") as f:
                exposed.add(f.read().strip())

    cases = []

    # Valid tokens with empty, multiple, type-2 boundary, and unknown-type records.
    cases.extend(["544f4b4e", "544F4B4E020000", "544f4b4e020020" + os.urandom(32).hex()])
    while len(cases) < 70:
        data = bytearray(b"TOKN")
        for _ in range(rng.randrange(1, 7)):
            record_type = rng.choice([0, 1, 2, 3, 17, 255])
            value_len = rng.randrange(0, 33) if record_type == 2 else rng.randrange(0, 97)
            data.append(record_type)
            data.extend(value_len.to_bytes(2, "big"))
            data.extend(os.urandom(value_len))
        token = data.hex()
        if token not in exposed:
            cases.append(token)

    # Complete overflow records, truncated headers/payloads, and bad framing.
    for _ in range(35):
        value_len = rng.randrange(33, 160)
        cases.append((b"TOKN" + bytes([2]) + value_len.to_bytes(2, "big") + os.urandom(value_len)).hex())
    for _ in range(35):
        actual = rng.randrange(0, 50)
        declared = actual + rng.randrange(1, 100)
        record_type = rng.choice([0, 1, 3, 255])
        cases.append((b"TOKN" + bytes([record_type]) + declared.to_bytes(2, "big") + os.urandom(actual)).hex())
    for suffix_len in (1, 2):
        for _ in range(15):
            cases.append((b"TOKN" + os.urandom(suffix_len)).hex())

    cases.extend([
        "",
        "54",
        "544f4b",
        "42414421",
        "544f4b4",
        "544f4b4ez0",
        "544f 4b4e",
        "0x544f4b4e",
        "544f4b4e02",
        "544f4b4e0200",
    ])

    failures = []
    for token in cases:
        expected = 0 if expected_safe(token) else 1
        actual = run_prefilter(token)
        if actual != expected:
            failures.append((token[:80], expected, actual))

    assert not failures, f"Misclassified unseen generated tokens: {failures[:10]}"


def test_exactly_one_argument_required():
    no_arg = subprocess.run(
        ["python3", SCRIPT_PATH],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=2,
        preexec_fn=demote_to_user,
    )
    assert no_arg.returncode == 1
    assert run_prefilter("544f4b4e", ("extra",)) == 1
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
