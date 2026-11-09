#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import gzip
import os
import pwd
import secrets
import shutil
import stat
import subprocess
import tempfile
from contextlib import contextmanager

HOME = "/home/user"
LOG_DIR = "/home/user/logs"
LOG_FILE = "/home/user/logs/ci_build.log"
USER_INFO = pwd.getpwnam("user")


def run(command, *, input_text=None, timeout=20):
    return subprocess.run(
        command,
        input=input_text,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
        check=False,
    )


@contextmanager
def isolated_logs():
    assert os.path.isdir(LOG_DIR) and not os.path.islink(LOG_DIR), \
        f"{LOG_DIR} must be a real directory"

    backup = f"{LOG_DIR}.verifier-{secrets.token_hex(12)}"
    os.rename(LOG_DIR, backup)
    os.mkdir(LOG_DIR, 0o755)
    os.chown(LOG_DIR, USER_INFO.pw_uid, USER_INFO.pw_gid)
    try:
        yield
    finally:
        if os.path.lexists(LOG_DIR):
            if os.path.isdir(LOG_DIR) and not os.path.islink(LOG_DIR):
                shutil.rmtree(LOG_DIR)
            else:
                os.unlink(LOG_DIR)
        os.rename(backup, LOG_DIR)


@contextmanager
def temporary_raw_build(content):
    path = "/home/user/raw_build.txt"
    old_content = None
    old_mode = None
    old_uid = None
    old_gid = None
    if os.path.exists(path):
        with open(path, "rb") as f:
            old_content = f.read()
        st = os.stat(path)
        old_mode = stat.S_IMODE(st.st_mode)
        old_uid, old_gid = st.st_uid, st.st_gid

    with open(path, "w", encoding="utf-8") as f:
        f.write(content)
    os.chown(path, USER_INFO.pw_uid, USER_INFO.pw_gid)
    os.chmod(path, 0o644)

    try:
        yield
    finally:
        if os.path.lexists(path):
            os.unlink(path)
        if old_content is not None:
            with open(path, "wb") as f:
                f.write(old_content)
            os.chown(path, old_uid, old_gid)
            os.chmod(path, old_mode)


def assert_logger_behavior(executable, as_user):
    nonce = secrets.token_hex(16)
    input_lines = [
        f"ordinary-{nonce}",
        f"FATAL critical-{nonce}",
        f"tail-{nonce}",
    ]
    sentinel = f"existing-{nonce}"

    with isolated_logs():
        with open(LOG_FILE, "w", encoding="utf-8") as f:
            f.write(sentinel + "\n")
        os.chown(LOG_FILE, USER_INFO.pw_uid, USER_INFO.pw_gid)
        os.chmod(LOG_FILE, 0o644)

        command = [executable]
        if as_user:
            command = ["runuser", "-u", "user", "--", executable]
        result = run(command, input_text="\n".join(input_lines) + "\n")
        assert result.returncode == 0, \
            f"Logger execution failed: stdout={result.stdout!r}, stderr={result.stderr!r}"

        assert os.path.isfile(LOG_FILE), "Logger did not write ci_build.log"
        with open(LOG_FILE, "r", encoding="utf-8") as f:
            actual = f.read().splitlines()
        assert actual == [sentinel] + input_lines, \
            f"Logger did not append all input lines unchanged: {actual!r}"


def test_ci_logger_compiled():
    path = "/home/user/ci_logger"
    assert os.path.isfile(path), f"Executable {path} not found. Did you compile the C++ code?"
    assert os.access(path, os.X_OK), f"File {path} is not executable."

    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", \
            "ci_logger is not a compiled ELF executable"


def test_run_ci_script():
    path = "/home/user/run_ci.sh"
    assert os.path.isfile(path), f"Script {path} not found."
    assert os.access(path, os.X_OK), f"Script {path} is not executable."

    with open(path, "r") as f:
        content = f.read()

    # Check for robust error handling
    assert "set -e" in content or "set -o errexit" in content or "set -o pipefail" in content, \
        "Script does not appear to enable robust error handling (e.g., set -e or set -o pipefail)."


def test_logrotate_conf():
    path = "/home/user/logrotate.conf"
    assert os.path.isfile(path), f"logrotate configuration {path} not found."

    with open(path, "r") as f:
        content = f.read()

    assert "/home/user/logs/ci_build.log" in content, "logrotate.conf does not target /home/user/logs/ci_build.log"
    assert "daily" in content, "logrotate.conf missing 'daily' rule"
    assert "rotate 3" in content, "logrotate.conf missing 'rotate 3' rule"
    assert "compress" in content, "logrotate.conf missing 'compress' rule"
    assert "missingok" in content, "logrotate.conf missing 'missingok' rule"


