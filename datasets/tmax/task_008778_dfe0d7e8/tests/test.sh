#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import subprocess
import tempfile
import time
from pathlib import Path

import pytest

PROJECT = Path("/home/user/migration_project")
EXPECT_SCRIPT = PROJECT / "init_db_auto.exp"
ENV_SCRIPT = PROJECT / "env_setup.sh"
DEPLOY_SCRIPT = PROJECT / "deploy.sh"
DB_SCRIPT = PROJECT / "db_service/init_db.sh"
MAIN_RS = PROJECT / "rust_app/src/main.rs"
BINARY = PROJECT / "rust_app/target/release/rust_app"
FLAG = PROJECT / "data/db_ready.flag"
LOG = PROJECT / "app.log"
SUCCESS = "Connection established\n"


def test_init_db_auto_exp_exists_and_executable():
    path = str(EXPECT_SCRIPT)
    assert os.path.isfile(path), f"Expect script {path} does not exist."
    assert os.access(path, os.X_OK), f"Expect script {path} is not executable."

    with open(path, "r") as f:
        content = f.read()
        assert "migrate123" in content, f"{path} does not contain the required password 'migrate123'."


def test_env_setup_sh_exists_and_exports():
    path = str(ENV_SCRIPT)
    assert os.path.isfile(path), f"Script {path} does not exist."
    assert os.access(path, os.X_OK), f"Script {path} is not executable."

    with open(path, "r") as f:
        content = f.read()
        assert "DATA_PATH" in content, f"{path} does not set DATA_PATH."
        assert "/home/user/migration_project/data" in content, f"{path} does not set the correct DATA_PATH value."

    result = subprocess.run(
        ["bash", "-c", f"unset DATA_PATH; source {ENV_SCRIPT}; printf '%s' \"$DATA_PATH\""],
        text=True,
        capture_output=True,
        timeout=5,
    )
    assert result.returncode == 0, result.stderr
    assert result.stdout == "/home/user/migration_project/data"


def test_deploy_sh_exists_and_executable():
    path = str(DEPLOY_SCRIPT)
    assert os.path.isfile(path), f"Deployment script {path} does not exist."
    assert os.access(path, os.X_OK), f"Deployment script {path} is not executable."

    with open(path, "r") as f:
        content = f.read()
        assert "env_setup.sh" in content, f"{path} does not source env_setup.sh."
        assert "cargo build --release" in content, f"{path} does not compile the Rust app."
        assert "init_db_auto.exp" in content, f"{path} does not execute init_db_auto.exp."
        assert "wait" in content, f"{path} does not use 'wait' to wait for background processes."


def test_rust_main_rs_modified():
    path = str(MAIN_RS)
    assert os.path.isfile(path), f"Rust source {path} does not exist."

    with open(path, "r") as f:
        content = f.read()
        assert "sleep" in content, f"{path} does not use sleep for retrying."
        assert "Connection established" in content, f"{path} does not contain the success message."


def test_expect_script_really_runs_db_script_and_answers_prompt():
    original = DB_SCRIPT.read_bytes()
    original_mode = stat.S_IMODE(DB_SCRIPT.stat().st_mode)
    challenge_dir = Path(tempfile.mkdtemp(prefix="expect_challenge_"))
    invoked = challenge_dir / "invoked"
    received = challenge_dir / "password"

    stub = f'''#!/bin/bash
set -e
touch {invoked}
echo -n "Enter admin password to initialize DB: "
IFS= read -r password
printf '%s' "$password" > {received}
[ "$password" = "migrate123" ]
sleep 1
mkdir -p /home/user/migration_project/data
touch /home/user/migration_project/data/db_ready.flag
echo "DB Ready."
'''

    try:
        DB_SCRIPT.write_text(stub)
        DB_SCRIPT.chmod(0o755)
        FLAG.unlink(missing_ok=True)
        result = subprocess.run(
            ["expect", str(EXPECT_SCRIPT)],
            cwd=str(PROJECT),
            text=True,
            capture_output=True,
            timeout=8,
        )
        assert result.returncode == 0, result.stdout + result.stderr
        assert invoked.is_file(), "The expect script did not execute db_service/init_db.sh."
        assert received.read_text() == "migrate123", "The expect script did not provide the required password."
        assert FLAG.is_file(), "The database initialization process did not complete."
    finally:
        DB_SCRIPT.write_bytes(original)
        DB_SCRIPT.chmod(original_mode)


