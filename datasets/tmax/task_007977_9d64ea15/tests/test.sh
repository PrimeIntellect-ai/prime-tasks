#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import collections
import fcntl
import hashlib
import os
import re
import signal
import subprocess
import tempfile
import time
import uuid

PARSER_C = "/home/user/doc_parser.c"
PARSER = "/home/user/doc_parser"
WATCHER = "/home/user/watch.sh"
MANIFEST = "/home/user/manifest.txt"
DOCS = "/home/user/docs"


def run_parser(archive, manifest, timeout=5):
    return subprocess.run(
        [PARSER, archive, manifest],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
    )


def expected_line(path, data, valid):
    name = os.path.basename(path)
    if valid:
        return f"{name} {hashlib.sha256(data).hexdigest()} VALID"
    return f"{name} INVALID"


def test_c_program_exists():
    assert os.path.exists(PARSER_C), "C program /home/user/doc_parser.c is missing."
    assert os.path.isfile(PARSER_C), "/home/user/doc_parser.c is not a regular file."


def test_compile_and_executable():
    # Compile the submitted source unconditionally so a separate tailored executable
    # cannot substitute for the requested C implementation.
    result = subprocess.run(
        ["gcc", PARSER_C, "-o", PARSER],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    assert result.returncode == 0, f"doc_parser.c failed to compile:\n{result.stderr}"
    assert os.path.exists(PARSER), "Compiled binary /home/user/doc_parser is missing."
    assert os.access(PARSER, os.X_OK), "/home/user/doc_parser is not executable."


def test_source_uses_required_posix_locking():
    source = open(PARSER_C, "r", encoding="utf-8", errors="replace").read()
    assert "F_SETLKW" in source, "The C source does not request a blocking POSIX fcntl lock."
    assert "F_WRLCK" in source, "The C source does not request an exclusive write lock."
    assert re.search(r"\bfcntl\s*\(", source), "The C source does not call fcntl()."


def test_exactly_two_argument_handling():
    with tempfile.TemporaryDirectory() as td:
        archive = os.path.join(td, "input.gz")
        manifest = os.path.join(td, "manifest.txt")
        open(archive, "wb").write(b"\x1f\x8bpayload")
        open(manifest, "wb").close()

        bad_invocations = [
            [PARSER],
            [PARSER, archive],
            [PARSER, archive, manifest, "extra"],
        ]
        for command in bad_invocations:
            result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=3)
            assert result.returncode != 0, f"Parser accepted invalid argument count: {command}"
        assert open(manifest, "rb").read() == b"", "Invalid invocation unexpectedly modified the manifest."


def test_parser_dynamic_magic_hash_and_basename():
    with tempfile.TemporaryDirectory() as td:
        manifest = os.path.join(td, "result.manifest")
        open(manifest, "wb").close()

        token = uuid.uuid4().hex
        cases = [
            (os.path.join(td, f"archive_{token}.bin"), b"\x1f\x8b" + os.urandom(137), True),
            (os.path.join(td, f"wrong_magic_{token}.gz"), b"\x1f\x8a" + os.urandom(91), False),
            (os.path.join(td, f"one_byte_{token}.gz"), b"\x1f", False),
            (os.path.join(td, f"empty_{token}.gz"), b"", False),
        ]

        wanted = []
        for path, data, valid in cases:
            with open(path, "wb") as f:
                f.write(data)
            result = run_parser(path, manifest)
            assert result.returncode == 0, result.stderr.decode(errors="replace")
            wanted.append(expected_line(path, data, valid))

        lines = open(manifest, "r", encoding="utf-8").read().splitlines()
        assert collections.Counter(lines) == collections.Counter(wanted), (
            f"Unexpected parser output. Expected {wanted!r}, got {lines!r}"
        )


