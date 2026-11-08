#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import filecmp
import os
import random
import secrets
import subprocess
import tempfile


def run_checker(binary, filepath):
    return subprocess.run(
        [binary, filepath],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        timeout=3,
    ).returncode


def test_fast_checker_exists_and_executable():
    path = "/home/user/fast_checker"
    assert os.path.exists(path), f"Missing compiled binary: {path}"
    assert os.path.isfile(path), f"{path} is not a file"
    assert os.access(path, os.X_OK), f"{path} is not executable"
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{path} is not a compiled ELF executable"
    assert not filecmp.cmp(path, "/app/legacy_checker", shallow=False), \
        "Replacement must not be a byte-identical copy of the legacy checker"


def test_unseen_inputs_match_legacy_checker():
    candidate = "/home/user/fast_checker"
    oracle = "/app/legacy_checker"
    rng = random.SystemRandom()
    alphabet = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_=- "

    def chunk():
        return bytes(rng.choice(alphabet) for _ in range(rng.randrange(0, 40)))

    cases = []

    # Randomized valid manifests with exactly five newlines.
    for _ in range(45):
        cases.append(b"BILD\n" + b"\n".join(chunk() for _ in range(5)))

    # Correct shape but with the forbidden marker at unpredictable positions.
    for _ in range(45):
        fields = [chunk() for _ in range(5)]
        pos = rng.randrange(5)
        offset = rng.randrange(len(fields[pos]) + 1)
        fields[pos] = fields[pos][:offset] + b"DEBUG=1" + fields[pos][offset:]
        cases.append(b"BILD\n" + b"\n".join(fields))

    # Correct prefix but wrong newline counts.
    for _ in range(35):
        count = rng.choice([0, 1, 2, 3, 4, 6, 7, 8, 12])
        cases.append(b"BILD\n" + b"\n".join(chunk() for _ in range(count)))

    # Wrong prefixes while retaining five newlines.
    for _ in range(35):
        prefix = secrets.token_bytes(rng.randrange(0, 8))
        if prefix.startswith(b"BILD\n"):
            prefix = b"X" + prefix
        cases.append(prefix + b"\n".join(chunk() for _ in range(6)))

    # Arbitrary binary data and edge cases, including embedded NUL bytes.
    cases.extend([
        b"",
        b"BILD",
        b"BILD\n",
        b"BILD\n\n\n\n\n",
        b"BILD\nA\nB\nC\nD\n",
        b"BILD\nA\x00DEBUG=1\nB\nC\nD\n",
        b"BILD\nA\nB\nC\nDEBUG=1\n",
        b"BILD\r\nA\nB\nC\nD\n",
    ])
    for _ in range(40):
        cases.append(secrets.token_bytes(rng.randrange(0, 257)))

    rng.shuffle(cases)

    with tempfile.TemporaryDirectory(prefix="manifest_probe_") as directory:
        paths = []
        for data in cases:
            path = os.path.join(directory, secrets.token_hex(12))
            with open(path, "wb") as f:
                f.write(data)
            paths.append(path)

        # Derive every expected result before executing the submission.
        expected = [run_checker(oracle, path) for path in paths]
        actual = [run_checker(candidate, path) for path in paths]

        mismatches = [
            (i, want, got) for i, (want, got) in enumerate(zip(expected, actual))
            if want != got
        ]
        assert not mismatches, \
            f"Replacement disagreed with legacy checker on unseen inputs: {mismatches[:10]}"


def test_clean_corpus_accepted():
    binary_path = "/home/user/fast_checker"
    corpus_dir = "/app/corpora/clean"

    assert os.path.isdir(corpus_dir), f"Missing clean corpus directory: {corpus_dir}"

    failed_files = []
    total_files = 0

    for filename in os.listdir(corpus_dir):
        filepath = os.path.join(corpus_dir, filename)
        if os.path.isfile(filepath):
            total_files += 1
            result = subprocess.run([binary_path, filepath], capture_output=True)
            if result.returncode != 0:
                failed_files.append(filename)

    assert total_files > 0, "No files found in clean corpus"
    assert len(failed_files) == 0, f"{len(failed_files)} of {total_files} clean files were rejected (expected exit 0). Offending files: {', '.join(failed_files[:10])}"


def test_evil_corpus_rejected():
    binary_path = "/home/user/fast_checker"
    corpus_dir = "/app/corpora/evil"

    assert os.path.isdir(corpus_dir), f"Missing evil corpus directory: {corpus_dir}"

    failed_files = []
    total_files = 0

    for filename in os.listdir(corpus_dir):
        filepath = os.path.join(corpus_dir, filename)
        if os.path.isfile(filepath):
            total_files += 1
            result = subprocess.run([binary_path, filepath], capture_output=True)
            if result.returncode == 0:
                failed_files.append(filename)

    assert total_files > 0, "No files found in evil corpus"
    assert len(failed_files) == 0, f"{len(failed_files)} of {total_files} evil files bypassed the checker (expected non-zero exit). Offending files: {', '.join(failed_files[:10])}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