def descendant_pids(root_pid):
    descendants = {root_pid}
    changed = True
    while changed:
        changed = False
        for entry in Path("/proc").iterdir():
            if not entry.name.isdigit():
                continue
            try:
                fields = (entry / "stat").read_text().split()
                ppid = int(fields[3])
                pid = int(entry.name)
            except (OSError, ValueError, IndexError):
                continue
            if ppid in descendants and pid not in descendants:
                descendants.add(pid)
                changed = True
    descendants.discard(root_pid)
    return descendants


def deploy_once_and_observe_background_binary():
    proc = subprocess.Popen(
        [str(DEPLOY_SCRIPT)],
        cwd=str(PROJECT),
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    saw_binary_while_deploy_running = False
    deadline = time.monotonic() + 30
    expected_exe = os.path.realpath(BINARY)

    while time.monotonic() < deadline and proc.poll() is None:
        for pid in descendant_pids(proc.pid):
            try:
                exe = os.path.realpath(f"/proc/{pid}/exe")
            except OSError:
                continue
            if exe == expected_exe:
                saw_binary_while_deploy_running = True
                break
        if saw_binary_while_deploy_running:
            break
        time.sleep(0.05)

    try:
        output, _ = proc.communicate(timeout=20)
    except subprocess.TimeoutExpired:
        proc.kill()
        output, _ = proc.communicate()
        pytest.fail("deploy.sh did not finish in time. Output:\n" + output)

    assert proc.returncode == 0, output
    assert saw_binary_while_deploy_running, "The compiled Rust binary was not observed running in the background during deployment."
    return output


def test_deployment_pipeline_executes_and_appends():
    FLAG.unlink(missing_ok=True)
    LOG.unlink(missing_ok=True)
    BINARY.unlink(missing_ok=True)

    deploy_once_and_observe_background_binary()
    assert BINARY.is_file() and os.access(BINARY, os.X_OK), "cargo build --release did not produce the executable."
    assert FLAG.is_file(), "deploy.sh did not complete database initialization."
    assert LOG.read_text() == SUCCESS

    FLAG.unlink(missing_ok=True)
    second = subprocess.run(
        [str(DEPLOY_SCRIPT)],
        cwd=str(PROJECT),
        text=True,
        capture_output=True,
        timeout=30,
    )
    assert second.returncode == 0, second.stdout + second.stderr
    assert LOG.read_text() == SUCCESS + SUCCESS, "Successful runs must append rather than overwrite app.log."


def test_rust_binary_fails_after_ten_retries_when_flag_never_appears():
    assert BINARY.is_file() and os.access(BINARY, os.X_OK)
    LOG.unlink(missing_ok=True)
    missing_data = Path(tempfile.mkdtemp(prefix="missing_db_flag_"))
    env = os.environ.copy()
    env["DATA_PATH"] = str(missing_data)

    started = time.monotonic()
    result = subprocess.run(
        [str(BINARY)],
        cwd=str(PROJECT),
        env=env,
        text=True,
        capture_output=True,
        timeout=14,
    )
    elapsed = time.monotonic() - started

    assert result.returncode != 0, "The Rust application succeeded even though the DB flag never appeared."
    assert elapsed >= 8.5, f"The application failed too quickly ({elapsed:.2f}s) instead of retrying ten times."
    assert elapsed <= 12.5, f"The application did not stop after ten retry attempts ({elapsed:.2f}s)."
    assert not LOG.exists(), "A failed connection attempt must not log a successful connection."


def test_rust_binary_retries_then_appends_on_success():
    delayed_data = Path(tempfile.mkdtemp(prefix="delayed_db_flag_"))
    delayed_flag = delayed_data / "db_ready.flag"
    LOG.write_text("existing entry\n")
    env = os.environ.copy()
    env["DATA_PATH"] = str(delayed_data)

    proc = subprocess.Popen(
        [str(BINARY)],
        cwd=str(PROJECT),
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    time.sleep(2.2)
    assert proc.poll() is None, "The Rust application did not wait for a delayed DB flag."
    delayed_flag.write_text("ready\n")
    stdout, stderr = proc.communicate(timeout=5)

    assert proc.returncode == 0, stdout + stderr
    assert LOG.read_text() == "existing entry\n" + SUCCESS, "The Rust application must append the exact success line."


def test_app_log_contains_success_message():
    path = str(LOG)
    assert os.path.isfile(path), f"Log file {path} does not exist. Did you run deploy.sh?"

    with open(path, "r") as f:
        content = f.read()
        assert "Connection established" in content, f"{path} does not contain 'Connection established'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
