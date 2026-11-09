#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import shutil
import socket
import stat
import subprocess
import tempfile
import time
import uuid

SOURCE = "/home/user/check_port.c"
EXECUTABLE = "/home/user/check_port"
REPO = "/home/user/monitor_repo"
HOOK = os.path.join(REPO, ".git/hooks/post-commit")
LOG = os.path.join(REPO, "net_log.txt")
BACKUP = os.path.join(REPO, "net_log.bak")


def stop_port_8080():
    try:
        subprocess.run(["fuser", "-k", "8080/tcp"], capture_output=True, timeout=5)
    except (FileNotFoundError, subprocess.TimeoutExpired):
        pass
    time.sleep(0.15)


def start_server():
    code = r'''
import socket
s = socket.socket()
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(("127.0.0.1", 8080))
s.listen(20)
print("READY", flush=True)
while True:
    c, _ = s.accept()
    c.close()
'''
    proc = subprocess.Popen(
        ["python3", "-c", code], stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, text=True
    )
    assert proc.stdout.readline().strip() == "READY", "Test server failed to start"
    return proc


def run_checker(path, expected):
    result = subprocess.run([path], capture_output=True, text=True, timeout=5)
    assert result.stdout == expected, (
        f"Expected {expected!r} from {path}, got {result.stdout!r}"
    )


def exercise_checker(path):
    # Runtime-randomized ordering prevents a fixed invocation sequence from passing.
    states = [False, False, False, True, True, True]
    random.SystemRandom().shuffle(states)
    server = None
    try:
        stop_port_8080()
        for listening in states:
            if server is not None:
                server.terminate()
                server.wait(timeout=5)
                server = None
                time.sleep(0.15)
            stop_port_8080()
            if listening:
                server = start_server()
            run_checker(path, "STATUS: OK\n" if listening else "STATUS: FAIL\n")
    finally:
        if server is not None:
            server.terminate()
            server.wait(timeout=5)
        stop_port_8080()


def make_commit(prefix):
    filename = f"{prefix}_{uuid.uuid4().hex}"
    with open(os.path.join(REPO, filename), "w") as f:
        f.write(uuid.uuid4().hex)
    subprocess.run(["git", "add", filename], cwd=REPO, check=True, capture_output=True)
    subprocess.run(
        ["git", "-c", "user.name=Test", "-c", "user.email=test@example.com",
         "commit", "-m", f"Add {filename}"],
        cwd=REPO, check=True, capture_output=True
    )


def clean_logs():
    for path in (LOG, BACKUP):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass


def read_lines(path):
    with open(path, "r") as f:
        return f.readlines()


