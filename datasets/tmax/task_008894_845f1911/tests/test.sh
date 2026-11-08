#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import secrets
import shutil
import subprocess

PROJECT = "/home/user/repro_check"
MANIFEST = os.path.join(PROJECT, "Cargo.toml")
RUN1 = "/home/user/run1.txt"
RUN2 = "/home/user/run2.txt"
LOG = "/home/user/validation_log.txt"
TARGET = "/tmp/verifier-cargo-target"
BINARY = os.path.join(TARGET, "debug", "repro_check")


def expected_line(run1_path=RUN1, run2_path=RUN2):
    with open(run1_path, "r") as f1:
        lines1 = [float(x) for x in f1.read().splitlines() if x.strip()]
    with open(run2_path, "r") as f2:
        lines2 = [float(x) for x in f2.read().splitlines() if x.strip()]

    n = len(lines1)
    assert n > 1, "Not enough lines to compute standard deviation."
    diffs = [l1 - l2 for l1, l2 in zip(lines1, lines2)]
    mean_diff = sum(diffs) / n
    variance = sum((d - mean_diff) ** 2 for d in diffs) / (n - 1)
    std_dev = math.sqrt(variance)
    margin_error = 1.96 * (std_dev / math.sqrt(n))
    ci_lower = mean_diff - margin_error
    ci_upper = mean_diff + margin_error
    return f"MEAN_DIFF: {mean_diff:.4f}, CI_LOWER: {ci_lower:.4f}, CI_UPPER: {ci_upper:.4f}"


def test_rust_project_exists():
    assert os.path.exists(MANIFEST), f"Rust Cargo project not found at {MANIFEST}. Did you create the project?"


def test_validation_log_exists():
    assert os.path.exists(LOG), f"Validation log not found at {LOG}."


def test_validation_log_content():
    expected = expected_line()
    with open(LOG, "r") as f:
        log_content = f.read()

    assert expected in log_content, (
        f"Expected to find the exact string:\n'{expected}'\n"
        f"in {LOG}, but it was not found. Current content:\n{log_content}"
    )
    assert log_content in (expected, expected + "\n"), (
        f"{LOG} must contain exactly one output line; current content was:\n{log_content}"
    )


def test_build_and_execute_rust_program_on_dynamic_inputs():
    shutil.rmtree(TARGET, ignore_errors=True)
    env = os.environ.copy()
    env["CARGO_TARGET_DIR"] = TARGET

    subprocess.run(
        ["cargo", "build", "--quiet", "--manifest-path", MANIFEST, "--bin", "repro_check"],
        cwd=PROJECT,
        env=env,
        check=True,
        timeout=120,
    )
    assert os.path.isfile(BINARY) and os.access(BINARY, os.X_OK), (
        "Cargo did not produce an executable repro_check binary."
    )

    original_run1 = open(RUN1, "rb").read()
    original_run2 = open(RUN2, "rb").read()
    original_log = open(LOG, "rb").read() if os.path.exists(LOG) else None

    try:
        for case in range(3):
            values1 = []
            values2 = []
            shift = (case - 1) * 400
            for _ in range(100):
                base = secrets.randbelow(20001) - 10000
                delta = shift + secrets.randbelow(601) - 300
                run2_value = base / 29.0
                run1_value = run2_value + delta / 137.0
                values1.append(run1_value)
                values2.append(run2_value)

            with open(RUN1, "w") as f1:
                f1.writelines(f"{value:.17g}\n" for value in values1)
            with open(RUN2, "w") as f2:
                f2.writelines(f"{value:.17g}\n" for value in values2)
            if os.path.exists(LOG):
                os.remove(LOG)

            expected = expected_line()
            subprocess.run(
                [BINARY],
                cwd=PROJECT,
                check=True,
                timeout=10,
            )

            assert os.path.exists(LOG), "The executed Rust program did not create validation_log.txt."
            with open(LOG, "r") as f:
                actual = f.read()
            assert actual in (expected, expected + "\n"), (
                "The executed Rust program must append exactly one correctly calculated line.\n"
                f"Expected: {expected!r}\nActual: {actual!r}"
            )
    finally:
        with open(RUN1, "wb") as f1:
            f1.write(original_run1)
        with open(RUN2, "wb") as f2:
            f2.write(original_run2)
        if original_log is None:
            if os.path.exists(LOG):
                os.remove(LOG)
        else:
            with open(LOG, "wb") as log_file:
                log_file.write(original_log)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
