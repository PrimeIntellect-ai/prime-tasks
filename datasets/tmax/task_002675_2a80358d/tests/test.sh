#!/bin/bash
mkdir -p /logs/verifier

# Ensure the provided Redis service is available for integration testing.
if ! redis-cli -h 127.0.0.1 -p 6379 ping >/dev/null 2>&1; then
    redis-server --daemonize yes >/dev/null 2>&1 || true
    sleep 1
fi

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import re
import secrets
import subprocess
import tempfile
import time
import urllib.request

import pytest

CLEAN_CORPUS_DIR = "/app/corpus/clean"
EVIL_CORPUS_DIR = "/app/corpus/evil"
FILTER_CLI = "/home/user/filter_cli"
PROCESSOR_SOURCE = "/home/user/processor.c"
PROCESSOR = "/home/user/processor"
STATS = "/home/user/www/stats.json"


def run(cmd, timeout=10):
    return subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                          timeout=timeout)


def assert_elf_executable(path):
    assert os.path.isfile(path), f"Missing executable: {path}"
    assert os.access(path, os.X_OK), f"Not executable: {path}"
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{path} is not a compiled ELF binary"


def redis(*args):
    result = run(["redis-cli", "-h", "127.0.0.1", "-p", "6379", *args])
    assert result.returncode == 0, result.stderr.decode(errors="replace")
    return result.stdout.decode().strip()


def wait_until(predicate, timeout=10, interval=0.05):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if predicate():
            return True
        time.sleep(interval)
    return False


def wait_for_stats(expected, timeout=10):
    def matches():
        try:
            with open(STATS, "r", encoding="utf-8") as f:
                return f.read() == expected
        except (FileNotFoundError, OSError):
            return False
    assert wait_until(matches, timeout), f"stats.json did not become {expected!r}"


def test_filter_cli_exists_and_executable():
    assert os.path.isfile(FILTER_CLI), f"Filter CLI binary not found at {FILTER_CLI}"
    assert os.access(FILTER_CLI, os.X_OK), f"Filter CLI at {FILTER_CLI} is not executable"
    assert_elf_executable(FILTER_CLI)


def test_adversarial_corpus():
    assert os.path.isdir(CLEAN_CORPUS_DIR), f"Clean corpus directory missing: {CLEAN_CORPUS_DIR}"
    assert os.path.isdir(EVIL_CORPUS_DIR), f"Evil corpus directory missing: {EVIL_CORPUS_DIR}"

    clean_files = [f for f in os.listdir(CLEAN_CORPUS_DIR) if f.endswith('.csv')]
    evil_files = [f for f in os.listdir(EVIL_CORPUS_DIR) if f.endswith('.csv')]

    assert len(clean_files) > 0, "No clean corpus files found"
    assert len(evil_files) > 0, "No evil corpus files found"

    clean_failed = []
    evil_failed = []

    with tempfile.TemporaryDirectory() as tmpdir:
        for cfile in clean_files:
            input_path = os.path.join(CLEAN_CORPUS_DIR, cfile)
            output_path = os.path.join(tmpdir, f"out_{cfile}")
            result = subprocess.run([FILTER_CLI, input_path, output_path], capture_output=True)
            if result.returncode != 0:
                clean_failed.append(cfile)
                continue
            if not os.path.exists(output_path):
                clean_failed.append(cfile)
                continue
            with open(input_path, 'r') as f_in, open(output_path, 'r') as f_out:
                in_lines = f_in.readlines()
                out_lines = f_out.readlines()
            if in_lines != out_lines:
                clean_failed.append(cfile)

        for efile in evil_files:
            input_path = os.path.join(EVIL_CORPUS_DIR, efile)
            output_path = os.path.join(tmpdir, f"out_{efile}")
            result = subprocess.run([FILTER_CLI, input_path, output_path], capture_output=True)
            if result.returncode != 0:
                pass
            elif os.path.exists(output_path):
                with open(output_path, 'r') as f_out:
                    out_lines = f_out.readlines()
                if len(out_lines) > 0:
                    evil_failed.append(efile)

    error_msg = []
    if clean_failed:
        error_msg.append(f"{len(clean_failed)} of {len(clean_files)} clean modified: {', '.join(clean_failed)}")
    if evil_failed:
        error_msg.append(f"{len(evil_failed)} of {len(evil_files)} evil bypassed: {', '.join(evil_failed)}")
    if error_msg:
        pytest.fail(" | ".join(error_msg))


