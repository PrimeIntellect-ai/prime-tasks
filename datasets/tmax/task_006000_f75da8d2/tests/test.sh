#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import shutil
import subprocess
import tempfile
import uuid

SCRIPT = "/home/user/pipeline.sh"
SOURCE = "/home/user/src/mailer_daemon.c"
CURRENT = "/home/user/deploy/current"
RELEASES = "/home/user/deploy/releases"
ALERT = "/home/user/alerts/deploy_email.txt"


def run_pipeline():
    return subprocess.run([SCRIPT], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                          timeout=30)


def file_hash(path):
    with open(path, "rb") as f:
        return hashlib.sha256(f.read()).hexdigest()


def release_snapshot():
    result = {}
    for name in sorted(os.listdir(RELEASES)):
        path = os.path.join(RELEASES, name)
        if os.path.isfile(path):
            result[name] = file_hash(path)
        else:
            result[name] = None
    return result


def validate_deployment():
    assert os.path.islink(CURRENT), f"{CURRENT} is not a symlink."
    target = os.path.realpath(CURRENT)
    assert os.path.isfile(target), f"Symlink target {target} does not exist or is not a file."
    assert os.access(target, os.X_OK), f"Symlink target {target} is not executable."
    assert os.path.commonpath([target, RELEASES]) == RELEASES, \
        f"Symlink target {target} is not inside {RELEASES}/"

    with open(target, "rb") as f:
        data = f.read()
    assert data.startswith(b"\x7fELF"), "Deployed artifact is not an ELF binary."
    size = len(data)
    digest = hashlib.sha256(data).hexdigest()
    assert size <= 100000, f"Deployed binary is {size} bytes, exceeding the quota."
    assert os.path.basename(target) == f"mailer_daemon_{digest}"

    assert os.path.isfile(ALERT), f"Alert file {ALERT} does not exist."
    with open(ALERT, "r") as f:
        lines = f.read().splitlines()
    assert lines == [
        "To: devops@company.local",
        "Subject: Deployment successful",
        f"Binary-Size: {size}",
        f"Checksum: {digest}",
    ], f"Alert contents are incorrect: {lines!r}"
    return target, data