def test_check_port_exists_and_executable():
    assert os.path.exists(SOURCE), f"{SOURCE} does not exist."
    assert os.path.isfile(SOURCE), f"{SOURCE} is not a regular file."
    assert os.path.exists(EXECUTABLE), f"{EXECUTABLE} does not exist."
    assert os.path.isfile(EXECUTABLE), f"{EXECUTABLE} is not a regular file."
    assert os.access(EXECUTABLE, os.X_OK), f"{EXECUTABLE} is not executable."
    with open(EXECUTABLE, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{EXECUTABLE} is not a compiled ELF executable."


def test_source_compiles_and_both_artifacts_behave():
    fd, rebuilt = tempfile.mkstemp(prefix="rebuilt_check_port_", dir="/tmp")
    os.close(fd)
    os.remove(rebuilt)
    try:
        result = subprocess.run(
            ["gcc", "-std=c11", "-Wall", "-Wextra", SOURCE, "-o", rebuilt],
            capture_output=True, text=True, timeout=20
        )
        assert result.returncode == 0, f"check_port.c did not compile:\n{result.stderr}"
        assert os.access(rebuilt, os.X_OK), "Rebuilt C executable is not executable"
        exercise_checker(rebuilt)
        exercise_checker(EXECUTABLE)
    finally:
        try:
            os.remove(rebuilt)
        except FileNotFoundError:
            pass


def test_check_port_behavior_original_sequence():
    stop_port_8080()
    run_checker(EXECUTABLE, "STATUS: FAIL\n")
    server = start_server()
    try:
        run_checker(EXECUTABLE, "STATUS: OK\n")
    finally:
        server.terminate()
        server.wait(timeout=5)
        stop_port_8080()


def test_git_repo_and_hook_exist():
    assert os.path.exists(os.path.join(REPO, ".git")), f"Git repository not initialized at {REPO}"
    assert os.path.exists(HOOK), f"post-commit hook not found at {HOOK}"
    assert os.access(HOOK, os.X_OK), "post-commit hook is not executable"
    result = subprocess.run(
        ["git", "rev-parse", "--is-inside-work-tree"], cwd=REPO,
        capture_output=True, text=True
    )
    assert result.returncode == 0 and result.stdout.strip() == "true"


def test_git_hook_behavior_original_fail_rotation():
    clean_logs()
    stop_port_8080()

    make_commit("verifier_fail_1")
    assert os.path.exists(LOG), "net_log.txt was not created after commit."
    assert read_lines(LOG) == ["STATUS: FAIL\n"]

    make_commit("verifier_fail_2")
    assert read_lines(LOG) == ["STATUS: FAIL\n", "STATUS: FAIL\n"]

    make_commit("verifier_fail_3")
    assert os.path.exists(LOG), "net_log.txt should exist after the third commit."
    assert read_lines(LOG) == [], "net_log.txt should be empty after the third commit."
    assert os.path.exists(BACKUP), "net_log.bak was not created after the third commit."
    assert read_lines(BACKUP) == ["STATUS: FAIL\n"] * 3

    make_commit("verifier_fail_4")
    assert read_lines(LOG) == ["STATUS: FAIL\n"]
    assert read_lines(BACKUP) == ["STATUS: FAIL\n"] * 3


def test_hook_really_invokes_absolute_checker_and_appends_its_output():
    saved = f"/tmp/check_port_saved_{uuid.uuid4().hex}"
    marker = f"/tmp/check_port_marker_{uuid.uuid4().hex}"
    shutil.copy2(EXECUTABLE, saved)
    probe = f'''#!/bin/sh
value=$(/usr/bin/python3 -c 'import secrets; print("PROBE-" + secrets.token_hex(16))')
printf '%s\\n' "$value" >> {marker}
printf '%s\\n' "$value"
'''
    try:
        with open(EXECUTABLE, "w") as f:
            f.write(probe)
        os.chmod(EXECUTABLE, 0o755)
        clean_logs()

        seen = []
        for i in range(4):
            before = read_lines(marker) if os.path.exists(marker) else []
            make_commit(f"verifier_probe_{i}")
            after = read_lines(marker)
            assert len(after) == len(before) + 1, (
                "Each commit must invoke /home/user/check_port exactly once"
            )
            seen.append(after[-1])
            if i == 0:
                assert read_lines(LOG) == seen
            elif i == 1:
                assert read_lines(LOG) == seen
            elif i == 2:
                assert read_lines(LOG) == []
                assert read_lines(BACKUP) == seen
            else:
                assert read_lines(LOG) == [seen[3]]
                assert read_lines(BACKUP) == seen[:3]

        # Run from an unrelated directory to verify that checker and log paths
        # do not depend on the hook's working directory.
        clean_logs()
        if os.path.exists(marker):
            os.remove(marker)
        stray = "/tmp/net_log.txt"
        try:
            os.remove(stray)
        except FileNotFoundError:
            pass
        subprocess.run([HOOK], cwd="/tmp", check=True, capture_output=True, timeout=10)
        invoked = read_lines(marker)
        assert len(invoked) == 1, "Hook did not invoke the absolute checker path"
        assert read_lines(LOG) == invoked, "Hook did not append checker output to the absolute log path"
        assert not os.path.exists(stray), "Hook wrote a log relative to its working directory"
    finally:
        shutil.copy2(saved, EXECUTABLE)
        os.chmod(EXECUTABLE, 0o755)
        for path in (saved, marker):
            try:
                os.remove(path)
            except FileNotFoundError:
                pass
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
