#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import secrets
import shutil
import subprocess
import tempfile
import pytest

VALIDATOR_SCRIPT = "/home/user/validate_config.py"
CLEAN_DIR = "/app/clean"
EVIL_DIR = "/app/evil"
GIT_DIR = "/home/user/provisioning.git"
HOOK_PATH = os.path.join(GIT_DIR, "hooks/pre-receive")
BLOCKED_PREFIX = "198.51.100."


def run_validator(path):
    return subprocess.run(
        ["python3", VALIDATOR_SCRIPT, os.path.abspath(path)],
        capture_output=True,
        timeout=10,
    )


def test_validator_script_exists_and_executable():
    assert os.path.isfile(VALIDATOR_SCRIPT), f"Validator script missing at {VALIDATOR_SCRIPT}"
    assert os.access(VALIDATOR_SCRIPT, os.X_OK) or VALIDATOR_SCRIPT.endswith('.py'), f"Validator script {VALIDATOR_SCRIPT} is not executable."


def test_clean_corpus_accepted():
    clean_files = [os.path.join(CLEAN_DIR, f) for f in os.listdir(CLEAN_DIR) if os.path.isfile(os.path.join(CLEAN_DIR, f))]
    assert len(clean_files) > 0, f"No files found in clean corpus {CLEAN_DIR}"

    failed_files = []
    for fpath in clean_files:
        result = run_validator(fpath)
        if result.returncode != 0:
            failed_files.append(os.path.basename(fpath))

    total = len(clean_files)
    failed_count = len(failed_files)
    assert failed_count == 0, f"{failed_count} of {total} clean modified (rejected). Offending files: {', '.join(failed_files)}"


def test_evil_corpus_rejected():
    evil_files = [os.path.join(EVIL_DIR, f) for f in os.listdir(EVIL_DIR) if os.path.isfile(os.path.join(EVIL_DIR, f))]
    assert len(evil_files) > 0, f"No files found in evil corpus {EVIL_DIR}"

    bypassed_files = []
    for fpath in evil_files:
        result = run_validator(fpath)
        if result.returncode == 0:
            bypassed_files.append(os.path.basename(fpath))

    total = len(evil_files)
    bypassed_count = len(bypassed_files)
    assert bypassed_count == 0, f"{bypassed_count} of {total} evil bypassed (accepted). Offending files: {', '.join(bypassed_files)}"


def test_validator_on_hidden_mixed_paths():
    # Both classes use unpredictable names in the same directory, so the result
    # must be based on file contents rather than the supplied corpus path.
    with tempfile.TemporaryDirectory(prefix="validator-eval-") as tmpdir:
        cases = []
        clean_contents = [
            "route add default gw 10.23.4.1\nBGP_PEER=\"203.0.113.77\"\n",
            "#!/bin/sh\necho provisioning 192.0.2.44\n",
            "primary_peer = 198.51.10.8\nbackup_peer = 203.0.113.9\n",
        ]
        evil_contents = [
            f"BGP_PEER=\"{BLOCKED_PREFIX}{secrets.randbelow(200) + 1}\"\n",
            f"route add -host {BLOCKED_PREFIX}{secrets.randbelow(200) + 1} gw 10.0.0.1\n",
            f"# unauthorized peer: {BLOCKED_PREFIX}{secrets.randbelow(200) + 1}\n",
        ]

        for expected, contents_group in ((0, clean_contents), (1, evil_contents)):
            for contents in contents_group:
                path = os.path.join(tmpdir, secrets.token_hex(12))
                with open(path, "w", encoding="utf-8") as f:
                    f.write(contents)
                cases.append((path, expected))

        failures = []
        for path, expected in cases:
            result = run_validator(path)
            if result.returncode != expected:
                failures.append(
                    f"{os.path.basename(path)} expected {expected}, got {result.returncode}"
                )
        assert not failures, "; ".join(failures)


def test_git_bare_repo_exists():
    assert os.path.isdir(GIT_DIR), f"Git repository directory missing at {GIT_DIR}"
    config_path = os.path.join(GIT_DIR, "config")
    assert os.path.isfile(config_path), f"Git config missing at {config_path}, is it a bare repo?"

    with open(config_path, "r") as f:
        content = f.read()
        assert "bare = true" in content.lower(), f"Repository at {GIT_DIR} is not a bare repository."


def test_git_hook_exists_and_configured():
    assert os.path.isfile(HOOK_PATH), f"Git pre-receive hook missing at {HOOK_PATH}"
    assert os.access(HOOK_PATH, os.X_OK), f"Git pre-receive hook at {HOOK_PATH} is not executable."

    with open(HOOK_PATH, "r") as f:
        content = f.read()
        assert "STRICT_MODE=1" in content, f"pre-receive hook does not export STRICT_MODE=1"
        assert "validate_config.py" in content, f"pre-receive hook does not call validate_config.py"


def test_git_hook_executes_validator_with_strict_mode():
    assert os.path.isfile(VALIDATOR_SCRIPT), "Validator must exist before hook execution test"
    marker_fd, marker_path = tempfile.mkstemp(prefix="hook-invocation-")
    os.close(marker_fd)
    os.unlink(marker_path)
    backup_path = VALIDATOR_SCRIPT + ".verifier-backup-" + secrets.token_hex(8)

    os.replace(VALIDATOR_SCRIPT, backup_path)
    try:
        spy = f'''#!/usr/bin/env python3
import os
with open({marker_path!r}, "a", encoding="utf-8") as marker:
    marker.write(os.environ.get("STRICT_MODE", "") + "\\n")
'''
        with open(VALIDATOR_SCRIPT, "w", encoding="utf-8") as f:
            f.write(spy)
        os.chmod(VALIDATOR_SCRIPT, 0o755)

        result = subprocess.run(
            [HOOK_PATH],
            input=b"",
            capture_output=True,
            timeout=10,
            cwd=GIT_DIR,
        )
        assert result.returncode == 0, (
            f"pre-receive hook failed when executed: "
            f"{result.stderr.decode(errors='replace')}"
        )
        assert os.path.isfile(marker_path), "pre-receive hook did not execute validate_config.py"
        with open(marker_path, "r", encoding="utf-8") as f:
            strict_values = [line.strip() for line in f if line.strip()]
        assert "1" in strict_values, "pre-receive hook did not call validator with STRICT_MODE=1"
    finally:
        try:
            if os.path.lexists(VALIDATOR_SCRIPT):
                os.unlink(VALIDATOR_SCRIPT)
        finally:
            os.replace(backup_path, VALIDATOR_SCRIPT)
        if os.path.exists(marker_path):
            os.unlink(marker_path)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
