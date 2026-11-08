#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import subprocess
import tempfile
import uuid


def run(cmd, timeout=10):
    return subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=timeout)


def remove_path(path):
    try:
        os.unlink(path)
    except FileNotFoundError:
        pass


def stash(path):
    if not os.path.lexists(path):
        return None
    backup = f"/tmp/verifier-backup-{uuid.uuid4().hex}"
    os.replace(path, backup)
    return backup


def restore(path, backup):
    remove_path(path)
    if backup is not None:
        os.replace(backup, path)


# Preserve the original final-state assertions.
def test_config_env_contents():
    config_path = "/home/user/config.env"
    assert os.path.isfile(config_path), f"File {config_path} does not exist"
    with open(config_path, "r") as f:
        content = f.read()
    assert "TOKEN=ZGVwbG95X3NlY3JldA==" in content, f"{config_path} does not contain the expected token"


def test_crash_lock_exists():
    lock_path = "/home/user/crash.lock"
    assert os.path.isfile(lock_path), f"File {lock_path} was not created"


def test_worker_permissions():
    worker_path = "/home/user/worker"
    assert os.path.isfile(worker_path), f"Executable {worker_path} does not exist"
    st = os.stat(worker_path)
    perms = stat.S_IMODE(st.st_mode)
    assert perms == 0o700, f"Permissions for {worker_path} are {oct(perms)}, expected 0o700"


def test_supervisor_permissions():
    supervisor_path = "/home/user/supervisor.sh"
    assert os.path.isfile(supervisor_path), f"Script {supervisor_path} does not exist"
    st = os.stat(supervisor_path)
    perms = stat.S_IMODE(st.st_mode)
    assert perms == 0o700, f"Permissions for {supervisor_path} are {oct(perms)}, expected 0o700"


def test_supervisor_log_contents():
    log_path = "/home/user/supervisor.log"
    assert os.path.isfile(log_path), f"Log file {log_path} does not exist"
    with open(log_path, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]
    expected_lines = ["Worker exited with 1", "Worker exited with 0"]
    assert lines == expected_lines, f"Contents of {log_path} do not match the expected supervisor execution sequence. Got: {lines}"


def test_expect_script_really_drives_vault_and_captures_output():
    expect_path = "/home/user/fetch_token.exp"
    vault_path = "/home/user/vault_cli.py"
    config_path = "/home/user/config.env"
    assert os.path.isfile(expect_path), f"Expect script {expect_path} does not exist"
    assert stat.S_ISREG(os.lstat(expect_path).st_mode), f"{expect_path} is not a regular file"

    vault_backup = stash(vault_path)
    config_backup = stash(config_path)
    marker = f"/tmp/vault-called-{uuid.uuid4().hex}"
    canary = f"TOKEN=VERIFIER_{uuid.uuid4().hex}"
    try:
        instrumented_vault = f'''#!/usr/bin/env python3
import sys
sys.stdout.write("Enter deployment passphrase: ")
sys.stdout.flush()
p = sys.stdin.readline().strip()
if p == "deploy_2024":
    open({marker!r}, "w").write("called")
    print({canary!r})
else:
    print("ACCESS DENIED")
    sys.exit(1)
'''
        with open(vault_path, "w") as f:
            f.write(instrumented_vault)
        os.chmod(vault_path, 0o755)

        result = run(["expect", "-f", expect_path])
        assert result.returncode == 0, f"Expect script failed: stdout={result.stdout!r}, stderr={result.stderr!r}"
        assert os.path.isfile(marker), "Expect script did not execute the vault and provide the deployment passphrase"
        assert os.path.isfile(config_path), "Expect script did not create config.env"
        with open(config_path, "r") as f:
            generated = f.read()
        assert canary in generated, "Expect script did not capture the successful output produced by the vault"
    finally:
        remove_path(marker)
        restore(config_path, config_backup)
        restore(vault_path, vault_backup)


def exercise_worker(binary):
    config_path = "/home/user/config.env"
    lock_path = "/home/user/crash.lock"
    config_backup = stash(config_path)
    lock_backup = stash(lock_path)
    try:
        # An invalid config must take precedence and must not create crash.lock.
        with open(config_path, "w") as f:
            f.write("TOKEN=INVALID\n")
        remove_path(lock_path)
        result = run([binary])
        assert result.returncode == 2, f"Worker returned {result.returncode} for an invalid config, expected 2"
        assert not os.path.exists(lock_path), "Worker created crash.lock despite an invalid config"

        # First valid run must create the lock and report the transient failure.
        with open(config_path, "w") as f:
            f.write("TOKEN=ZGVwbG95X3NlY3JldA==\n")
        remove_path(lock_path)
        result = run([binary])
        assert result.returncode == 1, f"First valid worker run returned {result.returncode}, expected 1"
        assert result.stdout == "CRASHING\n", f"First valid worker run printed {result.stdout!r}"
        assert os.path.isfile(lock_path), "First valid worker run did not create crash.lock"

        # A subsequent run must detect the existing lock and succeed.
        result = run([binary])
        assert result.returncode == 0, f"Second valid worker run returned {result.returncode}, expected 0"
        assert result.stdout == "SUCCESS\n", f"Second valid worker run printed {result.stdout!r}"
    finally:
        restore(config_path, config_backup)
        restore(lock_path, lock_backup)


def test_rust_source_compiles_and_worker_behaves():
    source = "/home/user/worker.rs"
    installed = "/home/user/worker"
    assert os.path.isfile(source), f"Rust source {source} does not exist"
    assert stat.S_ISREG(os.lstat(source).st_mode), f"{source} is not a regular file"
    assert stat.S_ISREG(os.lstat(installed).st_mode), f"{installed} is not a regular file"
    with open(installed, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{installed} is not a compiled native executable"

    build_dir = tempfile.mkdtemp(prefix="verify-rust-")
    rebuilt = os.path.join(build_dir, "worker")
    try:
        result = run(["rustc", source, "--crate-name", "worker", "-o", rebuilt], timeout=30)
        assert result.returncode == 0, f"worker.rs does not compile: {result.stderr}"
        exercise_worker(rebuilt)
        exercise_worker(installed)
    finally:
        remove_path(rebuilt)
        os.rmdir(build_dir)


def test_supervisor_executes_worker_loops_and_logs_actual_codes():
    supervisor = "/home/user/supervisor.sh"
    worker = "/home/user/worker"
    log = "/home/user/supervisor.log"
    assert stat.S_ISREG(os.lstat(supervisor).st_mode), f"{supervisor} is not a regular file"

    worker_backup = stash(worker)
    log_backup = stash(log)
    counter = f"/tmp/worker-counter-{uuid.uuid4().hex}"
    try:
        stub = f'''#!/bin/bash
if [ ! -e {counter!r} ]; then
    printf 1 > {counter!r}
    exit 7
fi
exit 0
'''
        with open(worker, "w") as f:
            f.write(stub)
        os.chmod(worker, 0o700)

        result = run([supervisor], timeout=10)
        assert result.returncode == 0, f"Supervisor did not terminate cleanly: stdout={result.stdout!r}, stderr={result.stderr!r}"
        assert os.path.isfile(counter), "Supervisor did not execute /home/user/worker"
        assert os.path.isfile(log), "Supervisor did not create supervisor.log"
        with open(log, "r") as f:
            lines = [line.strip() for line in f if line.strip()]
        assert lines == ["Worker exited with 7", "Worker exited with 0"], f"Supervisor did not loop and log actual exit codes: {lines}"
    finally:
        remove_path(counter)
        restore(worker, worker_backup)
        restore(log, log_backup)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
