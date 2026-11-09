#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import subprocess
import tempfile
import pytest

BINARY_PATH = "/home/user/detector"
WINDOW = 8
THRESHOLD = 12


def run_detector(filepath):
    try:
        return subprocess.run(
            [BINARY_PATH, filepath],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=10,
        ).returncode
    except subprocess.TimeoutExpired:
        pytest.fail(f"Detector timed out while processing {filepath}")


def test_detector_binary_exists():
    binary_path = BINARY_PATH
    assert os.path.isfile(binary_path), f"The detector binary is missing at {binary_path}."
    assert os.access(binary_path, os.X_OK), f"The detector binary at {binary_path} is not executable."


def test_clean_corpus():
    binary_path = BINARY_PATH
    clean_dir = "/app/corpora/clean"
    assert os.path.isdir(clean_dir), f"Clean corpus directory {clean_dir} is missing."

    files = [f for f in os.listdir(clean_dir) if os.path.isfile(os.path.join(clean_dir, f))]
    assert len(files) > 0, "No files found in clean corpus."

    failed_files = []
    for filename in files:
        filepath = os.path.join(clean_dir, filename)
        result = subprocess.run([binary_path, filepath], capture_output=True)
        if result.returncode != 0:
            failed_files.append((filename, result.returncode))

    if failed_files:
        error_msg = f"{len(failed_files)} of {len(files)} clean files failed (expected exit code 0). "
        error_msg += "Offending files: " + ", ".join([f[0] for f in failed_files])
        pytest.fail(error_msg)


def test_evil_corpus():
    binary_path = BINARY_PATH
    evil_dir = "/app/corpora/evil"
    assert os.path.isdir(evil_dir), f"Evil corpus directory {evil_dir} is missing."

    files = [f for f in os.listdir(evil_dir) if os.path.isfile(os.path.join(evil_dir, f))]
    assert len(files) > 0, "No files found in evil corpus."

    failed_files = []
    for filename in files:
        filepath = os.path.join(evil_dir, filename)
        result = subprocess.run([binary_path, filepath], capture_output=True)
        if result.returncode != 1:
            failed_files.append((filename, result.returncode))

    if failed_files:
        error_msg = f"{len(failed_files)} of {len(files)} evil files bypassed (expected exit code 1). "
        error_msg += "Offending files: " + ", ".join([f[0] for f in failed_files])
        pytest.fail(error_msg)


def oracle(events):
    by_ip = {}
    for timestamp, ip in events:
        by_ip.setdefault(ip, []).append(timestamp)

    for timestamps in by_ip.values():
        timestamps.sort()
        left = 0
        for right, timestamp in enumerate(timestamps):
            while timestamp - timestamps[left] > WINDOW:
                left += 1
            if right - left + 1 > THRESHOLD:
                return 1
    return 0


def test_generated_neutral_paths_and_window_semantics():
    rng = random.Random(secrets.randbits(128))
    base = rng.randint(100000, 900000)
    ip1 = f"172.{rng.randint(16, 30)}.{rng.randint(0, 255)}.{rng.randint(1, 254)}"
    ip2 = f"10.{rng.randint(1, 254)}.{rng.randint(0, 255)}.{rng.randint(1, 254)}"
    ip3 = f"192.168.{rng.randint(0, 255)}.{rng.randint(1, 254)}"

    cases = [
        [],
        [(base, ip1)] * 12,
        [(base, ip1)] * 13,
        [(base + i, ip1) for i in range(13)],
        [(base, ip1)] * 8 + [(base, ip2)] * 8,
        [(base + (i * 8 // 12), ip1) for i in range(13)],
        [(base + (i * 9 // 12), ip1) for i in range(13)],
        [(base + 40, ip2)] * 13 + [(base, ip1)] * 3,
    ]

    for case_index in range(30):
        events = []
        case_base = base + 1000 + case_index * 100
        ips = [ip1, ip2, ip3][:rng.randint(1, 3)]
        for ip in ips:
            for _ in range(rng.randint(0, 22)):
                events.append((case_base + rng.randint(0, 25), ip))
        cases.append(events)

    rng.shuffle(cases)
    with tempfile.TemporaryDirectory(prefix="detector-inputs-") as temp_dir:
        pending = []
        for events in cases:
            filename = secrets.token_hex(16) + ".dat"
            filepath = os.path.join(temp_dir, filename)
            ordered_events = sorted(events, key=lambda item: item[0])
            with open(filepath, "w", encoding="utf-8") as handle:
                handle.write("service startup completed\n")
                for timestamp, ip in ordered_events:
                    user = f"u{rng.randint(1000, 9999)}"
                    handle.write(
                        f"[{timestamp}] WARNING Failed authentication for user {user} from {ip}\n"
                    )
                handle.write(f"[{base}] INFO Routine health check from {ip3}\n")
                handle.write("unrelated application log message\n")
            pending.append((filepath, oracle(list(events))))

        rng.shuffle(pending)
        failures = []
        for filepath, expected in pending:
            actual = run_detector(filepath)
            if actual != expected:
                failures.append((os.path.basename(filepath), expected, actual))

        assert not failures, "Generated behavioral cases failed: " + "; ".join(
            f"{name}: expected {expected}, got {actual}"
            for name, expected, actual in failures
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
