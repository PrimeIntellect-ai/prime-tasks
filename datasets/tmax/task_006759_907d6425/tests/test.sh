#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import fcntl
import json
import os
import re
import secrets
import subprocess
import tempfile
import time
from pathlib import Path

import pytest


def test_logs_extracted():
    logs_dir = "/home/user/logs"
    assert os.path.exists(logs_dir), f"Expected directory {logs_dir} to exist."
    assert os.path.isdir(logs_dir), f"Expected {logs_dir} to be a directory."

    log1 = os.path.join(logs_dir, "backup_1.log")
    log2 = os.path.join(logs_dir, "backup_2.log")
    assert os.path.exists(log1), f"Expected {log1} to be extracted."
    assert os.path.exists(log2), f"Expected {log2} to be extracted."


def test_parser_c_exists():
    c_file = "/home/user/parser.c"
    assert os.path.exists(c_file), f"Expected C source file {c_file} to exist."
    assert os.path.isfile(c_file), f"Expected {c_file} to be a file."


def test_parser_executable_exists():
    executable = "/home/user/parser"
    assert os.path.exists(executable), f"Expected compiled executable {executable} to exist."
    assert os.path.isfile(executable), f"Expected {executable} to be a file."
    assert os.access(executable, os.X_OK), f"Expected {executable} to be executable."
    with open(executable, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Expected /home/user/parser to be a compiled ELF executable."


def test_output_json_exists_and_correct():
    output_file = "/home/user/failed_jobs.json"
    assert os.path.exists(output_file), f"Expected output file {output_file} to exist."
    assert os.path.isfile(output_file), f"Expected {output_file} to be a file."

    with open(output_file, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 2, f"Expected exactly 2 lines in {output_file}, but found {len(lines)}."

    parsed_objects = []
    for line in lines:
        try:
            parsed_objects.append(json.loads(line))
        except json.JSONDecodeError:
            pytest.fail(f"Line in {output_file} is not valid JSON: {line}")

    expected_objects = [
        {"JobID": 102, "Status": "FAILED", "Files": 12},
        {"JobID": 201, "Status": "FAILED", "Files": 100}
    ]

    parsed_objects.sort(key=lambda x: x.get("JobID", 0))
    expected_objects.sort(key=lambda x: x["JobID"])
    assert parsed_objects == expected_objects, f"Contents of {output_file} do not match expected JSON objects."


@pytest.fixture(scope="module")
def parser_binaries(tmp_path_factory):
    build_dir = tmp_path_factory.mktemp("build")
    rebuilt = build_dir / "parser_from_source"
    result = subprocess.run(
        ["gcc", "-std=c11", "-O2", "/home/user/parser.c", "-o", str(rebuilt)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    assert result.returncode == 0, f"parser.c did not compile:\n{result.stderr}"
    return [Path("/home/user/parser"), rebuilt]


def record(job_id, status, files):
    return (
        "BEGIN_JOB\n"
        f"JobID: {job_id}\n"
        f"Status: {status}\n"
        f"Files: {files}\n"
        "END_JOB\n"
    )


def json_line(job_id, status, files):
    return json.dumps(
        {"JobID": job_id, "Status": status, "Files": files},
        separators=(", ", ": "),
    )


def run_parser(binary, log, config, output, timeout=5):
    result = subprocess.run(
        [str(binary), str(log), str(config), str(output)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=timeout,
    )
    assert result.returncode == 0, (
        f"{binary} exited with {result.returncode}. stdout={result.stdout!r}, stderr={result.stderr!r}"
    )


def test_source_uses_required_locking_api():
    source = Path("/home/user/parser.c").read_text(errors="replace")
    assert re.search(r"\b(?:flock|fcntl)\s*\(", source), (
        "parser.c must call flock() or fcntl() to lock the output file."
    )


def test_dynamic_config_and_multiline_parsing(parser_binaries, tmp_path):
    target = "FAIL_" + secrets.token_hex(5)
    other = "OK_" + secrets.token_hex(5)
    minimum = 20 + secrets.randbelow(40)
    base = 100000 + secrets.randbelow(800000)

    config = tmp_path / "dynamic.conf"
    config.write_text(f"TARGET_STATUS={target}\nMIN_FILES={minimum}\n")
    log = tmp_path / "dynamic.log"
    log.write_text(
        record(base, target, minimum - 1)
        + record(base + 1, other, minimum + 50)
        + record(base + 2, target, minimum)
        + record(base + 3, target, minimum + 71)
    )
    expected = [
        json_line(base + 2, target, minimum),
        json_line(base + 3, target, minimum + 71),
    ]

    for index, binary in enumerate(parser_binaries):
        output = tmp_path / f"dynamic-{index}.json"
        run_parser(binary, log, config, output)
        assert output.exists(), "Parser did not create its output file."
        assert output.read_text().splitlines() == expected
        for line in output.read_text().splitlines():
            json.loads(line)


def test_parser_really_honors_an_exclusive_lock(parser_binaries, tmp_path):
    target = "LOCK_" + secrets.token_hex(5)
    job_id = 1000000 + secrets.randbelow(8000000)
    files = 50 + secrets.randbelow(100)
    config = tmp_path / "lock.conf"
    config.write_text(f"TARGET_STATUS={target}\nMIN_FILES={files}\n")
    log = tmp_path / "lock.log"
    log.write_text(record(job_id, target, files))
    expected = json_line(job_id, target, files) + "\n"

    for index, binary in enumerate(parser_binaries):
        output = tmp_path / f"locked-{index}.json"
        fd = os.open(output, os.O_RDWR | os.O_CREAT | os.O_TRUNC, 0o600)
        proc = None
        was_blocked = False
        try:
            # Hold both Linux lock families so a correct flock- or fcntl-based
            # implementation must wait before appending.
            fcntl.flock(fd, fcntl.LOCK_EX)
            fcntl.lockf(fd, fcntl.LOCK_EX)
            proc = subprocess.Popen(
                [str(binary), str(log), str(config), str(output)],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            time.sleep(0.5)
            was_blocked = proc.poll() is None
            assert os.fstat(fd).st_size == 0, "Parser wrote while another process held the output lock."
        finally:
            fcntl.lockf(fd, fcntl.LOCK_UN)
            fcntl.flock(fd, fcntl.LOCK_UN)
            os.close(fd)

        assert was_blocked, "Parser did not wait for an exclusive lock on the output file."
        try:
            returncode = proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait()
            pytest.fail("Parser did not finish after the output lock was released.")
        assert returncode == 0
        assert output.read_text() == expected


def test_concurrent_append_is_complete_and_uncorrupted(parser_binaries, tmp_path):
    target = "PAR_" + secrets.token_hex(5)
    minimum = 10 + secrets.randbelow(30)
    config = tmp_path / "parallel.conf"
    config.write_text(f"TARGET_STATUS={target}\nMIN_FILES={minimum}\n")
    count = 32
    base = 20000000 + secrets.randbelow(1000000)

    logs = []
    expected = []
    for i in range(count):
        log = tmp_path / f"parallel-{i}.log"
        files = minimum + i
        log.write_text(record(base + i, target, files))
        logs.append(log)
        expected.append(json_line(base + i, target, files))

    for run, binary in enumerate(parser_binaries):
        output = tmp_path / f"parallel-output-{run}.json"
        processes = [
            subprocess.Popen(
                [str(binary), str(log), str(config), str(output)],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            for log in logs
        ]
        for proc in processes:
            try:
                rc = proc.wait(timeout=8)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait()
                pytest.fail("A concurrent parser process timed out.")
            assert rc == 0, f"Concurrent parser process exited with {rc}."

        assert output.exists()
        lines = output.read_text().splitlines()
        assert len(lines) == count, "Concurrent append lost or combined output records."
        for line in lines:
            json.loads(line)
        assert sorted(lines) == sorted(expected), "Concurrent output was missing, duplicated, or corrupted."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