def test_filter_cli_generated_mixed_corpus():
    valid = [
        f"{secrets.token_hex(8)},1,Alpha Numeric 123,4.25\n".encode(),
        f"{secrets.token_hex(8).upper()},00042,{'A' * 100},-2.5\n".encode(),
        f"{secrets.token_hex(8)},999999999,spaces are allowed,1e2\n".encode(),
        f"{secrets.token_hex(8)},7,Final Row,0.0".encode(),
    ]
    bad_id = secrets.token_hex(8)
    invalid = [
        b"123,10,Good Text,1.0\n",
        b"gggggggggggggggg,10,Good Text,1.0\n",
        f"{bad_id},0,Good Text,1.0\n".encode(),
        f"{secrets.token_hex(8)},-1,Good Text,1.0\n".encode(),
        f"{secrets.token_hex(8)},1.5,Good Text,1.0\n".encode(),
        f"{secrets.token_hex(8)},10,Bad punctuation!,1.0\n".encode(),
        f"{secrets.token_hex(8)},10,Bad\tTab,1.0\n".encode(),
        f"{secrets.token_hex(8)},10,{'B' * 101},1.0\n".encode(),
        f"{secrets.token_hex(8)},10,Good Text,not-a-float\n".encode(),
        f"{secrets.token_hex(8)},10,Good Text,1.0,extra\n".encode(),
        f"{secrets.token_hex(8)},10,Caf".encode() + b"\xc3\xa9,1.0\n",
        f"{secrets.token_hex(8)},10,Bad".encode() + b"\xffText,1.0\n",
    ]
    rows = valid + invalid
    random.SystemRandom().shuffle(rows)
    expected = b"".join(row for row in rows if row in valid)

    with tempfile.TemporaryDirectory() as td:
        input_path = os.path.join(td, secrets.token_hex(10) + ".dat")
        output_path = os.path.join(td, secrets.token_hex(10) + ".result")
        with open(input_path, "wb") as f:
            f.write(b"".join(rows))
        result = run([FILTER_CLI, input_path, output_path])
        assert result.returncode == 0, result.stderr.decode(errors="replace")
        assert os.path.isfile(output_path), "filter_cli did not create its output file"
        with open(output_path, "rb") as f:
            actual = f.read()
        assert actual == expected, f"Unexpected filtered bytes: {actual!r}"


def test_processor_source_and_binary():
    assert os.path.isfile(PROCESSOR_SOURCE), f"Missing source file: {PROCESSOR_SOURCE}"
    assert_elf_executable(PROCESSOR)
    with open(PROCESSOR_SOURCE, "r", encoding="utf-8", errors="replace") as f:
        source = f.read()
    assert re.search(r"BLPOP", source, re.IGNORECASE), "processor.c does not issue BLPOP"
    assert "raw_logs" in source, "processor.c does not reference the raw_logs list"
    assert "tolower" in source.lower(), "processor.c does not implement lowercase normalization"
    compiled = "/tmp/processor_source_check"
    result = run(["gcc", PROCESSOR_SOURCE, "-O2", "-o", compiled, "-lhiredis"], timeout=30)
    assert result.returncode == 0, "processor.c does not compile:\n" + result.stderr.decode(errors="replace")
    assert_elf_executable(compiled)


def test_processor_redis_deduplication_and_aggregation():
    # Stop any prior submitted daemon so its in-memory state cannot affect this test.
    subprocess.run(["pkill", "-x", "processor"], stdout=subprocess.DEVNULL,
                   stderr=subprocess.DEVNULL)
    time.sleep(0.3)
    redis("FLUSHDB")
    try:
        os.remove(STATS)
    except FileNotFoundError:
        pass

    subprocess.Popen([PROCESSOR], cwd="/home/user", stdin=subprocess.DEVNULL,
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                     start_new_session=True)
    time.sleep(0.5)

    ids = [secrets.token_hex(8) for _ in range(20)]
    first_batch = [
        "bad_id,10,Good Text,500",
        f"{secrets.token_hex(8)},0,Good Text,500",
        f"{secrets.token_hex(8)},10,Bad!,500",
        f"{secrets.token_hex(8)},10,{'X' * 101},500",
        f"{secrets.token_hex(8)},10,Good Text,nope",
    ]
    first_batch += [f"{ids[i]},100,MiXeD Case Text,{i + 1}" for i in range(10)]
    first_batch.append(f"{ids[0]},101,Duplicate Must Drop,999")
    random.SystemRandom().shuffle(first_batch[:5])
    redis("RPUSH", "raw_logs", *first_batch)

    expected10 = '{"total_valid_records": 10, "sum_values": 55.00, "max_value": 10.00}'
    wait_for_stats(expected10)
    assert wait_until(lambda: redis("LLEN", "raw_logs") == "0", 5), "processor did not drain Redis"

    second_batch = [f"{ids[i]},200,Another MIXED Text,{i + 1}" for i in range(10, 19)]
    redis("RPUSH", "raw_logs", *second_batch)
    assert wait_until(lambda: redis("LLEN", "raw_logs") == "0", 5), "processor did not consume records"
    time.sleep(0.3)
    with open(STATS, "r", encoding="utf-8") as f:
        assert f.read() == expected10, "stats.json was written before another 10 valid records"

    redis("RPUSH", "raw_logs", f"{ids[19]},200,Last Valid Record,20")
    expected20 = '{"total_valid_records": 20, "sum_values": 210.00, "max_value": 20.00}'
    wait_for_stats(expected20)
    parsed = json.loads(expected20)
    with open(STATS, "r", encoding="utf-8") as f:
        assert json.loads(f.read()) == parsed
    assert subprocess.run(["pgrep", "-x", "processor"], stdout=subprocess.DEVNULL).returncode == 0, \
        "processor daemon is not left running"


def test_nginx_serves_home_user_www_on_8080():
    assert subprocess.run(["pgrep", "-x", "nginx"], stdout=subprocess.DEVNULL).returncode == 0, \
        "Nginx is not running"
    marker_name = "verifier_" + secrets.token_hex(12) + ".txt"
    marker = secrets.token_hex(32).encode()
    marker_path = os.path.join("/home/user/www", marker_name)
    with open(marker_path, "wb") as f:
        f.write(marker)
    try:
        def fetches_marker():
            try:
                with urllib.request.urlopen(f"http://127.0.0.1:8080/{marker_name}", timeout=1) as response:
                    return response.status == 200 and response.read() == marker
            except Exception:
                return False
        assert wait_until(fetches_marker, 5), "Nginx does not serve /home/user/www on port 8080"
    finally:
        try:
            os.remove(marker_path)
        except FileNotFoundError:
            pass
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
