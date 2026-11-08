#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import shlex
import subprocess
import tempfile
from pathlib import Path

EXE = "/home/user/quota_check"
SOURCE = "/home/user/quota_check.cpp"
TARGET = "/home/user/restore_target.git"
CLIENT = "/home/user/backup_client"


def run_quota(executable, directory, limit):
    return subprocess.run(
        [executable, directory, str(limit)],
        capture_output=True,
        text=True,
        timeout=10,
    )


def assert_quota_result(executable, directory, size, limit):
    result = run_quota(executable, directory, limit)
    expected_exceeded = size > limit
    assert result.returncode == (1 if expected_exceeded else 0), (
        f"Incorrect status for recursive size {size} and quota {limit}: "
        f"status={result.returncode}, stdout={result.stdout!r}, stderr={result.stderr!r}"
    )
    expected_output = "QUOTA EXCEEDED" if expected_exceeded else "OK"
    assert result.stdout.strip() == expected_output, (
        f"Expected {expected_output!r}, got {result.stdout!r}"
    )


def exercise_quota(executable):
    for _ in range(4):
        with tempfile.TemporaryDirectory() as tmpdir:
            root = Path(tmpdir)
            directories = [
                root,
                root / ("nested_" + secrets.token_hex(4)),
                root / ("nested_" + secrets.token_hex(4)) / ("deep_" + secrets.token_hex(4)),
            ]
            for directory in directories:
                directory.mkdir(parents=True, exist_ok=True)

            expected_size = 0
            for index in range(7):
                size = 1000 + secrets.randbelow(240000)
                directory = directories[secrets.randbelow(len(directories))]
                path = directory / f"file {index}_{secrets.token_hex(5)}.dat"
                with open(path, "wb") as stream:
                    stream.write(os.urandom(size))
                expected_size += size

            # The exact boundary is allowed; one byte below it is not.
            assert_quota_result(executable, tmpdir, expected_size, expected_size)
            assert_quota_result(executable, tmpdir, expected_size, expected_size - 1)
            assert_quota_result(
                executable,
                tmpdir,
                expected_size,
                expected_size + 1 + secrets.randbelow(200000),
            )

            # Confirm that results are recalculated after a nested file is added.
            added_size = 50000 + secrets.randbelow(150000)
            with open(directories[-1] / ("later_" + secrets.token_hex(5)), "wb") as stream:
                stream.write(os.urandom(added_size))
            expected_size += added_size
            assert_quota_result(executable, tmpdir, expected_size, expected_size - 1)


def test_quota_check_executable_and_source():
    assert os.path.isfile(EXE), f"{EXE} does not exist."
    assert os.access(EXE, os.X_OK), f"{EXE} is not executable."
    assert os.path.isfile(SOURCE), f"{SOURCE} does not exist."

    with open(EXE, "rb") as stream:
        assert stream.read(4) == b"\x7fELF", f"{EXE} is not a compiled executable."

    exercise_quota(EXE)

    # The submitted source must compile as C++17 and independently implement
    # the same recursive behavior.
    with tempfile.TemporaryDirectory() as builddir:
        rebuilt = os.path.join(builddir, "quota_check_rebuilt")
        compile_result = subprocess.run(
            ["g++", "-std=c++17", SOURCE, "-o", rebuilt],
            capture_output=True,
            text=True,
            timeout=30,
        )
        assert compile_result.returncode == 0, (
            f"quota_check.cpp does not compile with C++17: {compile_result.stderr}"
        )
        exercise_quota(rebuilt)

    with tempfile.TemporaryDirectory() as tmpdir:
        invalid_commands = [
            [EXE],
            [EXE, tmpdir],
            [EXE, tmpdir, "100", "extra"],
        ]
        for command in invalid_commands:
            result = subprocess.run(command, capture_output=True, text=True, timeout=10)
            assert result.returncode != 0, f"Accepted invalid argument count: {command}"