def test_parser_waits_for_posix_fcntl_lock():
    with tempfile.TemporaryDirectory() as td:
        archive = os.path.join(td, f"locked_{uuid.uuid4().hex}.gz")
        data = b"\x1f\x8b" + os.urandom(64)
        open(archive, "wb").write(data)
        manifest = os.path.join(td, "locked.manifest")

        with open(manifest, "a+b") as held:
            fcntl.lockf(held, fcntl.LOCK_EX)
            proc = subprocess.Popen([PARSER, archive, manifest], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            try:
                time.sleep(0.7)
                assert proc.poll() is None, "Parser wrote without waiting for the existing POSIX write lock."
            finally:
                fcntl.lockf(held, fcntl.LOCK_UN)
            stdout, stderr = proc.communicate(timeout=5)
            assert proc.returncode == 0, stderr.decode(errors="replace")

        lines = open(manifest, "r", encoding="utf-8").read().splitlines()
        assert lines == [expected_line(archive, data, True)]


def test_concurrent_parser_appends_are_complete():
    with tempfile.TemporaryDirectory() as td:
        manifest = os.path.join(td, "concurrent.manifest")
        open(manifest, "wb").close()
        cases = []
        for i in range(20):
            path = os.path.join(td, f"item_{uuid.uuid4().hex}_{i}.gz")
            valid = i % 3 != 0
            data = (b"\x1f\x8b" if valid else b"NO") + os.urandom(80 + i)
            open(path, "wb").write(data)
            cases.append((path, data, valid))

        processes = [subprocess.Popen([PARSER, path, manifest]) for path, _, _ in cases]
        for proc in processes:
            assert proc.wait(timeout=8) == 0

        actual = open(manifest, "r", encoding="utf-8").read().splitlines()
        wanted = [expected_line(path, data, valid) for path, data, valid in cases]
        assert collections.Counter(actual) == collections.Counter(wanted), (
            "Concurrent writes produced missing, duplicate, or corrupted manifest lines."
        )


def test_watch_script_exists():
    assert os.path.exists(WATCHER), "Bash script /home/user/watch.sh is missing."
    assert os.path.isfile(WATCHER), "/home/user/watch.sh is not a regular file."
    assert os.access(WATCHER, os.X_OK), "/home/user/watch.sh is not executable."


def test_system_integration():
    # Retain the original fixed-path assertions and add unpredictable paths so a
    # filename-specific watcher/parser cannot pass.
    with open(MANIFEST, "w") as f:
        f.write("")

    watcher = subprocess.Popen(
        [WATCHER],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    time.sleep(1.5)
    assert watcher.poll() is None, "watch.sh did not remain running to watch for events."

    created = []
    try:
        valid_gz_path = os.path.join(DOCS, "valid_doc.gz")
        subprocess.run(f"echo 'Valid data' | gzip > {valid_gz_path}", shell=True, check=True)
        created.append(valid_gz_path)
        valid_gz_data = open(valid_gz_path, "rb").read()
        valid_hash = hashlib.sha256(valid_gz_data).hexdigest()

        invalid_path = os.path.join(DOCS, "bad_doc.gz")
        with open(invalid_path, "wb") as f:
            f.write(b"Not a gzip file\n")
        created.append(invalid_path)

        token = uuid.uuid4().hex
        random_valid = os.path.join(DOCS, f"draft_{token}.dat")
        random_valid_data = b"\x1f\x8b" + os.urandom(211)
        with open(random_valid, "wb") as f:
            f.write(random_valid_data)
        created.append(random_valid)

        random_invalid = os.path.join(DOCS, f"notes_{uuid.uuid4().hex}.gz")
        random_invalid_data = b"not gzip " + os.urandom(73)
        with open(random_invalid, "wb") as f:
            f.write(random_invalid_data)
        created.append(random_invalid)

        expected = {
            f"valid_doc.gz {valid_hash} VALID",
            "bad_doc.gz INVALID",
            expected_line(random_valid, random_valid_data, True),
            expected_line(random_invalid, random_invalid_data, False),
        }

        deadline = time.time() + 8
        manifest_lines = []
        while time.time() < deadline:
            manifest_lines = open(MANIFEST, "r", encoding="utf-8").read().splitlines()
            if expected.issubset(set(manifest_lines)):
                break
            time.sleep(0.1)

        manifest_content = "\n".join(manifest_lines)
        expected_valid_line = f"valid_doc.gz {valid_hash} VALID"
        expected_invalid_line = "bad_doc.gz INVALID"
        assert expected_valid_line in manifest_content, f"Expected valid line '{expected_valid_line}' not found in manifest."
        assert expected_invalid_line in manifest_content, f"Expected invalid line '{expected_invalid_line}' not found in manifest."
        assert expected.issubset(set(manifest_lines)), (
            f"Watcher did not process unpredictable close_write events correctly; got {manifest_lines!r}"
        )
    finally:
        try:
            os.killpg(watcher.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        try:
            watcher.wait(timeout=3)
        except subprocess.TimeoutExpired:
            try:
                os.killpg(watcher.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            watcher.wait(timeout=3)
        for path in created:
            try:
                os.unlink(path)
            except FileNotFoundError:
                pass
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
