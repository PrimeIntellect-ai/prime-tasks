#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import string
import subprocess
import tempfile


def run_detector(detector_path, corpus_dir, direct=False):
    command = [detector_path, corpus_dir] if direct else ["python3", detector_path, corpus_dir]
    return subprocess.run(command, capture_output=True, text=True, timeout=15)


def output_lines(proc):
    return [line.strip() for line in proc.stdout.splitlines() if line.strip()]


def test_detector_exists_and_executable():
    detector_path = "/home/user/detector.py"
    assert os.path.isfile(detector_path), f"Detector script missing at {detector_path}"
    assert os.access(detector_path, os.X_OK), "Detector script must be executable."


def test_detector_against_corpora():
    detector_path = "/home/user/detector.py"
    evil_dir = "/app/corpora/evil"
    clean_dir = "/app/corpora/clean"

    assert os.path.isdir(evil_dir), f"Evil corpus directory missing at {evil_dir}"
    assert os.path.isdir(clean_dir), f"Clean corpus directory missing at {clean_dir}"

    evil_files = set(f for f in os.listdir(evil_dir) if os.path.isfile(os.path.join(evil_dir, f)))
    clean_files = set(f for f in os.listdir(clean_dir) if os.path.isfile(os.path.join(clean_dir, f)))

    assert len(evil_files) > 0, "Evil corpus is empty, cannot verify."
    assert len(clean_files) > 0, "Clean corpus is empty, cannot verify."

    evil_proc = run_detector(detector_path, evil_dir)
    assert evil_proc.returncode == 0, f"Detector script crashed on evil corpus: {evil_proc.stderr}"

    clean_proc = run_detector(detector_path, clean_dir)
    assert clean_proc.returncode == 0, f"Detector script crashed on clean corpus: {clean_proc.stderr}"

    evil_output_lines = set(output_lines(evil_proc))
    clean_output_lines = set(output_lines(clean_proc))

    bypassed_evil = evil_files - evil_output_lines
    flagged_clean = clean_output_lines.intersection(clean_files)
    unexpected_evil_output = evil_output_lines - evil_files
    unexpected_clean_output = clean_output_lines - clean_files

    errors = []
    if bypassed_evil:
        errors.append(f"{len(bypassed_evil)} of {len(evil_files)} evil bypassed: {', '.join(sorted(bypassed_evil))}")
    if flagged_clean:
        errors.append(f"{len(flagged_clean)} of {len(clean_files)} clean modified (flagged): {', '.join(sorted(flagged_clean))}")
    if unexpected_evil_output:
        errors.append(f"Unexpected output on evil corpus: {', '.join(sorted(unexpected_evil_output))}")
    if unexpected_clean_output:
        errors.append(f"Unexpected output on clean corpus: {', '.join(sorted(unexpected_clean_output))}")

    assert not errors, " | ".join(errors)


def test_detector_against_randomized_mixed_corpus():
    detector_path = "/home/user/detector.py"
    rng = random.Random(secrets.randbits(128))

    def token(min_len=5, max_len=12):
        return ''.join(rng.choice(string.ascii_letters) for _ in range(rng.randint(min_len, max_len)))

    malicious = []
    for _ in range(4):
        value = rng.randint(10, 99999)
        malicious.extend([
            f"<script>alert('{token()}')</script>",
            f"<img src=x onerror=alert({value})>",
            f"{token()}' OR '{value}'='{value}",
            f"{token()}' UNION SELECT {rng.randint(1, 9)},{rng.randint(10, 99)} --",
        ])

    benign = [
        f"{token()} {token()} {token()} {rng.randint(1000, 9999)}"
        for _ in range(len(malicious))
    ]

    entries = [(payload, True) for payload in malicious]
    entries.extend((payload, False) for payload in benign)
    rng.shuffle(entries)

    def encode(payload):
        return bytes(byte ^ 0x4B for byte in payload.encode("utf-8")).hex()

    with tempfile.TemporaryDirectory(prefix="corpus_") as corpus_dir:
        expected = set()
        for index, (payload, is_malicious) in enumerate(entries):
            filename = f"{token(10, 16)}_{index}_{secrets.token_hex(4)}.txt"
            with open(os.path.join(corpus_dir, filename), "w", encoding="utf-8") as handle:
                handle.write(encode(payload))
            if is_malicious:
                expected.add(filename)

        proc = run_detector(detector_path, corpus_dir, direct=True)
        assert proc.returncode == 0, f"Detector script crashed on randomized corpus: {proc.stderr}"

        lines = output_lines(proc)
        actual = set(lines)
        assert len(lines) == len(actual), "Detector printed one or more filenames multiple times"
        assert actual == expected, (
            f"Incorrect randomized-corpus output; missed={sorted(expected - actual)}, "
            f"unexpected={sorted(actual - expected)}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
