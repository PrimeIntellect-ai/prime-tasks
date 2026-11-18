#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import shutil
import signal
import subprocess
import tempfile
import uuid

import pytest

SUPERVISOR = "/home/user/supervisor"
SOURCE = "/home/user/supervisor.c"
RESTART = "[Supervisor] Restarting...\n"


def test_fstab_conf():
    path = "/home/user/fstab.conf"
    assert os.path.isfile(path), f"{path} is missing."
    with open(path, "r") as f:
        content = f.read().strip()

    expected_lines = [
        "/home/user/data_source /home/user/data_dest",
        "/home/user/log_source /home/user/log_dest"
    ]
    for line in expected_lines:
        assert line in content, f"Expected line '{line}' not found in {path}."


def test_symlinks_and_directories():
    dirs = [
        "/home/user/data_source",
        "/home/user/data_dest",
        "/home/user/log_source",
        "/home/user/log_dest"
    ]
    for d in dirs:
        assert os.path.isdir(d), f"Directory {d} does not exist."

    links = {
        "/home/user/data_dest/mnt": "/home/user/data_source",
        "/home/user/log_dest/mnt": "/home/user/log_source"
    }
    for link_path, target in links.items():
        assert os.path.islink(link_path), f"{link_path} is not a symlink."
        actual_target = os.readlink(link_path)
        assert actual_target == target, f"Symlink {link_path} points to {actual_target}, expected {target}."


def test_setup_mounts_idempotency():
    script_path = "/home/user/setup_mounts.sh"
    assert os.path.isfile(script_path), f"{script_path} is missing."
    assert os.access(script_path, os.X_OK), f"{script_path} is not executable."

    result = subprocess.run([script_path], capture_output=True, text=True, timeout=10)
    assert result.returncode == 0, f"{script_path} failed on second run. Not idempotent. Stderr: {result.stderr}"

    links = {
        "/home/user/data_dest/mnt": "/home/user/data_source",
        "/home/user/log_dest/mnt": "/home/user/log_source"
    }
    for link_path, target in links.items():
        assert os.path.islink(link_path), f"{link_path} is no longer a symlink after second run."
        actual_target = os.readlink(link_path)
        assert actual_target == target, f"Symlink {link_path} points to {actual_target} after second run, expected {target}."


def test_setup_mounts_reads_configuration_and_recreates_mounts():
    script_path = "/home/user/setup_mounts.sh"
    conf_path = "/home/user/fstab.conf"
    with open(conf_path, "rb") as f:
        original = f.read()

    suffix = uuid.uuid4().hex
    source = f"/home/user/test_source_{suffix}"
    dest = f"/home/user/test_dest_{suffix}"
    try:
        with open(conf_path, "ab") as f:
            if original and not original.endswith(b"\n"):
                f.write(b"\n")
            f.write(f"{source} {dest}\n".encode())

        result = subprocess.run([script_path], capture_output=True, text=True, timeout=10)
        assert result.returncode == 0, f"Mount script failed for a configured entry: {result.stderr}"
        assert os.path.isdir(source)
        assert os.path.isdir(dest)
        assert os.path.islink(os.path.join(dest, "mnt"))
        assert os.readlink(os.path.join(dest, "mnt")) == source
    finally:
        with open(conf_path, "wb") as f:
            f.write(original)
        shutil.rmtree(dest, ignore_errors=True)
        shutil.rmtree(source, ignore_errors=True)

    for path in ["/home/user/data_dest", "/home/user/data_source", "/home/user/log_dest", "/home/user/log_source"]:
        shutil.rmtree(path, ignore_errors=True)

    result = subprocess.run([script_path], capture_output=True, text=True, timeout=10)
    assert result.returncode == 0, f"Mount script could not recreate missing mounts: {result.stderr}"
    for link_path, target in {
        "/home/user/data_dest/mnt": "/home/user/data_source",
        "/home/user/log_dest/mnt": "/home/user/log_source"
    }.items():
        assert os.path.isdir(target)
        assert os.path.islink(link_path)
        assert os.readlink(link_path) == target

    result = subprocess.run([script_path], capture_output=True, text=True, timeout=10)
    assert result.returncode == 0, f"Mount script is not idempotent after recreation: {result.stderr}"


