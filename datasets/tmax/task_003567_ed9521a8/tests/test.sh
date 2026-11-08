#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import os
import secrets
import stat
import subprocess


def test_cert_status_verified():
    status_file = "/home/user/cert_status.txt"
    cert_file = "/home/user/cert_bundle.pem"
    hash_file = "/home/user/cert_hash.sha256"

    assert os.path.exists(status_file), f"File {status_file} is missing. Did you perform the integrity verification?"

    with open(status_file, "r") as f:
        content = f.read().strip()

    assert content == "VERIFIED", f"Expected {status_file} to contain 'VERIFIED', but found '{content}'."

    with open(hash_file, "r") as f:
        fields = f.read().strip().split()
    assert fields, f"Expected checksum file {hash_file} to contain a SHA-256 digest."
    expected = fields[0].lower()
    assert len(expected) == 64 and all(c in "0123456789abcdef" for c in expected), \
        f"The checksum in {hash_file} is not a valid SHA-256 digest."

    digest = hashlib.sha256()
    with open(cert_file, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            digest.update(chunk)
    actual = digest.hexdigest()
    assert actual == expected, \
        f"The SHA-256 checksum of {cert_file} does not match {hash_file}; cert_status.txt must not claim VERIFIED."


def test_legacy_runner_execution_and_log():
    runner_script = "/home/user/legacy_runner.sh"
    log_file = "/home/user/processing.log"

    # Ensure the log file is removed before running to verify it's recreated properly
    if os.path.exists(log_file):
        os.remove(log_file)

    # Execute the runner script
    result = subprocess.run(["bash", runner_script], capture_output=True, text=True)
    assert result.returncode == 0, f"Execution of {runner_script} failed with error: {result.stderr}"

    assert os.path.exists(log_file), f"Log file {log_file} was not created after running the script."

    with open(log_file, "r") as f:
        log_content = f.read()

    assert "[REDACTED]" in log_content, f"The log file {log_file} does not contain the redacted string '[REDACTED]'."
    assert "SUPER_SECRET_99!" not in log_content, f"The log file {log_file} still contains the plaintext password!"


def test_runner_really_passes_password_only_via_environment():
    runner_script = "/home/user/legacy_runner.sh"
    processor_script = "/home/user/processor.py"
    probe_file = f"/tmp/runner_probe_{secrets.token_hex(8)}.json"

    with open(processor_script, "rb") as f:
        original = f.read()
    original_mode = stat.S_IMODE(os.stat(processor_script).st_mode)

    probe = f'''import json
import os
import sys
with open({probe_file!r}, "w") as f:
    json.dump({{"argv": sys.argv, "password": os.environ.get("DB_PASSWORD")}}, f)
'''

    try:
        with open(processor_script, "w") as f:
            f.write(probe)
        os.chmod(processor_script, 0o755)

        env = os.environ.copy()
        env["DB_PASSWORD"] = "VERIFIER_DECOY_PASSWORD"
        result = subprocess.run(["bash", runner_script], env=env, capture_output=True, text=True)
        assert result.returncode == 0, f"Runner failed while testing credential transport: {result.stderr}"
        assert os.path.exists(probe_file), "The runner did not execute /home/user/processor.py."

        with open(probe_file, "r") as f:
            observed = json.load(f)

        assert observed["password"] == "SUPER_SECRET_99!", \
            "legacy_runner.sh did not actually set and pass the required DB_PASSWORD environment variable."
        argv_text = " ".join(observed["argv"])
        assert "SUPER_SECRET_99!" not in argv_text, "The database password was exposed in the processor command line."
        assert "--db-pass" not in observed["argv"], "The runner still passed the password using --db-pass."
    finally:
        with open(processor_script, "wb") as f:
            f.write(original)
        os.chmod(processor_script, original_mode)
        if os.path.exists(probe_file):
            os.remove(probe_file)


def test_processor_actually_reads_environment_and_redacts_dynamic_secret():
    processor_script = "/home/user/processor.py"
    log_file = "/home/user/processing.log"
    marker = f"/tmp/env_access_{secrets.token_hex(8)}"
    wrapper = f"/tmp/run_processor_{secrets.token_hex(8)}.py"
    dynamic_password = "DYNAMIC_SECRET_" + secrets.token_hex(16)

    wrapper_source = f'''import os
import runpy

marker = {marker!r}

class TrackingEnvironment(dict):
    def _record(self, key):
        if key == "DB_PASSWORD":
            with open(marker, "a") as f:
                f.write("accessed\\n")

    def __getitem__(self, key):
        self._record(key)
        return super().__getitem__(key)

    def get(self, key, default=None):
        self._record(key)
        return super().get(key, default)

os.environ = TrackingEnvironment(os.environ)
runpy.run_path({processor_script!r}, run_name="__main__")
'''

    try:
        with open(wrapper, "w") as f:
            f.write(wrapper_source)
        if os.path.exists(marker):
            os.remove(marker)
        if os.path.exists(log_file):
            os.remove(log_file)

        env = os.environ.copy()
        env["DB_PASSWORD"] = dynamic_password
        result = subprocess.run(["python3", wrapper], env=env, capture_output=True, text=True)
        assert result.returncode == 0, f"processor.py failed when supplied DB_PASSWORD: {result.stderr}"
        assert os.path.exists(marker), "processor.py did not actually access DB_PASSWORD from the environment."
        assert os.path.exists(log_file), "processor.py did not create processing.log."

        with open(log_file, "r") as f:
            log_content = f.read()
        assert "[REDACTED]" in log_content, "processor.py did not log the exact redaction marker."
        assert dynamic_password not in log_content, "processor.py leaked a dynamically supplied database password."
    finally:
        for path in (wrapper, marker):
            if os.path.exists(path):
                os.remove(path)


def test_legacy_runner_content():
    runner_script = "/home/user/legacy_runner.sh"
    assert os.path.exists(runner_script), f"File {runner_script} is missing."

    with open(runner_script, "r") as f:
        content = f.read()

    assert "--db-pass" not in content, f"The script {runner_script} still passes '--db-pass' as a command-line argument."
    assert "DB_PASSWORD" in content, f"The script {runner_script} does not seem to set the 'DB_PASSWORD' environment variable."
    assert "SUPER_SECRET_99!" in content, f"The script {runner_script} is missing the actual password value."


def test_processor_content():
    processor_script = "/home/user/processor.py"
    assert os.path.exists(processor_script), f"File {processor_script} is missing."

    with open(processor_script, "r") as f:
        content = f.read()

    assert "--db-pass" not in content, f"The script {processor_script} still defines or uses the '--db-pass' argument."

    # Check if os.environ or os.getenv is used for DB_PASSWORD
    uses_env = "os.environ" in content or "os.getenv" in content
    assert uses_env, f"The script {processor_script} does not appear to read from the environment (missing os.environ or os.getenv)."
    assert "DB_PASSWORD" in content, f"The script {processor_script} does not reference the 'DB_PASSWORD' environment variable."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
