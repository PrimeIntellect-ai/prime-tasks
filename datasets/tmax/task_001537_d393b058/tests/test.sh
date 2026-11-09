#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import subprocess
import random
import string
import tempfile
import pytest

ORACLE_PATH = "/app/legacy_ticket_extractor"
AGENT_PATH = "/home/user/ticket_extractor"
PARSER_SRC = "/home/user/parser_src"
REPO_PATH = "/home/user/config_repo.git"
LOG_PATH = "/home/user/repo_activity.log"
LOGROTATE_CONF = "/home/user/repo_logrotate.conf"
CHECK_STORAGE_SCRIPT = "/home/user/check_storage.sh"


def derived_output(input_data):
    # The legacy program reads at most 8191 bytes and applies this POSIX-ERE
    # pattern as a leftmost, non-overlapping search.
    data = input_data[:8191]
    matches = re.findall(rb"[A-Z]{3,5}-[0-9]{3,6}", data)
    return b",".join(matches) if matches else b"NO_TICKET"


def run_and_compare(path, cases, expected, label):
    for input_data, wanted in zip(cases, expected):
        proc = subprocess.run([path], input=input_data, capture_output=True)
        assert proc.returncode == 0, f"{label} return code mismatch on input {input_data!r}"
        assert proc.stdout == wanted, f"{label} stdout mismatch on input {input_data!r}. Expected {wanted!r}, got {proc.stdout!r}"
        assert proc.stderr == b"", f"{label} stderr mismatch on input {input_data!r}. Got {proc.stderr!r}"


def test_fuzz_equivalence_and_rust_source():
    assert os.path.exists(ORACLE_PATH), f"Oracle missing at {ORACLE_PATH}"
    assert os.path.exists(AGENT_PATH), f"Agent binary missing at {AGENT_PATH}"
    assert not os.path.islink(AGENT_PATH), "Agent executable must not be a symlink to the legacy program"
    assert os.path.isfile(AGENT_PATH), f"Agent executable at {AGENT_PATH} is not a regular file"
    assert os.access(AGENT_PATH, os.X_OK), f"Agent binary at {AGENT_PATH} is not executable"
    with open(AGENT_PATH, "rb") as f:
        agent_bytes = f.read()
    assert agent_bytes.startswith(b"\x7fELF"), "Agent executable is not a compiled ELF binary"

    assert os.path.isdir(PARSER_SRC), f"Rust project missing at {PARSER_SRC}"
    assert not os.path.islink(PARSER_SRC), "Rust project directory must not be a symlink"
    cargo_toml = os.path.join(PARSER_SRC, "Cargo.toml")
    assert os.path.isfile(cargo_toml), f"Cargo.toml missing at {cargo_toml}"
    rust_sources = []
    for root, dirs, files in os.walk(PARSER_SRC):
        dirs[:] = [d for d in dirs if d != "target"]
        for name in files:
            if name.endswith(".rs"):
                rust_sources.append(os.path.join(root, name))
    assert rust_sources, "No Rust source files found in parser_src"
    assert all(os.path.isfile(p) and not os.path.islink(p) for p in rust_sources), "Rust sources must be regular files"

    random.seed(42)
    charset = string.ascii_letters + string.digits + string.punctuation + " \n\t\r"
    cases = []
    expected = []
    for _ in range(5000):
        length = random.randint(0, 1024)
        input_data = "".join(random.choices(charset, k=length)).encode("utf-8")
        cases.append(input_data)
        wanted = derived_output(input_data)
        oracle_proc = subprocess.run([ORACLE_PATH], input=input_data, capture_output=True)
        assert oracle_proc.returncode == 0, f"Oracle return code mismatch on input {input_data!r}"
        assert oracle_proc.stdout == wanted, f"Oracle did not match independently derived answer on input {input_data!r}"
        assert oracle_proc.stderr == b"", f"Oracle wrote stderr on input {input_data!r}"
        expected.append(wanted)

    with open(ORACLE_PATH, "rb") as f:
        oracle_bytes = f.read()
    assert agent_bytes != oracle_bytes, "Agent executable is byte-identical to the legacy binary"

    # Remove the legacy executable while exercising both the delivered artifact
    # and a clean release build. Direct symlinks and wrappers therefore fail.
    oracle_mode = os.stat(ORACLE_PATH).st_mode & 0o7777
    os.unlink(ORACLE_PATH)
    try:
        run_and_compare(AGENT_PATH, cases, expected, "Agent binary")

        with tempfile.TemporaryDirectory() as target_dir:
            build = subprocess.run(
                ["cargo", "build", "--release", "--offline", "--target-dir", target_dir, "--message-format=json"],
                cwd=PARSER_SRC,
                capture_output=True,
                text=True,
            )
            assert build.returncode == 0, f"Rust project failed a clean release build:\n{build.stdout}\n{build.stderr}"

            executables = []
            for line in build.stdout.splitlines():
                try:
                    message = json.loads(line)
                except json.JSONDecodeError:
                    continue
                if message.get("reason") == "compiler-artifact" and "bin" in message.get("target", {}).get("kind", []):
                    executable = message.get("executable")
                    if executable and executable not in executables:
                        executables.append(executable)

            assert executables, "Cargo project did not produce a release binary"
            rebuilt_ok = False
            failures = []
            for executable in executables:
                try:
                    run_and_compare(executable, cases, expected, "Rebuilt Rust binary")
                    rebuilt_ok = True
                    break
                except AssertionError as exc:
                    failures.append(str(exc))
            assert rebuilt_ok, "No binary rebuilt from parser_src was equivalent: " + "; ".join(failures)
    finally:
        with open(ORACLE_PATH, "wb") as f:
            f.write(oracle_bytes)
        os.chmod(ORACLE_PATH, oracle_mode)


