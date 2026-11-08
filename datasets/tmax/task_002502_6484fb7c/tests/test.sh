#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import stat
import subprocess
import tempfile
import time
import urllib.request
import uuid

import pytest

BINARY = "/home/user/bin/cap-analyzer"
SOURCE_DIR = "/app/cap-analyzer"
BARE_REPO = "/home/user/repos/data-model.git"
LOG_FILE = "/home/user/logs/capacity.log"


def expected_deduplicated_size(root):
    """Mirror the requested inode-deduplicated walk independently."""
    visited = set()

    def walk(path):
        try:
            info = os.lstat(path)
        except OSError:
            return 0

        inode = (info.st_dev, info.st_ino)
        if inode in visited:
            return 0
        visited.add(inode)

        total = 0 if stat.S_ISDIR(info.st_mode) else info.st_size

        if stat.S_ISLNK(info.st_mode):
            try:
                return total + walk(os.path.realpath(path))
            except OSError:
                return total

        if stat.S_ISDIR(info.st_mode):
            try:
                children = sorted(os.listdir(path))
            except OSError:
                return total
            for child in children:
                total += walk(os.path.join(path, child))

        return total

    return walk(root)


def run_analyzer(binary, target, timeout=2.0):
    start = time.monotonic()
    try:
        result = subprocess.run(
            [binary, "--target", target],
            capture_output=True,
            text=True,
            timeout=timeout,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("cap-analyzer timed out; cyclic symlink traversal was not fixed")

    elapsed = time.monotonic() - start
    assert result.returncode == 0, f"cap-analyzer failed: {result.stderr}"
    output = result.stdout.strip()
    assert re.fullmatch(r"[0-9]+", output), f"invalid analyzer output: {result.stdout!r}"
    return int(output), elapsed


def parse_log_line(line):
    match = re.fullmatch(r"\[([^\]]+)\]\s+([0-9]+)", line)
    assert match, f"Log line format incorrect: {line}"
    assert match.group(1).strip(), f"Timestamp is empty: {line}"
    return int(match.group(2))


def test_binary_exists_and_executable():
    assert os.path.isfile(BINARY), f"Binary not found at {BINARY}"
    assert os.access(BINARY, os.X_OK), f"Binary at {BINARY} is not executable"
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", "cap-analyzer is not a compiled executable"


def test_post_receive_hook():
    hook_path = os.path.join(BARE_REPO, "hooks", "post-receive")
    assert os.path.isfile(hook_path), f"post-receive hook not found at {hook_path}"
    assert os.access(hook_path, os.X_OK), f"post-receive hook at {hook_path} is not executable"

    with open(hook_path, "r", errors="replace") as f:
        hook = f.read()
    assert BINARY in hook, "post-receive hook does not invoke the installed analyzer"
    assert "--target" in hook and BARE_REPO in hook, "hook does not analyze the bare repository"
    assert LOG_FILE in hook and ">>" in hook, "hook does not append analyzer output to capacity.log"


def test_http_server_running():
    log_dir = "/home/user/logs"
    os.makedirs(log_dir, exist_ok=True)
    test_file = os.path.join(log_dir, "test_server.txt")
    token = "server-is-running-" + uuid.uuid4().hex
    with open(test_file, "w") as f:
        f.write(token)

    success = False
    for _ in range(5):
        try:
            response = urllib.request.urlopen(
                "http://127.0.0.1:8080/test_server.txt", timeout=2
            )
            if response.status == 200 and response.read().decode().strip() == token:
                success = True
                break
        except Exception:
            time.sleep(1)

    assert success, "HTTP server is not running on 127.0.0.1:8080 or is not serving /home/user/logs/"


def test_analyzer_performance_and_accuracy():
    with tempfile.TemporaryDirectory() as temp_dir:
        dir1 = os.path.join(temp_dir, "dir1")
        os.makedirs(dir1)

        size1 = 1024 * 1024 + secrets.randbelow(4096) + 1
        size2 = 2 * 1024 * 1024 + secrets.randbelow(4096) + 1
        file1 = os.path.join(dir1, "file1.bin")
        file2 = os.path.join(dir1, "file2.bin")
        with open(file1, "wb") as f:
            f.write(os.urandom(size1))
        with open(file2, "wb") as f:
            f.write(os.urandom(size2))

        # A hard link must not be counted twice. The symlinks themselves are
        # filesystem entries, but their already-visited targets must be skipped.
        os.link(file1, os.path.join(dir1, "file1-hardlink.bin"))
        os.symlink(dir1, os.path.join(dir1, "cyclic_link"))
        os.symlink(file2, os.path.join(dir1, "file2_link"))

        expected = expected_deduplicated_size(temp_dir)
        actual, elapsed = run_analyzer(BINARY, temp_dir)
        assert elapsed < 1.0, f"Execution time {elapsed:.2f}s is too slow; expected < 1.0s"
        assert actual == expected, f"expected deduplicated size {expected}, got {actual}"

        # The vendored source itself must contain the fix and remain buildable.
        source_binary = os.path.join(temp_dir, "source-cap-analyzer")
        build = subprocess.run(
            ["/usr/local/go/bin/go", "build", "-o", source_binary, "."],
            cwd=SOURCE_DIR,
            capture_output=True,
            text=True,
            timeout=30,
        )
        assert build.returncode == 0, f"vendored Go package does not build: {build.stderr}"
        source_actual, _ = run_analyzer(source_binary, temp_dir)
        assert source_actual == expected, (
            f"binary built from vendored source returned {source_actual}, expected {expected}"
        )


def test_git_push_triggers_hook_with_correct_size_and_appends():
    if os.path.exists(LOG_FILE):
        os.remove(LOG_FILE)

    with tempfile.TemporaryDirectory() as clone_dir:
        subprocess.run(["git", "clone", BARE_REPO, clone_dir], check=True, capture_output=True)
        subprocess.run(["git", "config", "user.email", "test@example.com"], cwd=clone_dir, check=True)
        subprocess.run(["git", "config", "user.name", "Test User"], cwd=clone_dir, check=True)

        branch = "verifier-" + uuid.uuid4().hex
        subprocess.run(["git", "checkout", "-b", branch], cwd=clone_dir, check=True, capture_output=True)

        test_file = os.path.join(clone_dir, "data-" + uuid.uuid4().hex + ".txt")
        with open(test_file, "w") as f:
            f.write("Hello, World! " + uuid.uuid4().hex)
        subprocess.run(["git", "add", os.path.basename(test_file)], cwd=clone_dir, check=True)
        subprocess.run(["git", "commit", "-m", "Verifier initial commit"], cwd=clone_dir, check=True, capture_output=True)

        result = subprocess.run(
            ["git", "push", "origin", f"HEAD:refs/heads/{branch}"],
            cwd=clone_dir,
            capture_output=True,
            text=True,
        )
        assert result.returncode == 0, f"git push failed: {result.stderr}"
        assert os.path.exists(LOG_FILE), f"{LOG_FILE} was not created by the post-receive hook"

        with open(LOG_FILE, "r") as f:
            first_contents = f.read()
        first_lines = [line for line in first_contents.splitlines() if line.strip()]
        assert first_lines, "capacity.log is empty"
        first_logged_size = parse_log_line(first_lines[-1])
        first_expected = expected_deduplicated_size(BARE_REPO)
        assert first_logged_size == first_expected, (
            f"hook logged {first_logged_size}, expected repository size {first_expected}"
        )

        with open(test_file, "a") as f:
            f.write("\nsecond push " + uuid.uuid4().hex)
        subprocess.run(["git", "add", os.path.basename(test_file)], cwd=clone_dir, check=True)
        subprocess.run(["git", "commit", "-m", "Verifier second commit"], cwd=clone_dir, check=True, capture_output=True)
        result = subprocess.run(
            ["git", "push", "origin", f"HEAD:refs/heads/{branch}"],
            cwd=clone_dir,
            capture_output=True,
            text=True,
        )
        assert result.returncode == 0, f"second git push failed: {result.stderr}"

        with open(LOG_FILE, "r") as f:
            second_contents = f.read()
        assert second_contents.startswith(first_contents), "capacity.log was overwritten instead of appended"
        second_lines = [line for line in second_contents.splitlines() if line.strip()]
        assert len(second_lines) > len(first_lines), "second push did not append a new capacity entry"
        second_logged_size = parse_log_line(second_lines[-1])
        second_expected = expected_deduplicated_size(BARE_REPO)
        assert second_logged_size == second_expected, (
            f"hook logged {second_logged_size}, expected repository size {second_expected}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
