#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import shutil
import signal
import subprocess
import time
import uuid

INDEX = "/home/user/clean_index.txt"
INCOMING = "/home/user/incoming_docs"
SOURCE = "/home/user/watcher.cpp"
EXECUTABLE = "/home/user/watcher"

KNOWN_LINES = [
    "docs/intro.md | Introduction Guide",
    "docs/api/reference.md | API Reference V2",
    "assets/logo.png | Company Logo",
]


def read_index():
    if not os.path.isfile(INDEX):
        return []
    with open(INDEX, "r", encoding="utf-8") as f:
        return [line.strip() for line in f if line.strip()]


def test_clean_index_exists_and_content():
    assert os.path.isfile(INDEX), f"Expected file {INDEX} does not exist."
    actual_lines = read_index()
    assert actual_lines == KNOWN_LINES, (
        f"Content of {INDEX} does not match expected output.\n"
        f"Expected:\n{KNOWN_LINES}\nActual:\n{actual_lines}"
    )


def test_watcher_cpp_exists_and_contains_required_functions():
    assert os.path.isfile(SOURCE), f"Source file {SOURCE} does not exist."
    with open(SOURCE, "r", encoding="utf-8") as f:
        content = f.read()

    # Preserve the original assertions.
    assert "inotify_init" in content, "watcher.cpp does not contain 'inotify_init'."
    assert "inotify_add_watch" in content, "watcher.cpp does not contain 'inotify_add_watch'."
    assert "ifstream" in content, "watcher.cpp does not contain 'ifstream' (C++ standard file I/O)."

    # Require the relevant constructs outside comments rather than accepting keywords in comments.
    code = re.sub(r"/\*.*?\*/", "", content, flags=re.S)
    code = re.sub(r"//[^\n]*", "", code)
    assert re.search(r"\binotify_init(?:1)?\s*\(", code), "No inotify initialization call found."
    assert re.search(r"\binotify_add_watch\s*\(", code), "No inotify_add_watch call found."
    assert re.search(r"\b(?:std::)?ifstream\b", code), "No C++ ifstream use found."


def test_watcher_executable_exists():
    assert os.path.isfile(EXECUTABLE), f"Executable {EXECUTABLE} does not exist."
    assert os.access(EXECUTABLE, os.X_OK), f"File {EXECUTABLE} is not executable."
    with open(EXECUTABLE, "rb") as f:
        assert f.read(4) == b"\x7fELF", "watcher is not a compiled ELF executable."


def clear_runtime_state():
    os.makedirs(INCOMING, exist_ok=True)
    for name in os.listdir(INCOMING):
        path = os.path.join(INCOMING, name)
        if os.path.isdir(path) and not os.path.islink(path):
            shutil.rmtree(path)
        else:
            os.unlink(path)
    try:
        os.unlink(INDEX)
    except FileNotFoundError:
        pass


def wait_for_lines(expected, timeout=4.0):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if read_index() == expected:
            return
        time.sleep(0.05)
    assert read_index() == expected, f"Expected index lines {expected}, got {read_index()}"


def wait_for_inotify_close_watch(proc, timeout=4.0):
    deadline = time.time() + timeout
    while time.time() < deadline:
        assert proc.poll() is None, "watcher exited instead of running continuously"
        fd_dir = f"/proc/{proc.pid}/fd"
        try:
            fds = os.listdir(fd_dir)
        except FileNotFoundError:
            fds = []
        for fd in fds:
            fd_path = os.path.join(fd_dir, fd)
            try:
                target = os.readlink(fd_path)
            except OSError:
                continue
            if "inotify" not in target:
                continue
            try:
                with open(f"/proc/{proc.pid}/fdinfo/{fd}", "r", encoding="utf-8") as info:
                    text = info.read()
            except OSError:
                continue
            masks = re.findall(r"\bmask:([0-9a-fA-F]+)", text)
            if any(int(mask, 16) & 0x8 for mask in masks):
                return
        time.sleep(0.05)
    raise AssertionError("running watcher has no inotify watch including IN_CLOSE_WRITE")


def terminate(proc):
    if proc.poll() is None:
        proc.terminate()
        try:
            proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait(timeout=2)


def exercise_watcher(binary):
    clear_runtime_state()
    proc = subprocess.Popen(
        [binary],
        cwd="/home/user",
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    try:
        wait_for_inotify_close_watch(proc)

        # Re-run the prescribed input and retain the original exact-content assertion.
        shutil.copyfile("/home/user/test_data.log", os.path.join(INCOMING, "trigger.log"))
        wait_for_lines(KNOWN_LINES)
        assert proc.poll() is None, "watcher stopped after its first event"

        token = uuid.uuid4().hex
        valid1 = f"docs/{token}/guide.md"
        valid2 = f"assets/{token}.bin"
        bad1 = f"../outside/{token}.txt"
        bad2 = f"safe/{token}/../escape.txt"
        title1 = f"Generated Guide {token}"
        title2 = f"Generated Asset {token}"
        dynamic_text = f"""RECORD_START
Path: {valid1}
Title: {title1}
RECORD_END


RECORD_START
Path: {bad1}
Title: Reject One {token}
RECORD_END

RECORD_START
Path: {valid2}
Title: {title2}
RECORD_END

RECORD_START
Path: {bad2}
Title: Reject Two {token}
RECORD_END
"""

        # Keep the file open briefly: IN_CLOSE_WRITE processing must not happen early.
        dynamic_path = os.path.join(INCOMING, f"dynamic-{token}.log")
        f = open(dynamic_path, "w", encoding="utf-8")
        try:
            f.write(dynamic_text)
            f.flush()
            os.fsync(f.fileno())
            time.sleep(0.6)
            assert proc.poll() is None, "watcher exited while waiting for a close-write event"
            assert read_index() == KNOWN_LINES, "watcher processed a file before it was closed"
        finally:
            f.close()

        expected = KNOWN_LINES + [f"{valid1} | {title1}", f"{valid2} | {title2}"]
        wait_for_lines(expected)
        assert proc.poll() is None, "watcher stopped after processing a later event"

        # A third event verifies continuous operation and observable flushing while still running.
        valid3 = f"more/{token}/final.md"
        title3 = f"Final Record {token}"
        with open(os.path.join(INCOMING, f"final-{token}.log"), "w", encoding="utf-8") as f3:
            f3.write(f"\nRECORD_START\nPath: {valid3}\nTitle: {title3}\nRECORD_END\n")
        expected.append(f"{valid3} | {title3}")
        wait_for_lines(expected)
        assert proc.poll() is None, "watcher did not remain running after multiple files"
    finally:
        terminate(proc)


def test_real_watcher_behavior_and_recompiled_source():
    # Exercise the submitted executable itself.
    exercise_watcher(EXECUTABLE)

    # Also establish that watcher.cpp is a compilable implementation of the same behavior.
    rebuilt = f"/tmp/watcher-rebuilt-{uuid.uuid4().hex}"
    result = subprocess.run(
        ["g++", "-O2", SOURCE, "-o", rebuilt],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, f"watcher.cpp failed to compile with g++ -O2:\n{result.stderr}"
    assert os.access(rebuilt, os.X_OK)
    try:
        exercise_watcher(rebuilt)
    finally:
        try:
            os.unlink(rebuilt)
        except FileNotFoundError:
            pass
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