def test_logrotate_output():
    log_gz = "/home/user/logs/ci_build.log.1.gz"
    assert os.path.isfile(log_gz), f"Rotated log file {log_gz} not found. Did you run logrotate?"

    expected_lines = [
        "[CI] Build initialized",
        "[CI] FATAL: Missing provisioning credentials",
        "[CI] Build process terminated early"
    ]

    with gzip.open(log_gz, "rt") as f:
        content = f.read().strip().splitlines()

    assert content == expected_lines, \
        f"The content of the rotated log does not match the expected processed output. Got: {content}"


def test_fixed_source_compiles_and_preserves_fatal_lines():
    source = "/home/user/ci_logger.cpp"
    assert os.path.isfile(source), f"Source file {source} not found"

    with tempfile.TemporaryDirectory() as tmpdir:
        executable = os.path.join(tmpdir, "ci_logger_from_source")
        result = run(["g++", source, "-o", executable], timeout=30)
        assert result.returncode == 0, \
            f"ci_logger.cpp does not compile with g++: {result.stderr}"
        assert_logger_behavior(executable, as_user=False)


def test_submitted_logger_executes_and_preserves_fatal_lines():
    assert_logger_behavior("/home/user/ci_logger", as_user=True)


def test_run_ci_pipeline_on_unseen_input():
    nonce = secrets.token_hex(16)
    raw = "\n".join([
        f"[CI] start-{nonce}",
        f"[DEBUG] [CI] ERROR hidden-{nonce}",
        f" [CI] ERROR leading-space-{nonce}",
        f"[CI] ERROR: first-{nonce}",
        f"[INFO] ignored-{nonce}",
        f"[CI] FATAL existing-{nonce}",
        f"[CI] ERROR_CODE unchanged-{nonce}",
        f"[CI] ERROR then ERROR again-{nonce}",
    ]) + "\n"
    expected = [
        f"[CI] start-{nonce}",
        f"[CI] FATAL: first-{nonce}",
        f"[CI] FATAL existing-{nonce}",
        f"[CI] ERROR_CODE unchanged-{nonce}",
        f"[CI] FATAL then FATAL again-{nonce}",
    ]

    with temporary_raw_build(raw), isolated_logs():
        result = run(["runuser", "-u", "user", "--", "/home/user/run_ci.sh"])
        assert result.returncode == 0, \
            f"run_ci.sh failed: stdout={result.stdout!r}, stderr={result.stderr!r}"
        assert os.path.isfile(LOG_FILE), "run_ci.sh did not produce ci_build.log"
        with open(LOG_FILE, "r", encoding="utf-8") as f:
            actual = f.read().splitlines()
        assert actual == expected, \
            f"run_ci.sh did not perform the required pipeline. Got: {actual!r}"


def test_logrotate_configuration_actually_rotates_and_compresses():
    nonce = secrets.token_hex(16)
    expected = [f"rotation-{nonce}", f"FATAL rotation-{nonce}"]
    state = "/home/user/logrotate.status"
    state_backup = None
    state_meta = None

    if os.path.exists(state):
        with open(state, "rb") as f:
            state_backup = f.read()
        st = os.stat(state)
        state_meta = (stat.S_IMODE(st.st_mode), st.st_uid, st.st_gid)
        os.unlink(state)

    try:
        with isolated_logs():
            with open(LOG_FILE, "w", encoding="utf-8") as f:
                f.write("\n".join(expected) + "\n")
            os.chown(LOG_FILE, USER_INFO.pw_uid, USER_INFO.pw_gid)
            os.chmod(LOG_FILE, 0o644)

            result = run([
                "runuser", "-u", "user", "--",
                "logrotate", "-f", "-s", state, "/home/user/logrotate.conf"
            ])
            assert result.returncode == 0, \
                f"logrotate command failed: stdout={result.stdout!r}, stderr={result.stderr!r}"

            rotated = "/home/user/logs/ci_build.log.1.gz"
            assert os.path.isfile(rotated), \
                "Configuration did not create ci_build.log.1.gz when forcibly rotated"
            with open(rotated, "rb") as f:
                assert f.read(2) == b"\x1f\x8b", "Rotated output is not gzip-compressed"
            with gzip.open(rotated, "rt", encoding="utf-8") as f:
                actual = f.read().splitlines()
            assert actual == expected, \
                f"Rotated gzip did not preserve the active log contents: {actual!r}"
    finally:
        if os.path.lexists(state):
            os.unlink(state)
        if state_backup is not None:
            with open(state, "wb") as f:
                f.write(state_backup)
            mode, uid, gid = state_meta
            os.chown(state, uid, gid)
            os.chmod(state, mode)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
