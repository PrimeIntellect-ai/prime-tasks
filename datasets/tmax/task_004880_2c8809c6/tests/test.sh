#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import secrets
import subprocess
import tempfile
import uuid
import pytest


def test_symlink_target():
    link_path = "/home/user/target_list"
    expected_target = "/home/user/mail/oncall-network-team"

    assert os.path.islink(link_path), f"Expected a symbolic link at {link_path}"
    actual_target = os.readlink(link_path)
    assert actual_target == expected_target, f"Symlink {link_path} points to {actual_target}, expected {expected_target}"
    assert os.path.isdir(expected_target), f"Expected destination directory to exist at {expected_target}"


def test_alert_filter_script_exists_and_executable():
    script_path = "/home/user/alert_filter.py"
    assert os.path.exists(script_path), f"Script missing at {script_path}"
    assert os.path.isfile(script_path), f"{script_path} is not a file"
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable"


def test_alert_filter_classification():
    script_path = "/home/user/alert_filter.py"
    evil_dir = "/app/corpus/evil/"
    clean_dir = "/app/corpus/clean/"

    assert os.path.exists(script_path), f"Script missing at {script_path}"

    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if os.path.isfile(os.path.join(evil_dir, f))]
    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if os.path.isfile(os.path.join(clean_dir, f))]

    evil_bypassed = []
    clean_rejected = []

    for filepath in evil_files:
        result = subprocess.run(["python3", script_path, filepath], capture_output=True, text=True)
        output = result.stdout.strip()
        if output != "REJECT":
            evil_bypassed.append((os.path.basename(filepath), output))

    for filepath in clean_files:
        result = subprocess.run(["python3", script_path, filepath], capture_output=True, text=True)
        output = result.stdout.strip()
        if output != "ACCEPT":
            clean_rejected.append((os.path.basename(filepath), output))

    error_messages = []
    if evil_bypassed:
        error_messages.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed. Offending files: " + ", ".join([f[0] for f in evil_bypassed[:5]]) + ("..." if len(evil_bypassed) > 5 else ""))
    if clean_rejected:
        error_messages.append(f"{len(clean_rejected)} of {len(clean_files)} clean rejected. Offending files: " + ", ".join([f[0] for f in clean_rejected[:5]]) + ("..." if len(clean_rejected) > 5 else ""))

    assert not evil_bypassed and not clean_rejected, " | ".join(error_messages)


def test_alert_filter_uses_file_contents_not_path():
    script_path = "/home/user/alert_filter.py"
    rng = secrets.SystemRandom()
    cases = ["ACCEPT"] * 6 + ["REJECT"] * 6
    rng.shuffle(cases)

    with tempfile.TemporaryDirectory(prefix="alert-filter-check-") as temp_dir:
        # Reuse one unpredictable path for both classes, so its directory and
        # filename cannot determine the expected answer.
        filepath = os.path.join(temp_dir, f"sample_{uuid.uuid4().hex}.txt")

        for expected in cases:
            token = uuid.uuid4().hex
            if expected == "ACCEPT":
                cpu = rng.randrange(1, 50)
                contents = (
                    f"[ALERT] CPU usage at {cpu}%\n"
                    f"[WARNING] Disk space low on /dev/sda1\n"
                )
            else:
                contents = (
                    f"Click here to claim your prize http://example.com/{token}\n"
                    "Crypto investment opportunity!\n"
                )

            with open(filepath, "w") as sample:
                sample.write(contents)

            result = subprocess.run(
                ["python3", script_path, filepath],
                capture_output=True,
                text=True,
            )
            assert result.stdout.strip() == expected, (
                f"Classifier returned {result.stdout.strip()!r} for dynamically "
                f"generated {expected} content at the same neutral path"
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
