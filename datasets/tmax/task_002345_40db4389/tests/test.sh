#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import secrets
import subprocess
import tempfile


def test_sanitiser_exists_and_executable():
    executable = "/home/user/sanitiser"
    assert os.path.isfile(executable), f"Sanitiser program not found at {executable}"
    assert os.access(executable, os.X_OK), f"Sanitiser program at {executable} is not executable"


def test_source_exists():
    source = "/home/user/sanitiser.c"
    assert os.path.isfile(source), f"C source not found at {source}"


def test_adversarial_corpus():
    executable = "/home/user/sanitiser"
    clean_dir = "/app/corpus/clean"
    evil_dir = "/app/corpus/evil"

    assert os.path.isdir(clean_dir), f"Clean corpus directory {clean_dir} is missing."
    assert os.path.isdir(evil_dir), f"Evil corpus directory {evil_dir} is missing."

    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if os.path.isfile(os.path.join(clean_dir, f))]
    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if os.path.isfile(os.path.join(evil_dir, f))]

    assert len(clean_files) > 0, "No files found in clean corpus."
    assert len(evil_files) > 0, "No files found in evil corpus."

    clean_failures = []
    for f in clean_files:
        result = subprocess.run([executable, f], capture_output=True)
        if result.returncode != 0:
            clean_failures.append(os.path.basename(f))

    evil_failures = []
    for f in evil_files:
        result = subprocess.run([executable, f], capture_output=True)
        if result.returncode == 0:
            evil_failures.append(os.path.basename(f))

    error_msgs = []
    if clean_failures:
        error_msgs.append(f"{len(clean_failures)} of {len(clean_files)} clean modified/rejected: {', '.join(clean_failures)}")
    if evil_failures:
        error_msgs.append(f"{len(evil_failures)} of {len(evil_files)} evil bypassed/accepted: {', '.join(evil_failures)}")

    assert not error_msgs, "\n".join(error_msgs)


def expected_status(values):
    for i, value in enumerate(values):
        window = values[max(0, i - 2):i + 1]
        average = sum(window) / len(window)
        if abs(value - average) > 5.0:
            return 1
    return 0


def test_generated_csvs_and_recompiled_source():
    rng = random.SystemRandom()

    with tempfile.TemporaryDirectory(prefix="sanitiser-check-") as tempdir:
        rebuilt = os.path.join(tempdir, "rebuilt-sanitiser")
        compilation = subprocess.run(
            ["gcc", "-std=c11", "-O2", "/home/user/sanitiser.c", "-o", rebuilt, "-lm"],
            capture_output=True,
            text=True,
        )
        assert compilation.returncode == 0, f"sanitiser.c did not compile:\n{compilation.stderr}"

        cases = [
            [12345.0],
            [0.0, 10.0],                 # Difference is exactly the threshold.
            [0.0, 10.0004],              # Difference is strictly over it.
            [0.0, 0.0, 7.5],             # Third-row difference is exactly 5.
            [0.0, 0.0, 7.5004],
            [-20.0, -10.0],
            [-20.0, -9.9996],
            [4.0, 7.0, 10.0, 13.0, 16.0, 19.0],
        ]

        # Produce unpredictable accepted sequences and rejected variants so a
        # submission cannot classify known paths or filenames.
        for _ in range(24):
            length = rng.randint(3, 16)
            values = [rng.uniform(-10000.0, 10000.0)]
            for _ in range(length - 1):
                values.append(values[-1] + rng.uniform(-3.25, 3.25))
            assert expected_status(values) == 0
            cases.append(values)

            rejected = list(values)
            rejected.append(rejected[-1] + rng.choice((-1.0, 1.0)) * rng.uniform(12.0, 30.0))
            assert expected_status(rejected) == 1
            cases.append(rejected)

        # Add arbitrary numeric logs; their answers are computed independently.
        for _ in range(20):
            cases.append([rng.uniform(-200.0, 200.0) for _ in range(rng.randint(1, 12))])

        rng.shuffle(cases)
        generated = []
        timestamp_base = secrets.randbelow(1000000000) + 1000000000
        for index, values in enumerate(cases):
            path = os.path.join(tempdir, f"{secrets.token_hex(12)}.csv")
            with open(path, "w", encoding="utf-8") as csv_file:
                for row, value in enumerate(values):
                    csv_file.write(f"{timestamp_base + index * 1000 + row * 60},{value:.12f}\n")
            generated.append((path, expected_status(values)))

        for executable in ("/home/user/sanitiser", rebuilt):
            for path, expected in generated:
                try:
                    result = subprocess.run([executable, path], capture_output=True, timeout=2)
                except subprocess.TimeoutExpired:
                    raise AssertionError(f"{executable} timed out on generated CSV {path}")
                assert result.returncode == expected, (
                    f"{executable} returned {result.returncode} for generated CSV "
                    f"{path}; expected {expected}"
                )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
