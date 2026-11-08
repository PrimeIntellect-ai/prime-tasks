#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import collections
import os
import secrets
import signal
import subprocess
import sys
import tempfile

FILTER = '/home/user/filter.py'
INGEST = '/app/ingest.bin'


def run_filter(directory):
    return subprocess.run(
        [sys.executable, FILTER, directory],
        capture_output=True,
        text=True,
        timeout=20,
    )


def test_filter_script_exists():
    assert os.path.isfile(FILTER), "/home/user/filter.py does not exist."


def test_filter_on_evil_corpus():
    evil_dir = '/verifier/corpora/evil/'
    if not os.path.exists(evil_dir):
        return

    evil_files = {f for f in os.listdir(evil_dir) if f.endswith('.dat')}
    result = run_filter(evil_dir)

    assert result.returncode == 0, f"Script failed on evil corpus with error: {result.stderr}"
    output_lines = {line.strip() for line in result.stdout.splitlines() if line.strip()}

    bypassed = evil_files.intersection(output_lines)
    assert not bypassed, (
        f"{len(bypassed)} of {len(evil_files)} evil files bypassed. "
        f"Offending files: {', '.join(bypassed)}"
    )


def test_filter_on_clean_corpus():
    clean_dir = '/verifier/corpora/clean/'
    if not os.path.exists(clean_dir):
        return

    clean_files = {f for f in os.listdir(clean_dir) if f.endswith('.dat')}
    result = run_filter(clean_dir)

    assert result.returncode == 0, f"Script failed on clean corpus with error: {result.stderr}"
    output_lines = {line.strip() for line in result.stdout.splitlines() if line.strip()}

    missing = clean_files - output_lines
    assert not missing, (
        f"{len(missing)} of {len(clean_files)} clean files modified/rejected. "
        f"Offending files: {', '.join(missing)}"
    )


def test_filter_on_dynamic_mixed_corpus():
    rng = secrets.SystemRandom()

    with tempfile.TemporaryDirectory(prefix='telemetry_case_') as corpus:
        payloads = []

        # Boundary cases, malformed/short records, and varied trailing data.
        payloads.extend(os.urandom(n) for n in range(5))
        payloads.extend([
            b'IO\x03\xff\x00' + os.urandom(3),
            b'IO\x03\x00\x01' + os.urandom(7),
            b'IO\x03\x01\x01',
            b'IO\x03\xff\xff' + os.urandom(1),
            b'IO\x03\xfe\x00' + os.urandom(4),
            b'IO\x01\x00\x01' + os.urandom(5),
            b'IO\x02\xff\xff',
            b'IX\x03\x00\x01',
            b'NO\x03\xff\xff' + os.urandom(2),
        ])

        # Random heterogeneous records prevent classification by fixed bytes.
        for _ in range(80):
            payloads.append(os.urandom(rng.randrange(0, 33)))

        # Additional randomized headers, including both sides of boundaries.
        for _ in range(40):
            magic = rng.choice([b'IO', os.urandom(2)])
            sensor = rng.randrange(0, 256)
            length = rng.choice([0, 1, 254, 255, 256, 257, 511, 65535, rng.randrange(65536)])
            payloads.append(magic + bytes([sensor, length & 0xff, length >> 8]) + os.urandom(rng.randrange(0, 12)))

        rng.shuffle(payloads)
        dat_paths = []
        for payload in payloads:
            name = f"packet_{secrets.token_hex(8)}.dat"
            path = os.path.join(corpus, name)
            with open(path, 'wb') as f:
                f.write(payload)
            dat_paths.append((name, path))

        # Files without the required suffix must not be reported.
        for suffix in ('.txt', '.bin', '.DAT'):
            with open(os.path.join(corpus, f"decoy_{secrets.token_hex(5)}{suffix}"), 'wb') as f:
                f.write(os.urandom(12))

        expected = []
        saw_crash = False
        saw_clean = False
        for name, path in dat_paths:
            probe = subprocess.run([INGEST, path], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=5)
            if probe.returncode == -signal.SIGSEGV:
                saw_crash = True
            else:
                assert probe.returncode == 0, f"ingest.bin returned unexpected status {probe.returncode} for {name}"
                saw_clean = True
                expected.append(name)

        assert saw_crash and saw_clean, "Dynamic corpus must contain both crashing and clean files"

        result = run_filter(corpus)
        assert result.returncode == 0, f"Script failed on mixed corpus with error: {result.stderr}"

        actual = [line.strip() for line in result.stdout.splitlines() if line.strip()]
        assert collections.Counter(actual) == collections.Counter(expected), (
            "Output must contain each and only each safe .dat basename exactly once. "
            f"Missing: {sorted(collections.Counter(expected) - collections.Counter(actual))}; "
            f"Unexpected/duplicate: {sorted(collections.Counter(actual) - collections.Counter(expected))}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
