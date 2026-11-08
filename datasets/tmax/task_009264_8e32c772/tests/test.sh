#!/bin/bash
set -e
mkdir -p /logs/verifier
reward=0
trap 'echo "$reward" > /logs/verifier/reward.txt' EXIT

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import shutil
import stat
import subprocess
import time
import pytest

REPO = "/home/user/repo"
SOURCE = f"{REPO}/server.c"
RUN_DIR = "/home/user/run"
PID_FILE = f"{RUN_DIR}/server.pid"


def test_git_commit_message():
    result = subprocess.run(
        ["git", "-C", REPO, "log", "-1", "--pretty=%B"],
        capture_output=True, text=True
    )
    assert result.returncode == 0, "Failed to execute git log."
    assert result.stdout.strip() == "Fix PID directory", (
        "The latest commit message must be exactly 'Fix PID directory'."
    )


def test_server_change_is_committed():
    result = subprocess.run(
        ["git", "-C", REPO, "show", "--format=", "--name-only", "HEAD"],
        capture_output=True, text=True
    )
    assert result.returncode == 0, "Failed to inspect the latest commit."
    changed = {line.strip() for line in result.stdout.splitlines() if line.strip()}
    assert "server.c" in changed, "The latest commit does not include server.c."

    result = subprocess.run(
        ["git", "-C", REPO, "diff", "--quiet", "HEAD", "--", "server.c"]
    )
    assert result.returncode == 0, "The current server.c change is not committed."


def test_server_source_uses_required_api_before_pid_open():
    with open(SOURCE, "r") as f:
        source = f.read()

    assert re.search(r"^\s*#\s*include\s*<\s*sys/stat\.h\s*>", source, re.MULTILINE), (
        "server.c must include <sys/stat.h>."
    )

    # Remove comments so mentions in comments cannot satisfy the source check.
    code = re.sub(r"/\*.*?\*/", "", source, flags=re.DOTALL)
    code = re.sub(r"//[^\n]*", "", code)
    mkdir_call = re.search(r"\bmkdir\s*\(", code)
    pid_open = re.search(r"\bfopen\s*\(\s*\"/home/user/run/server\.pid\"", code)
    assert mkdir_call is not None, "server.c does not call mkdir()."
    assert pid_open is not None, "server.c does not open the required PID file."
    assert mkdir_call.start() < pid_open.start(), (
        "mkdir() must be called before opening /home/user/run/server.pid."
    )


