#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import functools
import os
import re
import secrets
import subprocess
import tempfile
import time
import pytest

MAGIC = b"[AUDIT]"
EXPECTED_KEY = "AUTHKEY-9a8b7c6d5e4f3a2b1c0d9e8f7a6b5c4d"


def carve_reference(data):
    result = bytearray()
    pos = 0
    while True:
        start = data.find(MAGIC, pos)
        if start < 0:
            break
        end = data.find(b"\n", start)
        if end < 0:
            break
        result.extend(data[start:end + 1])
        pos = end + 1
    return bytes(result)


def assert_elf_executable(path):
    assert os.path.isfile(path), f"Executable {path} not found."
    assert os.access(path, os.X_OK), f"{path} is not executable."
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{path} is not a compiled ELF binary."


@functools.lru_cache(maxsize=1)
def rebuild_log_query():
    project = "/app/log-query-1.0"
    binary = os.path.join(project, "log-query")

    # Preserve the original existence and executable assertions before rebuilding.
    assert os.path.isfile(binary), f"Binary {binary} does not exist. Did you fix the Makefile and compile it?"
    assert os.access(binary, os.X_OK), f"Binary {binary} is not executable."

    dry = subprocess.run(
        ["make", "-n", "-B", "log-query"], cwd=project,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True
    )
    assert dry.returncode == 0, f"Makefile dry run failed:\n{dry.stdout}"
    assert re.search(r"(?:^|\s)(?:-pthread|-lpthread)(?:\s|$)", dry.stdout), \
        "The Makefile link command does not include the required pthread library/flag."

    os.remove(binary)
    built = subprocess.run(
        ["make", "-B", "log-query"], cwd=project,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True
    )
    assert built.returncode == 0, f"Makefile failed to build log-query:\n{built.stdout}"
    assert_elf_executable(binary)

    missing = subprocess.run(
        [binary, "parse", "/app/recovered.log"],
        env={k: v for k, v in os.environ.items() if k != "AUTH_KEY"},
        stdout=subprocess.PIPE, stderr=subprocess.PIPE
    )
    assert missing.returncode != 0, "log-query incorrectly succeeds without AUTH_KEY."

    valid_env = os.environ.copy()
    valid_env["AUTH_KEY"] = EXPECTED_KEY
    valid = subprocess.run(
        [binary, "parse", "/app/recovered.log"], env=valid_env,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE
    )
    assert valid.returncode == 0, \
        f"Rebuilt log-query failed: {valid.stderr.decode(errors='ignore')}"
    assert valid.stdout == b"Timeline parsed successfully.\n", \
        f"Unexpected log-query output: {valid.stdout!r}. Check DATA_DIR."
    return binary


def run_recovery(binary, image, expected, timeout=10):
    output = os.path.join(tempfile.gettempdir(), "recovered-" + secrets.token_hex(10) + ".log")
    try:
        proc = subprocess.run(
            [binary, image, output], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            timeout=timeout
        )
        assert proc.returncode == 0, \
            f"recover_logs failed with return code {proc.returncode}: {proc.stderr.decode(errors='ignore')}"
        assert os.path.isfile(output), f"recover_logs did not create {output}."
        with open(output, "rb") as f:
            actual = f.read()
        assert actual == expected, \
            f"Incorrect recovery for generated input: expected {expected!r}, got {actual!r}"
    finally:
        if os.path.exists(output):
            os.remove(output)


def test_extracted_key():
    key_path = "/app/extracted_key.txt"
    assert os.path.isfile(key_path), f"File {key_path} does not exist. Did you extract the key?"
    with open(key_path, "r") as f:
        key = f.read().strip()
    assert key == EXPECTED_KEY, f"Incorrect key extracted. Expected '{EXPECTED_KEY}', got '{key}'."


def test_log_query_binary_and_makefile():
    rebuild_log_query()


