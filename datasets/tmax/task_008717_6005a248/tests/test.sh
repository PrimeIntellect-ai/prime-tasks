#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import secrets
import shutil
import signal
import subprocess
import tempfile
import time

import pytest

WATCH_DIR = "/home/user/doc_watch"
PROCESSED_DIR = "/home/user/doc_processed"
SOURCE = "/home/user/doc_daemon.cpp"
EXECUTABLE = "/home/user/doc_daemon"


def test_daemon_running():
    """Preserve the original assertion that a daemon was left running."""
    try:
        output = subprocess.check_output(["pgrep", "-f", "doc_daemon"]).decode("utf-8")
        assert output.strip(), "doc_daemon is not running in the background."
    except subprocess.CalledProcessError:
        pytest.fail("doc_daemon process not found.")


def stop_all_doc_daemons():
    me = os.getpid()
    victims = []
    for proc in glob.glob("/proc/[0-9]*"):
        try:
            pid = int(os.path.basename(proc))
            if pid == me:
                continue
            with open(os.path.join(proc, "cmdline"), "rb") as f:
                cmdline = f.read()
            exe = os.path.realpath(os.path.join(proc, "exe"))
            if b"doc_daemon" in cmdline or exe == os.path.realpath(EXECUTABLE):
                victims.append(pid)
        except (FileNotFoundError, PermissionError, ProcessLookupError, ValueError):
            pass

    for pid in victims:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    time.sleep(0.4)
    for pid in victims:
        try:
            os.kill(pid, 0)
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    time.sleep(0.2)


def launch(path):
    proc = subprocess.Popen(
        [path],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    time.sleep(0.35)
    assert proc.poll() is None, f"{path} exited instead of running continuously"
    assert os.path.realpath(f"/proc/{proc.pid}/exe") == os.path.realpath(path), \
        f"The running process is not the required executable {path}"
    return proc


def terminate(proc):
    if proc is None or proc.poll() is not None:
        return
    try:
        os.killpg(proc.pid, signal.SIGTERM)
        proc.wait(timeout=2)
    except (ProcessLookupError, subprocess.TimeoutExpired):
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def submit_file(name, lines):
    out_dir = os.path.join(PROCESSED_DIR, name)
    shutil.rmtree(out_dir, ignore_errors=True)

    final_path = os.path.join(WATCH_DIR, name + ".txt")
    temporary_path = final_path + ".uploading"
    for path in (final_path, temporary_path):
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass

    with open(temporary_path, "w", encoding="utf-8", newline="") as f:
        for line in lines:
            f.write(line + "\n")
    os.replace(temporary_path, final_path)
    return final_path, out_dir


def verify_case(name, lines, timeout=8):
    source_file, out_dir = submit_file(name, lines)
    count = (len(lines) + 2) // 3
    expected_parts = [os.path.join(out_dir, f"part_{i}.md") for i in range(1, count + 1)]
    index_file = os.path.join(out_dir, "index.md")

    deadline = time.time() + timeout
    while time.time() < deadline:
        if (not os.path.exists(source_file)
                and os.path.isdir(out_dir)
                and all(os.path.isfile(p) for p in expected_parts)
                and os.path.isfile(index_file)):
            break
        time.sleep(0.1)

    assert not os.path.exists(source_file), f"Original file {source_file} was not deleted by the daemon."
    assert os.path.isdir(out_dir), f"Output directory {out_dir} was not created."

    actual_parts = sorted(
        glob.glob(os.path.join(out_dir, "part_*.md")),
        key=lambda p: int(os.path.basename(p)[5:-3]),
    )
    assert actual_parts == expected_parts, "The daemon created an incorrect set of chunk files."

    for i, part in enumerate(expected_parts):
        assert os.path.isfile(part), f"{part} does not exist."
        with open(part, "r", encoding="utf-8") as f:
            content = f.read().splitlines()
        expected = lines[i * 3:(i + 1) * 3]
        assert content == expected, f"{part} content is incorrect."
        if i < count - 1:
            assert len(content) == 3, f"{part} should contain exactly 3 lines."

    with open(index_file, "r", encoding="utf-8") as f:
        index_content = f.read().strip()
    normalized = [os.path.normpath(os.path.abspath(p)) for p in expected_parts]
    expected_index = "\n".join(normalized)
    assert index_content == expected_index, \
        f"index.md content is incorrect. Expected:\n{expected_index}\nGot:\n{index_content}"


def test_source_executable_and_general_processing():
    assert os.path.isfile(SOURCE) and not os.path.islink(SOURCE), \
        f"Required C++ source file {SOURCE} is missing or is not a regular file."
    assert os.path.isfile(EXECUTABLE) and not os.path.islink(EXECUTABLE), \
        f"Required executable {EXECUTABLE} is missing or is not a regular file."
    assert os.access(EXECUTABLE, os.X_OK), f"{EXECUTABLE} is not executable."
    with open(EXECUTABLE, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{EXECUTABLE} is not a compiled executable."

    build_dir = tempfile.mkdtemp(prefix="doc_daemon_build_")
    rebuilt = os.path.join(build_dir, "rebuilt_daemon")
    compile_result = subprocess.run(
        ["g++", "-std=c++17", "-pthread", SOURCE, "-o", rebuilt],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    assert compile_result.returncode == 0, \
        f"{SOURCE} does not compile as C++:\n{compile_result.stderr}"

    os.makedirs(WATCH_DIR, exist_ok=True)
    os.makedirs(PROCESSED_DIR, exist_ok=True)
    stop_all_doc_daemons()

    submitted_proc = None
    rebuilt_proc = None
    final_proc = None
    try:
        # Execute the submitted artifact itself and preserve the original fixed case.
        submitted_proc = launch(EXECUTABLE)
        verify_case("secret_manual", [f"Line {i}" for i in range(1, 9)])

        # Unpredictable names and contents prevent a fixed-filename/fixed-output fake.
        token = secrets.token_hex(8)
        cases = []
        for number, line_count in enumerate((1, 3, 4, 7, 11)):
            name = f"draft_{token}_{number}"
            lines = [f"{secrets.token_hex(12)}-{i}" for i in range(line_count)]
            cases.append((name, lines))
        for name, lines in cases:
            verify_case(name, lines)

        terminate(submitted_proc)
        submitted_proc = None
        stop_all_doc_daemons()

        # Independently compile and exercise the submitted C++ source.
        rebuilt_proc = launch(rebuilt)
        source_name = f"source_check_{secrets.token_hex(8)}"
        source_lines = [secrets.token_urlsafe(18) for _ in range(10)]
        verify_case(source_name, source_lines)
        terminate(rebuilt_proc)
        rebuilt_proc = None
        stop_all_doc_daemons()

        # Leave the required submitted executable watching in the background.
        final_proc = launch(EXECUTABLE)
        time.sleep(0.3)
        assert final_proc.poll() is None, "doc_daemon was not left running."
    finally:
        terminate(submitted_proc)
        terminate(rebuilt_proc)
        shutil.rmtree(build_dir, ignore_errors=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
