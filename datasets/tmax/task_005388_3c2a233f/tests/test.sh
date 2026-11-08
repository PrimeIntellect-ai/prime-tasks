#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import shutil
import struct
import subprocess
import tempfile

APP = "/home/user/app"
SIGNATURE = bytes.fromhex("DE AD BE EF")


def test_bad_signature_txt():
    path = "/home/user/bad_signature.txt"
    assert os.path.isfile(path), f"{path} is missing"

    with open(path, "r") as f:
        content = f.read().strip()

    normalized_content = "".join(content.split()).upper()
    assert normalized_content == "DEADBEEF", f"{path} does not contain the correct 4-byte sequence"


def test_fuzzer_py_exists_and_runs():
    path = "/home/user/fuzzer.py"
    assert os.path.isfile(path), f"{path} is missing"

    with open(path, "r", errors="replace") as f:
        source = f.read()
    assert "parse_record" in source, f"{path} does not interface with parse_record"
    assert "libfastparse.so" in source, f"{path} does not reference libfastparse.so"

    trace_path = "/tmp/fuzzer.strace"
    result = subprocess.run(
        ["strace", "-f", "-e", "trace=openat", "-o", trace_path, "python3", path],
        cwd=APP,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=60,
    )
    assert result.returncode == 0, (
        f"{path} did not run successfully (return code: {result.returncode})\n"
        f"stderr: {result.stderr.decode(errors='replace')}"
    )
    with open(trace_path, "r", errors="replace") as f:
        trace = f.read()
    assert "libfastparse.so" in trace, f"{path} did not load libfastparse.so when executed"


def test_mre_py_segfaults():
    path = "/home/user/mre.py"
    assert os.path.isfile(path), f"{path} is missing"

    result = subprocess.run(["python3", path], capture_output=True)
    assert result.returncode in (139, -11), f"{path} did not result in a segmentation fault (return code: {result.returncode})"


def _read_spy_calls(path):
    calls = []
    with open(path, "rb") as f:
        payload = f.read()
    offset = 0
    while offset < len(payload):
        assert offset + 4 <= len(payload), "Malformed parse_record call log"
        length = struct.unpack_from("<I", payload, offset)[0]
        offset += 4
        assert offset + length <= len(payload), "Malformed parse_record call payload"
        calls.append(payload[offset:offset + length])
        offset += length
    return calls


def test_safe_report_generator_py_exists_and_sanitizes():
    path = "/home/user/safe_report_generator.py"
    assert os.path.isfile(path), f"{path} is missing"

    library_path = os.path.join(APP, "libfastparse.so")
    data_path = os.path.join(APP, "data.bin")
    log_path = os.path.join(APP, "processed.log")

    with open(library_path, "rb") as f:
        original_library = f.read()
    with open(data_path, "rb") as f:
        original_data = f.read()
    original_log = None
    if os.path.exists(log_path):
        with open(log_path, "rb") as f:
            original_log = f.read()

    spy_source = r'''
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

int parse_record(const char *data, int len) {
    const char *path = getenv("FASTPARSE_CALL_LOG");
    if (!path || len < 0) return 0;
    FILE *f = fopen(path, "ab");
    if (!f) return 0;
    uint32_t n = (uint32_t)len;
    fwrite(&n, sizeof(n), 1, f);
    if (len) fwrite(data, 1, (size_t)len, f);
    fclose(f);
    return 1;
}
'''

    temp_dir = tempfile.mkdtemp(prefix="safe-generator-test-")
    spy_c = os.path.join(temp_dir, "spy.c")
    spy_so = os.path.join(temp_dir, "libfastparse.so")
    calls_path = os.path.join(temp_dir, "calls.bin")

    try:
        with open(spy_c, "w") as f:
            f.write(spy_source)
        subprocess.run(
            ["gcc", "-shared", "-fPIC", "-o", spy_so, spy_c],
            check=True,
            capture_output=True,
        )

        chunk1 = b"A" * 10 + SIGNATURE + b"B" * 50
        chunk2 = bytes(range(64))
        chunk3 = b"C" * 60 + SIGNATURE
        test_data = chunk1 + chunk2 + chunk3
        assert len(test_data) == 64 * 3

        shutil.copyfile(spy_so, library_path)
        with open(data_path, "wb") as f:
            f.write(test_data)
        if os.path.exists(log_path):
            os.remove(log_path)

        env = os.environ.copy()
        env["FASTPARSE_CALL_LOG"] = calls_path
        result = subprocess.run(
            ["python3", path],
            cwd=APP,
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
        )
        assert result.returncode == 0, (
            f"{path} failed on test telemetry (return code: {result.returncode})\n"
            f"stderr: {result.stderr.decode(errors='replace')}"
        )
        assert os.path.isfile(calls_path), f"{path} never called parse_record"

        calls = _read_spy_calls(calls_path)
        assert len(calls) == 3, f"Expected parse_record to be called for 3 chunks, got {len(calls)}"
        assert all(SIGNATURE not in call for call in calls), "The crashing sequence was passed to parse_record"
        expected = b"".join(chunk.replace(SIGNATURE, b"") for chunk in (chunk1, chunk2, chunk3))
        assert b"".join(calls) == expected, "The wrapper did not preserve all non-crashing input bytes"

        assert os.path.isfile(log_path), f"{log_path} was not generated"
        with open(log_path, "r") as f:
            content = f.read().strip()
        assert "Processed 3 chunks" in content, "The wrapper reported the wrong test chunk count"
    finally:
        with open(library_path, "wb") as f:
            f.write(original_library)
        with open(data_path, "wb") as f:
            f.write(original_data)
        if original_log is None:
            if os.path.exists(log_path):
                os.remove(log_path)
        else:
            with open(log_path, "wb") as f:
                f.write(original_log)
        shutil.rmtree(temp_dir, ignore_errors=True)


def test_processed_log():
    path = "/home/user/app/processed.log"
    safe_path = "/home/user/safe_report_generator.py"

    if os.path.exists(path):
        os.remove(path)
    result = subprocess.run(
        ["python3", safe_path],
        cwd=APP,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"{safe_path} did not process the real data successfully (return code: {result.returncode})\n"
        f"stderr: {result.stderr.decode(errors='replace')}"
    )
    assert os.path.isfile(path), f"{path} is missing. Make sure safe_report_generator.py was run successfully."

    with open(path, "r") as f:
        content = f.read().strip()

    assert "Processed 1000 chunks" in content, f"{path} does not contain the expected success message"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