def test_recovered_log_and_final_timeline():
    image_path = "/app/logs_partition.img"
    recovered_path = "/app/recovered.log"
    timeline_path = "/app/final_timeline.txt"

    assert os.path.isfile(recovered_path), "The requested /app/recovered.log was not generated."
    with open(image_path, "rb") as f:
        expected_recovered = carve_reference(f.read())
    with open(recovered_path, "rb") as f:
        actual_recovered = f.read()
    assert actual_recovered == expected_recovered, "/app/recovered.log is not the correct recovery of the supplied image."

    assert os.path.isfile(timeline_path), f"File {timeline_path} does not exist. Did you run the log-query tool?"
    assert os.path.getsize(timeline_path) > 0, f"File {timeline_path} is empty."

    binary = rebuild_log_query()
    env = os.environ.copy()
    env["AUTH_KEY"] = EXPECTED_KEY
    generated = subprocess.run(
        [binary, "parse", recovered_path], env=env,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE
    )
    assert generated.returncode == 0, f"log-query could not generate the timeline: {generated.stderr.decode(errors='ignore')}"
    with open(timeline_path, "rb") as f:
        timeline = f.read()
    assert timeline == generated.stdout, "/app/final_timeline.txt is not the output of log-query on /app/recovered.log."


def test_recover_logs_generated_inputs_and_c_source():
    app_binary = "/app/recover_logs"
    assert_elf_executable(app_binary)

    source = "/app/recover_logs.c"
    assert os.path.isfile(source), "C source /app/recover_logs.c is missing."
    rebuilt = "/tmp/recover_logs-" + secrets.token_hex(10)
    compile_proc = subprocess.run(
        ["gcc", "-O2", "-std=c11", source, "-o", rebuilt],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE
    )
    assert compile_proc.returncode == 0, \
        f"/app/recover_logs.c does not compile as C: {compile_proc.stderr.decode(errors='ignore')}"
    assert_elf_executable(rebuilt)

    try:
        size = 2 * 1024 * 1024 + 4096
        data = bytearray(os.urandom(size))
        placements = [
            (4093, b"[AUDIT] boundary-4k-" + secrets.token_hex(8).encode() + b"\n"),
            (65533, b"[AUDIT] boundary-64k-" + secrets.token_hex(8).encode() + b"\n"),
            (1048573, b"[AUDIT] boundary-1m-" + secrets.token_hex(8).encode() + b"\n"),
            (1500003, b"[AUDIT] " + os.urandom(24).hex().encode() + b"\n"),
        ]
        for offset, line in placements:
            data[offset:offset + len(line)] = line
        # An unterminated candidate is not a complete audit log entry.
        data[-31:] = b"[AUDIT] unterminated-entry!!!!"

        fd, image = tempfile.mkstemp(prefix="partition-", suffix=".img")
        os.close(fd)
        with open(image, "wb") as f:
            f.write(data)
        expected = carve_reference(bytes(data))
        try:
            # Exercise both the delivered executable and a fresh build of the submitted C source.
            run_recovery(app_binary, image, expected)
            run_recovery(rebuilt, image, expected)
        finally:
            os.remove(image)
    finally:
        if os.path.exists(rebuilt):
            os.remove(rebuilt)


def test_recover_logs_metric():
    bin_path = "/app/recover_logs"
    assert os.path.isfile(bin_path), \
        f"Executable {bin_path} not found. Ensure you compile your C code to this exact path."
    assert os.access(bin_path, os.X_OK), f"Binary {bin_path} is not executable."

    input_img = "/hidden/large_partition.img"
    output_log = "/tmp/test_recovered.log"
    expected_log = "/hidden/expected.log"
    assert os.path.isfile(input_img), f"Hidden verifier file {input_img} is missing."
    assert os.path.isfile(expected_log), f"Hidden verifier file {expected_log} is missing."
    if os.path.exists(output_log):
        os.remove(output_log)

    start_time = time.time()
    proc = subprocess.run([bin_path, input_img, output_log], capture_output=True)
    elapsed = time.time() - start_time
    assert proc.returncode == 0, \
        f"recover_logs failed with return code {proc.returncode}. stderr: {proc.stderr.decode('utf-8', errors='ignore')}"
    assert os.path.isfile(output_log), f"recover_logs did not create the output file at {output_log}."
    with open(output_log, "rb") as f:
        recovered = f.read()
    with open(expected_log, "rb") as f:
        expected = f.read()
    assert recovered == expected, "Recovered logs do not match the expected output exactly. (Accuracy < 1.0)"
    assert elapsed <= 1.0, f"Execution time {elapsed:.3f}s exceeds the 1.0s threshold."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