def test_git_hook_functionality():
    assert os.path.exists(REPO_PATH), f"Git repo missing at {REPO_PATH}"

    with tempfile.TemporaryDirectory() as tmpdir:
        clone_dir = os.path.join(tmpdir, "clone")
        subprocess.run(["git", "clone", REPO_PATH, clone_dir], check=True, capture_output=True)

        test_file = os.path.join(clone_dir, "test.txt")
        with open(test_file, "w") as f:
            f.write("test")

        subprocess.run(["git", "add", "test.txt"], cwd=clone_dir, check=True, capture_output=True)
        subprocess.run(["git", "-c", "user.name=Test", "-c", "user.email=test@example.com", "commit", "-m", "Fixes VANGUARD-8821 and also bugs"], cwd=clone_dir, check=True, capture_output=True)
        subprocess.run(["git", "push", "origin", "master"], cwd=clone_dir, check=True, capture_output=True)

    assert os.path.exists(LOG_PATH), f"Log file missing at {LOG_PATH}"
    with open(LOG_PATH, "r") as f:
        log_content = f.read()

    pattern = r"\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\] Codename VANGUARD-8821 processed"
    assert re.search(pattern, log_content), f"Expected log entry not found in {LOG_PATH}"


def test_logrotate_conf():
    assert os.path.exists(LOGROTATE_CONF), f"Logrotate conf missing at {LOGROTATE_CONF}"
    with open(LOGROTATE_CONF, "r") as f:
        content = f.read()

    assert "daily" in content, "Missing 'daily' directive in logrotate conf"
    assert "rotate 7" in content, "Missing 'rotate 7' directive in logrotate conf"
    assert "compress" in content, "Missing 'compress' directive in logrotate conf"
    assert LOG_PATH in content, f"Logrotate conf does not target {LOG_PATH}"


def test_crontab():
    proc = subprocess.run(["crontab", "-l"], capture_output=True, text=True)
    assert proc.returncode == 0, "Failed to read crontab"
    crontab_content = proc.stdout

    assert re.search(r"0\s+\*\s+\*\s+\*\s+\*\s+/home/user/check_storage\.sh", crontab_content), "Missing check_storage.sh crontab entry"
    assert re.search(r"0\s+0\s+\*\s+\*\s+\*\s+logrotate\s+/home/user/repo_logrotate\.conf\s+--state\s+/home/user/logrotate\.state", crontab_content), "Missing logrotate crontab entry"


def test_check_storage_script():
    assert os.path.exists(CHECK_STORAGE_SCRIPT), f"Storage check script missing at {CHECK_STORAGE_SCRIPT}"
    assert os.access(CHECK_STORAGE_SCRIPT, os.X_OK), f"Storage check script at {CHECK_STORAGE_SCRIPT} is not executable"

    dummy_file = os.path.join(REPO_PATH, "dummy_60mb.bin")
    try:
        with open(dummy_file, "wb") as f:
            f.write(os.urandom(60 * 1024 * 1024))

        subprocess.run([CHECK_STORAGE_SCRIPT], check=True, capture_output=True)
        assert os.path.exists(LOG_PATH), f"Log file missing at {LOG_PATH}"
        with open(LOG_PATH, "r") as f:
            log_content = f.read()

        assert "WARNING: QUOTA EXCEEDED" in log_content, "Storage check script failed to append warning to log"
    finally:
        if os.path.exists(dummy_file):
            os.remove(dummy_file)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
