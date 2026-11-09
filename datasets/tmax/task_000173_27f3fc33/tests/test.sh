#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import secrets
import shutil
import subprocess
import tempfile
import pytest

SOURCE_DIR = "/app/vmm-deploy-0.5.0"
BINARY_PATH = "/home/user/.local/bin/vmm-deploy"
VALIDATOR_PATH = "/home/user/validator.py"


def run_checked(command, **kwargs):
    try:
        return subprocess.run(command, timeout=10, **kwargs)
    except subprocess.TimeoutExpired:
        pytest.fail(f"Command timed out: {command}")


def test_vmm_deploy_installed_and_working():
    # Ensure the submitted Makefile/package configuration performs the install;
    # a binary placed directly at the destination must not satisfy this test.
    if os.path.lexists(BINARY_PATH):
        if os.path.isdir(BINARY_PATH) and not os.path.islink(BINARY_PATH):
            shutil.rmtree(BINARY_PATH)
        else:
            os.unlink(BINARY_PATH)

    env = os.environ.copy()
    env["HOME"] = "/home/user"
    install = run_checked(
        ["make", "-C", SOURCE_DIR, "install"],
        capture_output=True,
        text=True,
        env=env,
    )
    assert install.returncode == 0, (
        f"make install failed with exit code {install.returncode}. "
        f"Stdout: {install.stdout} Stderr: {install.stderr}"
    )

    assert os.path.isfile(BINARY_PATH), f"The binary {BINARY_PATH} was not installed."
    assert os.access(BINARY_PATH, os.X_OK), f"The binary {BINARY_PATH} is not executable."

    result = run_checked([BINARY_PATH, "--version"], capture_output=True, text=True)
    assert result.returncode == 0, f"vmm-deploy failed with exit code {result.returncode}. Stderr: {result.stderr}"
    assert "vmm-deploy 0.5.0" in result.stdout, f"vmm-deploy output did not contain 'vmm-deploy 0.5.0'. Output: {result.stdout}"


def test_validator_adversarial_corpus():
    assert os.path.isfile(VALIDATOR_PATH), f"Validator script {VALIDATOR_PATH} does not exist."

    evil_dir = "/tests/corpus/evil"
    clean_dir = "/tests/corpus/clean"

    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if f.endswith(".json")]
    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if f.endswith(".json")]

    assert len(evil_files) > 0, "No evil corpus files found."
    assert len(clean_files) > 0, "No clean corpus files found."

    evil_bypassed = []
    for evil_file in evil_files:
        result = run_checked(["python3", VALIDATOR_PATH, evil_file], capture_output=True, text=True)
        if result.returncode != 1 or result.stdout.strip() != "EVIL":
            evil_bypassed.append(os.path.basename(evil_file))

    clean_modified = []
    for clean_file in clean_files:
        result = run_checked(["python3", VALIDATOR_PATH, clean_file], capture_output=True, text=True)
        if result.returncode != 0 or result.stdout.strip() != "CLEAN":
            clean_modified.append(os.path.basename(clean_file))

    error_messages = []
    if evil_bypassed:
        error_messages.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_modified:
        error_messages.append(f"{len(clean_modified)} of {len(clean_files)} clean modified/rejected: {', '.join(clean_modified)}")

    if error_messages:
        pytest.fail(" | ".join(error_messages))


def expected_classification(config):
    forbidden = ("/etc", "/var", "/root", "/sys")
    allowed_root = os.path.normpath("/home/user/app_data")

    for mount in config["mounts"]:
        if mount["source"].startswith(forbidden):
            return "EVIL", 1
        normalized_target = os.path.normpath(mount["target"])
        try:
            if os.path.commonpath([allowed_root, normalized_target]) != allowed_root:
                return "EVIL", 1
        except ValueError:
            return "EVIL", 1

    if len(config["cron"].split()) != 5:
        return "EVIL", 1
    return "CLEAN", 0


def test_validator_generated_cases():
    assert os.path.isfile(VALIDATOR_PATH), f"Validator script {VALIDATOR_PATH} does not exist."

    token = secrets.token_hex(10)
    good_source = f"/mnt/{token}"
    good_target = f"/home/user/app_data/{token}"
    good_cron = f"{len(token)} 3 * * 2"

    configs = [
        {"mounts": [], "cron": good_cron},
        {"mounts": [{"source": good_source, "target": good_target}], "cron": good_cron},
        {"mounts": [
            {"source": f"/opt/{token}", "target": f"{good_target}/nested/data"},
            {"source": f"relative-{token}", "target": f"/home/user/app_data/other-{token}"},
        ], "cron": "alpha beta gamma delta epsilon"},
        {"mounts": [{"source": f"/etc/{token}", "target": good_target}], "cron": good_cron},
        {"mounts": [{"source": f"/var/lib/{token}", "target": good_target}], "cron": good_cron},
        {"mounts": [{"source": f"/root/{token}", "target": good_target}], "cron": good_cron},
        {"mounts": [{"source": f"/sys/class/{token}", "target": good_target}], "cron": good_cron},
        {"mounts": [{"source": good_source, "target": f"/home/user/app_data/{token}/../../outside-{token}"}], "cron": good_cron},
        {"mounts": [{"source": good_source, "target": f"/home/user/app_data_{token}/file"}], "cron": good_cron},
        {"mounts": [{"source": good_source, "target": f"/tmp/{token}"}], "cron": good_cron},
        {"mounts": [{"source": good_source, "target": good_target}], "cron": "0 1 * *"},
        {"mounts": [{"source": good_source, "target": good_target}], "cron": "0 1 * * * extra"},
    ]
    random.SystemRandom().shuffle(configs)

    with tempfile.TemporaryDirectory(prefix=f"validator-{token}-") as temp_dir:
        failures = []
        for config in configs:
            expected_stdout, expected_code = expected_classification(config)
            path = os.path.join(temp_dir, secrets.token_hex(12) + ".json")
            with open(path, "w", encoding="utf-8") as handle:
                json.dump(config, handle)

            result = run_checked(["python3", VALIDATOR_PATH, path], capture_output=True, text=True)
            if result.returncode != expected_code or result.stdout.strip() != expected_stdout:
                failures.append(
                    f"config={config!r}, expected=({expected_code}, {expected_stdout}), "
                    f"actual=({result.returncode}, {result.stdout!r})"
                )

        if failures:
            pytest.fail("Generated validator cases failed:\n" + "\n".join(failures))
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
