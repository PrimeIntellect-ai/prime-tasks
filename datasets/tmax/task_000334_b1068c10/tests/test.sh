#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import secrets
import stat
import subprocess
import sys
import tempfile
from pathlib import Path

import pytest

SCRIPT_PATH = "/home/user/sanitiser.py"
EVIL_DIR = "/app/evil_configs"
CLEAN_DIR = "/app/clean_configs"


def run_sanitiser(target_dir):
    """Run the submitted script and parse its JSON output."""
    assert os.path.isfile(SCRIPT_PATH), f"Sanitiser script not found at {SCRIPT_PATH}"

    try:
        result = subprocess.run(
            [sys.executable, SCRIPT_PATH, target_dir],
            capture_output=True,
            text=True,
            timeout=20,
        )
    except subprocess.TimeoutExpired:
        pytest.fail(f"Script timed out on {target_dir}")

    assert result.returncode == 0, (
        f"Script failed on {target_dir} with return code {result.returncode}.\n"
        f"Stderr: {result.stderr}"
    )

    try:
        output_json = json.loads(result.stdout)
    except json.JSONDecodeError:
        pytest.fail(f"Script output is not valid JSON. Stdout: {result.stdout}")

    assert isinstance(output_json, dict), "Script output must be a JSON dictionary"
    return output_json


def test_evil_corpus_rejected():
    """Verify that all files in the original evil corpus are REJECTED."""
    assert os.path.isdir(EVIL_DIR), f"Evil corpus directory missing: {EVIL_DIR}"

    output = run_sanitiser(EVIL_DIR)
    evil_files = [f for f in os.listdir(EVIL_DIR) if f.endswith('.conf')]
    assert len(evil_files) > 0, f"No .conf files found in {EVIL_DIR}"

    bypassed = []
    for filename in evil_files:
        status = output.get(filename)
        if status != "REJECTED":
            bypassed.append(f"{filename} (status: {status})")

    if bypassed:
        pytest.fail(
            f"{len(bypassed)} of {len(evil_files)} evil configs bypassed rejection:\n"
            + "\n".join(bypassed)
        )


def test_clean_corpus_accepted():
    """Verify that all files in the original clean corpus are ACCEPTED."""
    assert os.path.isdir(CLEAN_DIR), f"Clean corpus directory missing: {CLEAN_DIR}"

    output = run_sanitiser(CLEAN_DIR)
    clean_files = [f for f in os.listdir(CLEAN_DIR) if f.endswith('.conf')]
    assert len(clean_files) > 0, f"No .conf files found in {CLEAN_DIR}"

    rejected = []
    for filename in clean_files:
        status = output.get(filename)
        if status != "ACCEPTED":
            rejected.append(f"{filename} (status: {status})")

    if rejected:
        pytest.fail(
            f"{len(rejected)} of {len(clean_files)} clean configs were incorrectly rejected:\n"
            + "\n".join(rejected)
        )


def test_randomised_mixed_corpus_and_preservation():
    """Exercise content and metadata checks in one unpredictably named directory."""
    root = Path(tempfile.mkdtemp(prefix=f"cfg-{secrets.token_hex(8)}-"))

    cases = [
        ("ACCEPTED", b"log_path=/var/log/service.log\nconfig_dir=/etc/app/conf.d\nenabled=true\n", False),
        ("ACCEPTED", b"primary=/etc/app/main.conf\nsecondary=/var/log/service.log.1\ncount=7\n", False),
        ("ACCEPTED", b"config_dir=/etc/app/profiles/default\nlog_path=/var/log/nested/app.log\n", False),
        ("ACCEPTED", b"log_path=/var/log/app.log\nconfig_dir=/etc/app/\nmode=rotate\n", False),
        ("REJECTED", b"log_path=/var/log/app.log > /etc/app/captured\n", False),
        ("REJECTED", b"log_path=/var/log/app.log\ncommand=< /etc/app/input\n", False),
        ("REJECTED", b"log_path=/var/log/app.log | helper\n", False),
        ("REJECTED", b"log_path=/var/log/app.log &> /etc/app/error.log\n", False),
        ("REJECTED", b"log_path=/tmp/stolen.log\nconfig_dir=/etc/app/conf.d\n", False),
        ("REJECTED", b"log_path=/var/log/app.log\nconfig_dir=/home/user/private\n", False),
        ("REJECTED", b"log_path=/var/log/executable.log\nconfig_dir=/etc/app/conf.d\n", True),
        ("REJECTED", b"X" * (1024 * 1024 + 1) + b"\nlog_path=/var/log/large.log\n", False),
    ]
    random.SystemRandom().shuffle(cases)

    expected = {}
    accepted_snapshots = {}
    for expected_status, content, executable in cases:
        filename = f"{secrets.token_hex(12)}.conf"
        path = root / filename
        path.write_bytes(content)
        os.chmod(path, 0o744 if executable else 0o640)
        expected[filename] = expected_status
        if expected_status == "ACCEPTED":
            st = path.stat()
            accepted_snapshots[filename] = (
                path.read_bytes(),
                stat.S_IMODE(st.st_mode),
                st.st_mtime_ns,
            )

    # A non-config file must not be reported as a processed configuration.
    (root / f"{secrets.token_hex(8)}.txt").write_text(
        "log_path=/tmp/not-a-config\n", encoding="utf-8"
    )

    output = run_sanitiser(str(root))
    assert set(output) == set(expected), (
        "Output keys must be exactly the .conf filenames in the supplied directory"
    )
    assert output == expected, "Randomised mixed corpus was classified incorrectly"

    for filename, (original_bytes, original_mode, original_mtime) in accepted_snapshots.items():
        path = root / filename
        assert path.is_file(), f"Accepted file was removed: {filename}"
        st = path.stat()
        assert path.read_bytes() == original_bytes, f"Accepted file content changed: {filename}"
        assert stat.S_IMODE(st.st_mode) == original_mode, f"Accepted file mode changed: {filename}"
        assert st.st_mtime_ns == original_mtime, f"Accepted file timestamp changed: {filename}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