def test_git_restore_target():
    assert os.path.isdir(TARGET), f"{TARGET} does not exist."
    assert os.path.isfile(os.path.join(TARGET, "config")), f"{TARGET} does not look like a git repository."
    result = subprocess.run(
        ["git", "rev-parse", "--is-bare-repository"],
        cwd=TARGET,
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0
    assert result.stdout.strip() == "true", f"{TARGET} is not a bare repository."


def test_pre_receive_hook_invocation_and_rejection():
    hook = os.path.join(TARGET, "hooks", "pre-receive")
    assert os.path.isfile(hook), f"{hook} does not exist."
    assert os.access(hook, os.X_OK), f"{hook} is not executable."

    token = secrets.token_hex(16)
    record = f"/tmp/quota_invocation_{token}"
    saved_exe = f"/tmp/quota_check_saved_{token}"
    os.replace(EXE, saved_exe)
    try:
        wrapper = (
            "#!/bin/sh\n"
            f"printf '%s\\n' {shlex.quote(token)} > {shlex.quote(record)}\n"
            f"printf '%s\\n' \"$#\" \"$1\" \"$2\" >> {shlex.quote(record)}\n"
            "echo 'QUOTA EXCEEDED'\n"
            "exit 1\n"
        )
        with open(EXE, "w") as stream:
            stream.write(wrapper)
        os.chmod(EXE, 0o755)

        with tempfile.TemporaryDirectory() as client:
            subprocess.run(["git", "init", "-q", "-b", "master"], cwd=client, check=True)
            subprocess.run(["git", "config", "user.name", "Verifier"], cwd=client, check=True)
            subprocess.run(["git", "config", "user.email", "verifier@example.invalid"], cwd=client, check=True)
            Path(client, "probe.txt").write_text(token)
            subprocess.run(["git", "add", "probe.txt"], cwd=client, check=True)
            subprocess.run(["git", "commit", "-q", "-m", "hook probe"], cwd=client, check=True)
            ref = "refs/heads/audit_" + token
            pushed = subprocess.run(
                ["git", "push", TARGET, f"HEAD:{ref}"],
                cwd=client,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                timeout=30,
            )
            assert pushed.returncode != 0, "The pre-receive hook did not reject a failing quota check."
            assert "QUOTA EXCEEDED" in pushed.stdout, pushed.stdout

        assert os.path.isfile(record), "The hook did not execute /home/user/quota_check."
        with open(record) as stream:
            invocation = stream.read().splitlines()
        assert invocation == [token, "2", TARGET, "5000000"], (
            f"Hook used incorrect quota_check arguments: {invocation}"
        )
        absent = subprocess.run(
            ["git", "show-ref", "--verify", "--quiet", ref], cwd=TARGET
        )
        assert absent.returncode != 0, "A ref was created despite hook rejection."
    finally:
        if os.path.lexists(EXE):
            os.unlink(EXE)
        os.replace(saved_exe, EXE)
        if os.path.exists(record):
            os.unlink(record)


def test_socat_port_forwarding():
    pid_file = "/home/user/socat.pid"
    assert os.path.isfile(pid_file), f"{pid_file} does not exist."
    with open(pid_file) as stream:
        pid_str = stream.read().strip()
    assert pid_str.isdigit(), f"PID file {pid_file} does not contain a valid integer."
    pid = int(pid_str)
    assert os.path.isdir(f"/proc/{pid}"), f"Process with PID {pid} is not running."
    with open(f"/proc/{pid}/cmdline", "rb") as stream:
        cmdline = stream.read().replace(b"\0", b" ").decode(errors="replace").strip()
    assert "socat" in cmdline, f"Process {pid} is not socat. Cmdline: {cmdline}"
    assert "18080" in cmdline, f"socat is not listening on port 18080. Cmdline: {cmdline}"
    assert "19090" in cmdline, f"socat is not forwarding to 19090. Cmdline: {cmdline}"


def test_backup_client_repo_commit_remote_and_real_failed_push():
    assert os.path.isdir(CLIENT), f"{CLIENT} does not exist."
    assert os.path.isdir(os.path.join(CLIENT, ".git")), f"{CLIENT} is not a git repository."

    payload = os.path.join(CLIENT, "payload.dat")
    assert os.path.isfile(payload), f"{payload} does not exist."
    size = os.path.getsize(payload)
    assert size > 5000000, f"{payload} is too small to trigger the quota."

    branch = subprocess.run(
        ["git", "branch", "--show-current"], cwd=CLIENT, capture_output=True, text=True, check=True
    ).stdout.strip()
    assert branch == "master", f"Expected checked-out branch master, got {branch!r}."

    head = subprocess.run(
        ["git", "rev-parse", "HEAD"], cwd=CLIENT, capture_output=True, text=True, check=True
    ).stdout.strip()
    master = subprocess.run(
        ["git", "rev-parse", "refs/heads/master"], cwd=CLIENT, capture_output=True, text=True, check=True
    ).stdout.strip()
    assert head == master, "The payload commit is not on the checked-out master branch."

    committed_size = subprocess.run(
        ["git", "cat-file", "-s", "HEAD:payload.dat"],
        cwd=CLIENT,
        capture_output=True,
        text=True,
        check=True,
    ).stdout.strip()
    assert int(committed_size) == size, "payload.dat is not committed at its required size."
    status = subprocess.run(
        ["git", "status", "--porcelain", "--", "payload.dat"],
        cwd=CLIENT,
        capture_output=True,
        text=True,
        check=True,
    )
    assert status.stdout.strip() == "", "The working payload differs from the committed payload."

    remotes = subprocess.run(
        ["git", "remote"], cwd=CLIENT, capture_output=True, text=True, check=True
    ).stdout.split()
    assert "origin" in remotes, "Remote origin is missing."
    origin = subprocess.run(
        ["git", "remote", "get-url", "origin"], cwd=CLIENT, capture_output=True, text=True, check=True
    ).stdout.strip()
    assert origin == TARGET, f"origin points to {origin!r}, not {TARGET!r}."

    existing = subprocess.run(
        ["git", "show-ref", "--verify", "--quiet", "refs/heads/master"], cwd=TARGET
    )
    assert existing.returncode != 0, "The supposedly rejected master push is present in the destination."

    # Perform the required push ourselves so the log can only pass if a real
    # receive attempt invokes the real hook and is rejected for quota.
    pushed = subprocess.run(
        ["git", "push", "origin", "master"],
        cwd=CLIENT,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=60,
    )
    with open("/home/user/push_failed.log", "w") as stream:
        stream.write(pushed.stdout)
    assert pushed.returncode != 0, "The oversized master push unexpectedly succeeded."
    assert "QUOTA EXCEEDED" in pushed.stdout, (
        f"The push was not rejected with quota hook output: {pushed.stdout}"
    )
    still_absent = subprocess.run(
        ["git", "show-ref", "--verify", "--quiet", "refs/heads/master"], cwd=TARGET
    )
    assert still_absent.returncode != 0, "The rejected push created refs/heads/master."


def test_push_failed_log():
    log_path = "/home/user/push_failed.log"
    assert os.path.isfile(log_path), f"{log_path} does not exist."
    with open(log_path) as stream:
        log_content = stream.read()
    assert "QUOTA EXCEEDED" in log_content, f"'QUOTA EXCEEDED' not found in {log_path}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