def test_program_itself_creates_run_directory_with_mkdir():
    executable = f"/tmp/submission_server_verify_{os.getpid()}"
    interceptor_c = f"/tmp/mkdir_interceptor_{os.getpid()}.c"
    interceptor_so = f"/tmp/mkdir_interceptor_{os.getpid()}.so"
    marker = f"/tmp/mkdir_marker_{os.getpid()}"
    backup = f"/home/user/run.verifier-backup-{os.getpid()}"

    interceptor_source = r'''
#define _GNU_SOURCE
#include <sys/types.h>
#include <sys/stat.h>
#include <dlfcn.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

int mkdir(const char *path, mode_t mode) {
    static int (*real_mkdir)(const char *, mode_t) = NULL;
    if (!real_mkdir)
        real_mkdir = dlsym(RTLD_NEXT, "mkdir");
    if (path && strcmp(path, "/home/user/run") == 0 && (mode & 07777) == 0755) {
        int fd = open("@MARKER@", O_WRONLY | O_CREAT | O_TRUNC, 0666);
        if (fd >= 0) {
            dprintf(fd, "%d\n", getpid());
            close(fd);
        }
    }
    return real_mkdir(path, mode);
}
'''.replace("@MARKER@", marker)

    process = None
    moved_original = False
    try:
        with open(interceptor_c, "w") as f:
            f.write(interceptor_source)

        compile_server = subprocess.run(
            ["gcc", SOURCE, "-o", executable], capture_output=True, text=True
        )
        assert compile_server.returncode == 0, (
            f"server.c failed to compile: {compile_server.stderr}"
        )
        compile_interceptor = subprocess.run(
            ["gcc", "-shared", "-fPIC", interceptor_c, "-o", interceptor_so, "-ldl"],
            capture_output=True, text=True
        )
        assert compile_interceptor.returncode == 0, (
            f"Failed to build mkdir verifier: {compile_interceptor.stderr}"
        )

        assert not os.path.exists(backup), f"Unexpected verifier backup path: {backup}"
        if os.path.exists(RUN_DIR):
            os.rename(RUN_DIR, backup)
            moved_original = True

        env = os.environ.copy()
        env["LD_PRELOAD"] = interceptor_so

        def zero_umask():
            os.umask(0)

        process = subprocess.Popen(
            [executable], env=env, stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL, preexec_fn=zero_umask
        )

        deadline = time.time() + 5
        while time.time() < deadline:
            if os.path.isfile(marker) and os.path.isfile(PID_FILE):
                break
            if process.poll() is not None:
                break
            time.sleep(0.05)

        assert process.poll() is None, "The submitted server exited during execution."
        assert os.path.isfile(marker), (
            "The running server did not call mkdir('/home/user/run', 0755)."
        )
        with open(marker, "r") as f:
            mkdir_pid = f.read().strip()
        assert mkdir_pid == str(process.pid), (
            "The required mkdir call was not made by the submitted server process."
        )
        assert os.path.isdir(RUN_DIR), "Executing server.c did not create /home/user/run."
        assert stat.S_IMODE(os.stat(RUN_DIR).st_mode) == 0o755, (
            "The program-created /home/user/run directory does not have mode 0755."
        )
        assert os.path.isfile(PID_FILE), "The executed server did not create server.pid."
        with open(PID_FILE, "r") as f:
            assert f.read().strip() == str(process.pid), (
                "The executed server did not write its own PID to server.pid."
            )
    finally:
        if process is not None and process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=2)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=2)
        if os.path.isdir(RUN_DIR):
            shutil.rmtree(RUN_DIR)
        elif os.path.exists(RUN_DIR):
            os.unlink(RUN_DIR)
        if moved_original and os.path.exists(backup):
            os.rename(backup, RUN_DIR)
        for path in (executable, interceptor_c, interceptor_so, marker):
            try:
                os.unlink(path)
            except FileNotFoundError:
                pass


def test_run_directory_exists_and_permissions():
    assert os.path.isdir(RUN_DIR), f"Directory {RUN_DIR} does not exist."
    st = os.stat(RUN_DIR)
    assert stat.S_IMODE(st.st_mode) == 0o755, f"Permissions of {RUN_DIR} are not 0755."


def test_server_pid_file_exists_and_valid():
    assert os.path.isfile(PID_FILE), f"PID file {PID_FILE} does not exist."
    with open(PID_FILE, "r") as f:
        content = f.read().strip()
    assert content.isdigit(), f"PID file {PID_FILE} does not contain a valid numeric PID."


def test_solution_txt_matches_pid():
    solution_file = "/home/user/solution.txt"
    assert os.path.isfile(solution_file), f"Solution file {solution_file} does not exist."
    with open(PID_FILE, "r") as f:
        expected_pid = f.read().strip()
    with open(solution_file, "r") as f:
        actual_pid = f.read().strip()
    assert actual_pid == expected_pid, (
        f"Solution file contains '{actual_pid}', but expected '{expected_pid}' from {PID_FILE}."
    )


def test_server_process_running():
    subprocess.run(
        ["pgrep", "-f", "^/home/user/repo/server$"],
        capture_output=True, text=True
    )
    if os.path.isfile(PID_FILE):
        with open(PID_FILE, "r") as f:
            pid = f.read().strip()
        if pid.isdigit():
            assert os.path.isdir(f"/proc/{pid}"), f"Process with PID {pid} is not running."
            with open(f"/proc/{pid}/cmdline", "r") as f:
                cmdline = f.read().replace('\x00', ' ').strip()
            assert "/home/user/repo/server" in cmdline, (
                f"Process {pid} is not the server. Cmdline: {cmdline}"
            )
        else:
            pytest.fail("PID file does not contain a numeric PID.")
    else:
        pytest.fail("Cannot verify running process because PID file is missing.")
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    reward=1
fi
