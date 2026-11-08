#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import concurrent.futures
import fcntl
import os
import re
import subprocess
import tempfile
import time


def test_safe_append_source_fixed():
    source_path = "/home/user/tools/safe_append.c"
    assert os.path.isfile(source_path), f"Source file missing: {source_path}"

    with open(source_path, "r") as f:
        content = f.read()

    # Preserve the original assertions.
    assert "flock" in content, "The flock() function call is missing in safe_append.c"
    assert "LOCK_EX" in content, "LOCK_EX is missing in safe_append.c"
    assert "LOCK_UN" in content, "LOCK_UN is missing in safe_append.c"

    # Comments and string literals must not satisfy the locking checks.
    cleaned = re.sub(
        r'//.*?$|/\*.*?\*/|"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'',
        "",
        content,
        flags=re.MULTILINE | re.DOTALL,
    )
    assert re.search(r"\bflock\s*\([^;{}]*\bLOCK_EX\b[^;{}]*\)", cleaned, re.DOTALL), \
        "safe_append.c does not call flock() with LOCK_EX"
    assert re.search(r"\bflock\s*\([^;{}]*\bLOCK_UN\b[^;{}]*\)", cleaned, re.DOTALL), \
        "safe_append.c does not call flock() with LOCK_UN"


def test_safe_append_compiled():
    exe_path = "/home/user/tools/safe_append"
    assert os.path.isfile(exe_path), f"Compiled executable missing: {exe_path}"
    assert os.access(exe_path, os.X_OK), f"File is not executable: {exe_path}"
    with open(exe_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "safe_append is not a compiled ELF executable"


def assert_blocks_on_exclusive_lock(exe_path):
    with tempfile.TemporaryDirectory() as td:
        target = os.path.join(td, "append.txt")
        baseline = b"existing\n"
        payload = b"new locked content\n"
        with open(target, "wb") as f:
            f.write(baseline)

        lock_fd = os.open(target, os.O_RDWR)
        proc = None
        try:
            fcntl.flock(lock_fd, fcntl.LOCK_EX)
            proc = subprocess.Popen(
                [exe_path, target],
                stdin=subprocess.PIPE,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            )
            proc.stdin.write(payload)
            proc.stdin.close()
            time.sleep(0.4)

            assert proc.poll() is None, \
                f"{exe_path} did not wait for an existing exclusive lock"
            with open(target, "rb") as f:
                assert f.read() == baseline, \
                    f"{exe_path} wrote while another process held the lock"

            fcntl.flock(lock_fd, fcntl.LOCK_UN)
            proc.wait(timeout=5)
            assert proc.returncode == 0, f"{exe_path} exited with {proc.returncode}"
            with open(target, "rb") as f:
                assert f.read() == baseline + payload, \
                    f"{exe_path} did not append the supplied input correctly"
        finally:
            try:
                fcntl.flock(lock_fd, fcntl.LOCK_UN)
            except OSError:
                pass
            os.close(lock_fd)
            if proc is not None and proc.poll() is None:
                proc.kill()
                proc.wait()


def assert_concurrent_appends_are_atomic(exe_path):
    with tempfile.TemporaryDirectory() as td:
        target = os.path.join(td, "concurrent.txt")
        payload_a = b"BEGIN_A\n" + (b"A" * 131072) + b"\nEND_A\n"
        payload_b = b"BEGIN_B\n" + (b"B" * 131072) + b"\nEND_B\n"

        def append(payload):
            return subprocess.run(
                [exe_path, target], input=payload,
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10
            )

        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
            futures = [pool.submit(append, payload_a), pool.submit(append, payload_b)]
            results = [future.result() for future in futures]

        for result in results:
            assert result.returncode == 0, result.stderr.decode(errors="replace")

        with open(target, "rb") as f:
            actual = f.read()
        assert actual in (payload_a + payload_b, payload_b + payload_a), \
            "Concurrent append operations were interleaved or corrupted"


def test_safe_append_runtime_locking():
    submitted_exe = "/home/user/tools/safe_append"
    assert_blocks_on_exclusive_lock(submitted_exe)
    assert_concurrent_appends_are_atomic(submitted_exe)

    # Recompile the submitted source so an unrelated executable cannot pass.
    with tempfile.TemporaryDirectory() as td:
        rebuilt_exe = os.path.join(td, "safe_append")
        result = subprocess.run(
            ["gcc", "/home/user/tools/safe_append.c", "-o", rebuilt_exe],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
        )
        assert result.returncode == 0, f"safe_append.c failed to compile: {result.stderr}"
        assert_blocks_on_exclusive_lock(rebuilt_exe)
        assert_concurrent_appends_are_atomic(rebuilt_exe)


def test_api_docs_output():
    conf_path = "/home/user/docs.conf"
    assert os.path.isfile(conf_path), f"Config file missing: {conf_path}"

    prefix = ""
    with open(conf_path, "r") as f:
        for line in f:
            if line.startswith("PREFIX="):
                prefix = line.strip().split("=", 1)[1]
                break

    assert prefix, "Could not find PREFIX in docs.conf"

    src_dir = "/home/user/src"
    assert os.path.isdir(src_dir), f"Source directory missing: {src_dir}"
    src_files = sorted([f for f in os.listdir(src_dir) if f.endswith(".c")])

    expected_lines = []
    for src_file in src_files:
        with open(os.path.join(src_dir, src_file), "r") as f:
            in_api_block = False
            for line in f:
                stripped = line.strip()
                if stripped == "/* API":
                    in_api_block = True
                elif stripped == "*/":
                    in_api_block = False
                elif in_api_block:
                    text = line[:-1] if line.endswith("\n") else line
                    expected_lines.append(f"{prefix} {text}")

    expected_content = "\n".join(expected_lines)
    if expected_content:
        expected_content += "\n"

    output_path = "/home/user/api_docs.md"
    assert os.path.isfile(output_path), f"Output file missing: {output_path}"
    with open(output_path, "r") as f:
        actual_content = f.read()

    assert actual_content == expected_content, \
        f"Content of {output_path} does not match expected output."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