def test_pipeline_execution_source_quota_and_idempotence():
    assert os.path.isfile(SCRIPT), f"Deployment script {SCRIPT} does not exist."
    assert os.access(SCRIPT, os.X_OK), f"Deployment script {SCRIPT} is not executable."

    with open(SOURCE, "rb") as f:
        original_source = f.read()

    shutil.rmtree("/home/user/deploy", ignore_errors=True)
    shutil.rmtree("/home/user/alerts", ignore_errors=True)

    try:
        first = run_pipeline()
        assert first.returncode == 0, first.stderr.decode(errors="replace")
        first_target, first_data = validate_deployment()

        with tempfile.TemporaryDirectory() as td:
            reference = os.path.join(td, "reference")
            compiled = subprocess.run(["gcc", SOURCE, "-o", reference],
                                      stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            assert compiled.returncode == 0, compiled.stderr.decode(errors="replace")
            expected_run = subprocess.run([reference], stdout=subprocess.PIPE,
                                          stderr=subprocess.PIPE, timeout=10)
        deployed_run = subprocess.run([first_target], stdout=subprocess.PIPE,
                                      stderr=subprocess.PIPE, timeout=10)
        assert deployed_run.returncode == expected_run.returncode
        assert deployed_run.stdout == expected_run.stdout
        assert deployed_run.stderr == expected_run.stderr

        first_alert = open(ALERT, "rb").read()
        second = run_pipeline()
        assert second.returncode == 0, second.stderr.decode(errors="replace")
        second_target, second_data = validate_deployment()
        assert second_target == first_target
        assert second_data == first_data
        assert open(ALERT, "rb").read() == first_alert

        quota_source = b'''#include <stdio.h>\nvolatile unsigned char quota_probe[110000] = {1};\nint main(void) { puts("quota probe"); return quota_probe[0] == 1 ? 0 : 2; }\n'''
        with open(SOURCE, "wb") as f:
            f.write(quota_source)
        with tempfile.TemporaryDirectory() as td:
            oversized = os.path.join(td, "oversized")
            check = subprocess.run(["gcc", SOURCE, "-o", oversized],
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            assert check.returncode == 0, check.stderr.decode(errors="replace")
            assert os.path.getsize(oversized) > 100000, "Quota test binary was not oversized."

        old_link = os.readlink(CURRENT)
        old_alert = open(ALERT, "rb").read()
        old_releases = release_snapshot()
        quota_run = run_pipeline()
        assert quota_run.returncode == 1, \
            f"Oversized build returned {quota_run.returncode}, expected 1."
        assert os.path.islink(CURRENT) and os.readlink(CURRENT) == old_link, \
            "Pipeline changed the current deployment after exceeding quota."
        assert open(ALERT, "rb").read() == old_alert, \
            "Pipeline changed the alert after exceeding quota."
        assert release_snapshot() == old_releases, \
            "Pipeline changed releases after exceeding quota."

        marker = "source_probe_" + uuid.uuid4().hex
        probe_source = (f'#include <stdio.h>\nint main(void) {{ puts("{marker}"); return 0; }}\n').encode()
        with open(SOURCE, "wb") as f:
            f.write(probe_source)
        probe_run = run_pipeline()
        assert probe_run.returncode == 0, probe_run.stderr.decode(errors="replace")
        probe_target, _ = validate_deployment()
        executed = subprocess.run([probe_target], stdout=subprocess.PIPE,
                                  stderr=subprocess.PIPE, timeout=10)
        assert executed.returncode == 0
        assert executed.stdout == (marker + "\n").encode(), \
            "Deployed binary was not built from the current C source."
    finally:
        with open(SOURCE, "wb") as f:
            f.write(original_source)

    final_run = run_pipeline()
    assert final_run.returncode == 0, final_run.stderr.decode(errors="replace")
    validate_deployment()


def test_pipeline_script_executable():
    script_path = "/home/user/pipeline.sh"
    assert os.path.isfile(script_path), f"Deployment script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Deployment script {script_path} is not executable."


def test_symlink_and_binary():
    symlink_path = "/home/user/deploy/current"
    assert os.path.islink(symlink_path), f"{symlink_path} is not a symlink."

    target_path = os.path.realpath(symlink_path)
    assert os.path.isfile(target_path), f"Symlink target {target_path} does not exist or is not a file."
    assert os.access(target_path, os.X_OK), f"Symlink target {target_path} is not executable."

    assert target_path.startswith("/home/user/deploy/releases/"), \
        f"Symlink target {target_path} is not inside /home/user/deploy/releases/"

    with open(target_path, "rb") as f:
        data = f.read()

    binary_size = len(data)
    binary_hash = hashlib.sha256(data).hexdigest()

    expected_filename = f"mailer_daemon_{binary_hash}"
    assert os.path.basename(target_path) == expected_filename, \
        f"Binary filename {os.path.basename(target_path)} does not match expected {expected_filename}."


def test_alert_email_file():
    symlink_path = "/home/user/deploy/current"
    assert os.path.exists(symlink_path), "Symlink does not exist, cannot verify email contents."
    target_path = os.path.realpath(symlink_path)

    with open(target_path, "rb") as f:
        data = f.read()
    binary_size = len(data)
    binary_hash = hashlib.sha256(data).hexdigest()

    email_path = "/home/user/alerts/deploy_email.txt"
    assert os.path.isfile(email_path), f"Alert file {email_path} does not exist."

    with open(email_path, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    expected_lines = [
        "To: devops@company.local",
        "Subject: Deployment successful",
        f"Binary-Size: {binary_size}",
        f"Checksum: {binary_hash}"
    ]

    for expected_line in expected_lines:
        assert expected_line in lines, f"Expected line '{expected_line}' not found in {email_path}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
