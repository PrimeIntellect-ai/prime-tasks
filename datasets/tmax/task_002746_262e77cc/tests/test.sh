#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import shlex
import stat
import subprocess
import tempfile
import pytest


def test_build_runner_patched():
    script_path = "/home/user/pipeline/build_runner.sh"
    assert os.path.isfile(script_path), f"File {script_path} does not exist"
    assert os.access(script_path, os.X_OK), f"File {script_path} is not executable"

    with open(script_path, "r") as f:
        content = f.read()

    assert "eval" not in content, "Vulnerability not patched: 'eval' is still present in build_runner.sh"
    assert "make" in content, "Script does not seem to call 'make' anymore. Functionality might be broken."

    makefile_path = "/home/user/project/Makefile"
    with open(makefile_path, "rb") as f:
        original_makefile = f.read()
    original_mode = stat.S_IMODE(os.stat(makefile_path).st_mode)

    target = "verify_" + secrets.token_hex(8)
    with tempfile.TemporaryDirectory() as work:
        built_marker = os.path.join(work, "built_" + secrets.token_hex(8))
        injection_marker = os.path.join(work, "injected_" + secrets.token_hex(8))
        makefile = (
            f".PHONY: {target}\n"
            f"{target}:\n"
            f"\t@printf built > {shlex.quote(built_marker)}\n"
        )
        try:
            with open(makefile_path, "w") as f:
                f.write(makefile)

            result = subprocess.run([script_path, target], capture_output=True, text=True, timeout=15)
            assert result.returncode == 0, (
                f"build_runner.sh did not successfully build the supplied target: "
                f"stdout={result.stdout!r}, stderr={result.stderr!r}"
            )
            assert os.path.isfile(built_marker), "The requested make target was not actually executed"

            payload = f"{target}; /usr/bin/touch {injection_marker}"
            subprocess.run([script_path, payload], capture_output=True, text=True, timeout=15)
            assert not os.path.exists(injection_marker), "build_runner.sh still permits shell command injection"
        finally:
            with open(makefile_path, "wb") as f:
                f.write(original_makefile)
            os.chmod(makefile_path, original_mode)


def test_audit_report():
    report_path = "/home/user/audit_report.json"
    assert os.path.isfile(report_path), f"Report {report_path} does not exist"

    with open(report_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {report_path} is not valid JSON")

    assert isinstance(data, dict), "Audit report must be a JSON object"
    assert set(data.keys()) == {"build_runner_cwe", "validator_secret"}, "Audit report has an incorrect structure"

    cwe = data.get("build_runner_cwe")
    assert cwe in ["CWE-78", "CWE-77"], f"Expected CWE-78 or CWE-77 for build_runner_cwe, got {cwe}"

    secret = data.get("validator_secret")
    assert secret == "AUTH_KEY_9921_DEV", f"Incorrect validator secret found: {secret}"


def test_enforce_policy_script():
    script_path = "/home/user/enforce_policy.sh"
    assert os.path.isfile(script_path), f"Script {script_path} does not exist"
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable"

    log_file = "/home/user/fixed_files.log"
    if os.path.exists(log_file):
        os.remove(log_file)

    with tempfile.TemporaryDirectory(prefix="policy_" + secrets.token_hex(5) + "_") as temp_dir:
        nested = [temp_dir]
        current = temp_dir
        for _ in range(3):
            current = os.path.join(current, "dir_" + secrets.token_hex(5))
            os.mkdir(current)
            nested.append(current)

        entries = []

        def add_file(parent, mode, should_change):
            path = os.path.join(parent, "file_" + secrets.token_hex(8) + ".dat")
            with open(path, "w") as fp:
                fp.write(secrets.token_hex(12))
            os.chmod(path, mode)
            entries.append((path, mode, should_change))
            return path

        normal_files = [
            add_file(nested[0], secrets.choice([0o600, 0o640, 0o644, 0o755]), False),
            add_file(nested[3], secrets.choice([0o600, 0o640, 0o644, 0o755]), False),
        ]
        bad_files = [
            add_file(nested[1], secrets.choice([0o4700, 0o4754, 0o4765]), True),
            add_file(nested[2], secrets.choice([0o2640, 0o2751, 0o2755]), True),
            add_file(nested[3], secrets.choice([0o606, 0o622, 0o666]), True),
            add_file(nested[3], secrets.choice([0o6777, 0o6606, 0o6742]), True),
        ]

        result = subprocess.run([script_path, temp_dir], capture_output=True, text=True, timeout=20)
        assert result.returncode == 0, f"enforce_policy.sh failed with output: {result.stderr}"

        clear_mask = stat.S_ISUID | stat.S_ISGID | stat.S_IWOTH
        for path, original, should_change in entries:
            actual = stat.S_IMODE(os.stat(path).st_mode)
            if should_change:
                assert not (actual & stat.S_ISUID), f"SUID bit was not removed from {path}"
                assert not (actual & stat.S_ISGID), f"SGID bit was not removed from {path}"
                assert not (actual & stat.S_IWOTH), f"World-writable bit was not removed from {path}"
                expected_mode = original & ~clear_mask
                assert actual == expected_mode, f"Unrelated permissions were changed on {path}: expected {oct(expected_mode)}, got {oct(actual)}"
            else:
                assert actual == original, f"Normal file permissions were incorrectly altered for {path}"

        assert os.path.isfile(log_file), f"Log file {log_file} was not created"
        with open(log_file, "r") as f:
            lines = [line.strip() for line in f.readlines() if line.strip()]

        expected_modified = sorted(bad_files)
        assert lines == expected_modified, f"Log file contents do not match expected sorted paths. Expected {expected_modified}, got {lines}"

        second = subprocess.run([script_path, temp_dir], capture_output=True, text=True, timeout=20)
        assert second.returncode == 0, f"enforce_policy.sh failed on an already-compliant tree: {second.stderr}"
        with open(log_file, "r") as f:
            second_lines = [line.strip() for line in f.readlines() if line.strip()]
        assert second_lines == expected_modified, "Files that were not modified were incorrectly added to the log"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
