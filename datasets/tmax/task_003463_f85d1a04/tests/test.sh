#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import sys
import stat
import subprocess
import tempfile
import uuid
import random
import pytest
import importlib.util


def test_pipeline_script():
    script_path = "/home/user/pipeline.sh"
    assert os.path.isfile(script_path), f"Missing script at {script_path}"

    st = os.stat(script_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"Script {script_path} is not executable"

    result = subprocess.run([script_path], capture_output=True, text=True)
    assert "Pipeline running" in result.stdout, f"Script output did not contain 'Pipeline running'. Output: {result.stdout}"


def test_cron_job():
    # The instruction requires the crontab belonging specifically to user.
    result = subprocess.run(["crontab", "-u", "user", "-l"], capture_output=True, text=True)
    assert result.returncode == 0, f"Failed to list crontab for user: {result.stderr}"
    lines = result.stdout.strip().split('\n')
    found = False
    for line in lines:
        if line.startswith('#'):
            continue
        if "/home/user/pipeline.sh" in line and line.startswith("* * * * *"):
            found = True
            break
    assert found, f"Cron job for /home/user/pipeline.sh running every minute not found in user crontab. Crontab: {result.stdout}"


def load_validator():
    validator_path = "/home/user/validator.py"
    assert os.path.isfile(validator_path), f"Missing validator module at {validator_path}"

    spec = importlib.util.spec_from_file_location("validator", validator_path)
    validator = importlib.util.module_from_spec(spec)
    sys.modules["validator"] = validator
    try:
        spec.loader.exec_module(validator)
    except Exception as e:
        pytest.fail(f"Failed to import {validator_path}: {e}")

    assert hasattr(validator, "process_and_validate"), f"Function process_and_validate not found in {validator_path}"
    assert callable(validator.process_and_validate), "process_and_validate is not callable"
    return validator.process_and_validate


def test_validator_corpus():
    process_and_validate = load_validator()

    evil_dir = "/app/corpora/evil"
    clean_dir = "/app/corpora/clean"

    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if os.path.isfile(os.path.join(evil_dir, f))]
    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if os.path.isfile(os.path.join(clean_dir, f))]

    evil_failures = []
    for f in evil_files:
        try:
            result = process_and_validate(f)
            if result is not False:
                evil_failures.append(os.path.basename(f))
        except Exception as e:
            evil_failures.append(f"{os.path.basename(f)} (crashed: {e})")

    clean_failures = []
    for f in clean_files:
        try:
            result = process_and_validate(f)
            if result is not True:
                clean_failures.append(os.path.basename(f))
        except Exception as e:
            clean_failures.append(f"{os.path.basename(f)} (crashed: {e})")

    error_msgs = []
    if evil_failures:
        error_msgs.append(f"{len(evil_failures)} of {len(evil_files)} evil bypassed: {', '.join(evil_failures)}")
    if clean_failures:
        error_msgs.append(f"{len(clean_failures)} of {len(clean_files)} clean modified/rejected: {', '.join(clean_failures)}")

    if error_msgs:
        pytest.fail(" | ".join(error_msgs))


def test_validator_generated_inputs():
    process_and_validate = load_validator()
    header = "timestamp,temperature,notes\n"

    cases = [
        # Ordinary valid input.
        (header +
         "2025-04-03T08:00:00Z,8.0,departed\n"
         "2025-04-03T08:01:00Z,8.2,all good\n"
         "2025-04-03T08:02:00Z,8.1,no issues\n"
         "2025-04-03T08:03:00Z,8.0,script is a word\n"
         "2025-04-03T08:04:00Z,8.1,arrived\n", True, "stable clean data"),

        # With WINDOW=5, the fifth value's deviation is 2.4, below MAX_DEV=2.5.
        (header +
         "2025-04-03T09:00:00Z,10.0,ok\n"
         "2025-04-03T09:01:00Z,10.0,ok\n"
         "2025-04-03T09:02:00Z,10.0,ok\n"
         "2025-04-03T09:03:00Z,10.0,ok\n"
         "2025-04-03T09:04:00Z,13.0,within limit\n", True, "deviation below threshold"),

        # With WINDOW=5, the fifth value's deviation is 2.56, above MAX_DEV=2.5.
        (header +
         "2025-04-03T10:00:00Z,10.0,ok\n"
         "2025-04-03T10:01:00Z,10.0,ok\n"
         "2025-04-03T10:02:00Z,10.0,ok\n"
         "2025-04-03T10:03:00Z,10.0,ok\n"
         "2025-04-03T10:04:00Z,13.2,outlier\n", False, "deviation above threshold"),

        # Resampling and forward filling create four baseline samples before the spike.
        (header +
         "2025-04-03T11:00:00Z,10.0,ok\n"
         "2025-04-03T11:04:00Z,10.0,after gap\n"
         "2025-04-03T11:05:00Z,15.0,spike\n", False, "resampled spike"),

        (header +
         "2025-04-03T12:00:00Z,7.0,<ScRiPt>alert(1)</ScRiPt>\n", False, "mixed-case script injection"),

        (header +
         "2025-04-03T13:00:00Z,7.0,open JAVASCRIPT:payload\n", False, "mixed-case javascript injection"),

        ("time,temp,memo\n2025-04-03T14:00:00Z,7.0,ok\n", False, "malformed headers"),
    ]

    failures = []
    with tempfile.TemporaryDirectory(prefix="validator-generated-") as root:
        generated = []
        for content, expected, description in cases:
            path = os.path.join(root, uuid.uuid4().hex + ".csv")
            with open(path, "w", encoding="utf-8", newline="") as f:
                f.write(content)
            generated.append((path, expected, description))

        invalid_encoding_path = os.path.join(root, uuid.uuid4().hex + ".csv")
        with open(invalid_encoding_path, "wb") as f:
            f.write(header.encode("utf-8"))
            f.write(b"2025-04-03T15:00:00Z,7.0,invalid-utf8-\xff\n")
        generated.append((invalid_encoding_path, False, "strict UTF-8 decoding"))

        # Randomized names and order prevent classification based on visible corpus paths.
        random.SystemRandom().shuffle(generated)
        for path, expected, description in generated:
            try:
                actual = process_and_validate(path)
            except Exception as e:
                failures.append(f"{description}: crashed with {e!r}")
                continue
            if actual is not expected:
                failures.append(f"{description}: expected {expected}, got {actual!r}")

    assert not failures, "Generated validation failures: " + " | ".join(failures)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