def test_supervisor_compiled():
    assert os.path.isfile(SOURCE), f"{SOURCE} is missing."
    assert os.path.isfile(SUPERVISOR), f"{SUPERVISOR} is missing."
    assert os.access(SUPERVISOR, os.X_OK), f"{SUPERVISOR} is not executable."
    with open(SUPERVISOR, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{SUPERVISOR} is not a compiled ELF executable."


@pytest.fixture(scope="session")
def supervisor_binaries():
    build_dir = tempfile.mkdtemp(prefix="supervisor-build-")
    rebuilt = os.path.join(build_dir, "supervisor-from-source")
    result = subprocess.run(
        ["gcc", "-std=c11", "-Wall", "-Wextra", SOURCE, "-o", rebuilt],
        capture_output=True,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, f"supervisor.c does not compile:\n{result.stderr}"
    yield [SUPERVISOR, rebuilt]
    shutil.rmtree(build_dir, ignore_errors=True)


def run_case(binary, max_retries, failures_before_success):
    case_dir = tempfile.mkdtemp(prefix="supervisor-case-")
    records = os.path.join(case_dir, "records.jsonl")
    helper = os.path.join(case_dir, "service.py")
    token = uuid.uuid4().hex
    fail_code = random.SystemRandom().randint(2, 125)
    helper_source = f'''#!/usr/bin/env python3
import json
import os
import sys
records = {records!r}
try:
    with open(records, "r") as f:
        invocation = sum(1 for _ in f) + 1
except FileNotFoundError:
    invocation = 1
with open(records, "a") as f:
    f.write(json.dumps({{"invocation": invocation, "args": sys.argv[1:], "ppid": os.getppid()}}) + "\\n")
print({token!r} + ":" + str(invocation), flush=True)
if invocation <= {failures_before_success}:
    sys.exit({fail_code})
sys.exit(0)
'''
    with open(helper, "w") as f:
        f.write(helper_source)
    os.chmod(helper, 0o755)

    args = [token, "argument with spaces", "--value=17"]
    proc = subprocess.Popen(
        [binary, str(max_retries), helper] + args,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        start_new_session=True,
    )
    try:
        stdout, stderr = proc.communicate(timeout=8)
    except subprocess.TimeoutExpired:
        os.killpg(proc.pid, signal.SIGKILL)
        proc.communicate()
        pytest.fail(f"{binary} hung while supervising a child")

    expected_executions = min(failures_before_success + 1, max_retries + 1)
    expected_stdout = ""
    for invocation in range(1, expected_executions + 1):
        expected_stdout += f"{token}:{invocation}\n"
        if invocation <= failures_before_success and invocation <= max_retries:
            expected_stdout += RESTART

    expected_status = 0 if failures_before_success <= max_retries else 1
    assert proc.returncode == expected_status, (
        f"{binary} returned {proc.returncode}; expected {expected_status}. stderr: {stderr}"
    )
    assert stdout == expected_stdout, f"Unexpected supervisor stdout.\nExpected:\n{expected_stdout!r}\nActual:\n{stdout!r}"
    assert stderr == "", f"Unexpected supervisor stderr: {stderr!r}"

    with open(records, "r") as f:
        observations = [json.loads(line) for line in f]
    assert len(observations) == expected_executions
    assert [x["invocation"] for x in observations] == list(range(1, expected_executions + 1))
    assert all(x["args"] == args for x in observations), "execvp did not preserve child arguments"
    assert all(x["ppid"] == proc.pid for x in observations), "Service was not directly forked/executed by the supervisor"
    shutil.rmtree(case_dir, ignore_errors=True)


def test_supervisor_success_retry_and_failure_behavior(supervisor_binaries):
    rng = random.SystemRandom()
    for binary in supervisor_binaries:
        run_case(binary, rng.randint(2, 4), 0)

        retries = rng.randint(3, 5)
        eventual_failures = rng.randint(1, retries - 1)
        run_case(binary, retries, eventual_failures)

        retries = rng.randint(2, 4)
        run_case(binary, retries, retries + 20)


def test_failing_service_script():
    script_path = "/home/user/failing_service.sh"
    assert os.path.isfile(script_path), f"{script_path} is missing."
    assert os.access(script_path, os.X_OK), f"{script_path} is not executable."
    with open(script_path, "rb") as f:
        assert f.read() == b'#!/bin/bash\necho "Running service..."\nexit 2\n'


def test_migration_result():
    log_path = "/home/user/migration_result.log"
    assert os.path.isfile(log_path), f"{log_path} is missing."

    expected_output = (
        "Running service...\n"
        "[Supervisor] Restarting...\n"
        "Running service...\n"
        "[Supervisor] Restarting...\n"
        "Running service...\n"
        "[Supervisor] Restarting...\n"
        "Running service..."
    )

    with open(log_path, "r") as f:
        content = f.read().strip()
    assert content == expected_output, f"Contents of {log_path} do not match expected output.\nExpected:\n{expected_output}\nActual:\n{content}"

    with open(log_path, "w") as log:
        result = subprocess.run(
            [SUPERVISOR, "3", "/home/user/failing_service.sh"],
            cwd="/home/user",
            stdout=log,
            stderr=subprocess.STDOUT,
            timeout=10,
        )
    assert result.returncode == 1, f"Supervisor returned {result.returncode} for the failing service, expected 1."
    with open(log_path, "r") as f:
        actual = f.read().strip()
    assert actual == expected_output, f"Executing the deployment produced unexpected output.\nExpected:\n{expected_output}\nActual:\n{actual}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
