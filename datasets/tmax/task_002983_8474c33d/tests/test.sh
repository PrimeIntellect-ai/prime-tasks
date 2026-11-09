#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import string
import subprocess
import tempfile
import urllib.parse
import zipfile

BINARY = "/home/user/sanitizer"
SOURCE = "/home/user/sanitizer.cpp"
ARCHIVE = "/app/audit_logs.zip"
PASSWORD = b"739284"


def extract_corpus(temp_dir):
    with zipfile.ZipFile(ARCHIVE, "r") as zf:
        zf.extractall(path=temp_dir, pwd=PASSWORD)


def run_and_check(binary, payload_path, expected_evil):
    result = subprocess.run(
        [binary, payload_path], capture_output=True, text=True, timeout=5
    )
    expected_code = 1 if expected_evil else 0
    expected_output = "EVIL" if expected_evil else "CLEAN"
    assert result.returncode == expected_code, (
        f"Expected exit {expected_code} for {payload_path}, got {result.returncode}; "
        f"stdout={result.stdout!r}, stderr={result.stderr!r}"
    )
    assert result.stdout.strip() == expected_output, (
        f"Expected {expected_output!r} for {payload_path}, got {result.stdout!r}"
    )


def oracle(decoded):
    return (
        "../" in decoded
        or "..\\" in decoded
        or ";" in decoded
        or "|" in decoded
        or "`" in decoded
        or "$(" in decoded
    )


def encode_payload(decoded, use_plus):
    if use_plus:
        encoded = urllib.parse.quote_plus(decoded, safe="")
    else:
        encoded = urllib.parse.quote(decoded, safe="")

    # Percent escapes are case-insensitive. Randomizing their case prevents
    # classification based on one fixed spelling of the supplied corpus.
    chars = list(encoded)
    i = 0
    while i + 2 < len(chars):
        if chars[i] == "%":
            for j in (i + 1, i + 2):
                if chars[j].isalpha():
                    chars[j] = chars[j].lower() if secrets.randbelow(2) else chars[j].upper()
            i += 3
        else:
            i += 1
    return "".join(chars)


def test_sanitizer_binary_exists():
    assert os.path.isfile(BINARY), f"Sanitizer binary not found at {BINARY}"
    assert os.access(BINARY, os.X_OK), f"Sanitizer at {BINARY} is not executable"
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Sanitizer must be a compiled executable"


def test_source_exists_and_builds():
    assert os.path.isfile(SOURCE), f"C++ source not found at {SOURCE}"
    assert os.path.getsize(SOURCE) > 0, "C++ source is empty"
    result = subprocess.run(
        ["g++", "-std=c++17", SOURCE, "-o", "/tmp/sanitizer_rebuilt"],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, f"sanitizer.cpp does not compile: {result.stderr}"
    assert os.access("/tmp/sanitizer_rebuilt", os.X_OK)


def test_stage_one_corpus_was_extracted():
    assert os.path.isdir("/app/corpus/clean"), "Missing extracted clean corpus"
    assert os.path.isdir("/app/corpus/evil"), "Missing extracted evil corpus"

    with zipfile.ZipFile(ARCHIVE, "r") as zf:
        members = [info for info in zf.infolist() if not info.is_dir()]
        assert members, "Audit archive contains no payloads"
        for info in members:
            destination = os.path.join("/app/corpus", info.filename)
            assert os.path.isfile(destination), f"Missing extracted file: {info.filename}"
            with zf.open(info, pwd=PASSWORD) as archived, open(destination, "rb") as extracted:
                assert extracted.read() == archived.read(), (
                    f"Extracted file differs from archive: {info.filename}"
                )


def test_adversarial_corpus():
    with tempfile.TemporaryDirectory() as temp_dir:
        extract_corpus(temp_dir)
        evil_dir = os.path.join(temp_dir, "evil")
        clean_dir = os.path.join(temp_dir, "clean")

        evil_files = [
            os.path.join(evil_dir, f)
            for f in os.listdir(evil_dir)
            if os.path.isfile(os.path.join(evil_dir, f))
        ]
        clean_files = [
            os.path.join(clean_dir, f)
            for f in os.listdir(clean_dir)
            if os.path.isfile(os.path.join(clean_dir, f))
        ]

        evil_bypassed = []
        clean_modified = []
        for evil_file in evil_files:
            result = subprocess.run([BINARY, evil_file], capture_output=True, text=True)
            if result.returncode != 1 or result.stdout.strip() != "EVIL":
                evil_bypassed.append(os.path.basename(evil_file))
        for clean_file in clean_files:
            result = subprocess.run([BINARY, clean_file], capture_output=True, text=True)
            if result.returncode != 0 or result.stdout.strip() != "CLEAN":
                clean_modified.append(os.path.basename(clean_file))

        errors = []
        if evil_bypassed:
            errors.append(
                f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: "
                + ", ".join(evil_bypassed)
            )
        if clean_modified:
            errors.append(
                f"{len(clean_modified)} of {len(clean_files)} clean modified/rejected: "
                + ", ".join(clean_modified)
            )
        assert not errors, " | ".join(errors)


def test_randomized_content_not_path_classification():
    rng = secrets.SystemRandom()
    signatures = ["../", "..\\", ";", "|", "`", "$("]
    clean_examples = [
        "user=john&id=123",
        "file=reports/final.pdf",
        "search=apples and oranges",
        "version=1..2",
        "price=$5",
        "note=(ordinary text)",
        "literal=plus+sign&ok=yes",
    ]

    alphabet = string.ascii_letters + string.digits + "_=-+ /.,:&?()"
    while len(clean_examples) < 24:
        candidate = "".join(rng.choice(alphabet) for _ in range(rng.randint(12, 60)))
        if not oracle(candidate):
            clean_examples.append(candidate)

    evil_examples = []
    for signature in signatures:
        for _ in range(4):
            prefix = "".join(rng.choice(string.ascii_letters + string.digits) for _ in range(10))
            suffix = "".join(rng.choice(string.ascii_letters + string.digits + " /_") for _ in range(15))
            evil_examples.append(prefix + " " + signature + suffix)

    cases = clean_examples + evil_examples
    rng.shuffle(cases)

    # Every payload uses a random, neutral path in one common directory.
    with tempfile.TemporaryDirectory(prefix="payload_checks_") as temp_dir:
        for decoded in cases:
            expected_evil = oracle(decoded)
            encoded = encode_payload(decoded, bool(rng.randrange(2)))
            filename = "case_" + secrets.token_hex(12) + ".dat"
            path = os.path.join(temp_dir, filename)
            with open(path, "w", encoding="utf-8") as f:
                f.write(encoded)
            run_and_check(BINARY, path, expected_evil)
            run_and_check("/tmp/sanitizer_rebuilt", path, expected_evil)


def test_requires_exactly_one_argument():
    for binary in (BINARY, "/tmp/sanitizer_rebuilt"):
        no_arg = subprocess.run([binary], capture_output=True, text=True, timeout=5)
        two_args = subprocess.run(
            [binary, "/dev/null", "/dev/null"], capture_output=True, text=True, timeout=5
        )
        assert no_arg.returncode != 0, "Sanitizer accepted zero payload arguments"
        assert two_args.returncode != 0, "Sanitizer accepted multiple payload arguments"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
