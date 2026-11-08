#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import os
import random
import re
import socket
import subprocess
import time

import pytest

DETECTOR = "/home/user/bin/detector"
PROCESSOR = "/home/user/bin/log_processor"
PROCESSOR_SOURCE = "/home/user/src/log_processor.cpp"


def assert_elf_executable(path):
    assert os.path.isfile(path), f"Binary not found at {path}"
    assert os.access(path, os.X_OK), f"Binary at {path} is not executable"
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{path} is not a compiled ELF binary"


def run_detector(payload):
    return subprocess.run(
        [DETECTOR],
        input=(json.dumps(payload, separators=(",", ":")) + "\n").encode(),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=3,
    ).returncode


def test_detector_exists_and_executable():
    assert_elf_executable(DETECTOR)


def test_adversarial_corpus():
    clean_files = sorted(glob.glob("/home/user/corpus/clean/*.json"))
    evil_files = sorted(glob.glob("/home/user/corpus/evil/*.json"))
    assert clean_files, "No JSON files found in clean corpus"
    assert evil_files, "No JSON files found in evil corpus"

    clean_failed = []
    for path in clean_files:
        with open(path, "rb") as f:
            result = subprocess.run([DETECTOR], stdin=f, timeout=3)
        if result.returncode != 0:
            clean_failed.append(os.path.basename(path))

    evil_failed = []
    for path in evil_files:
        with open(path, "rb") as f:
            result = subprocess.run([DETECTOR], stdin=f, timeout=3)
        if result.returncode != 1:
            evil_failed.append(os.path.basename(path))

    assert not clean_failed, f"Clean files rejected: {clean_failed}"
    assert not evil_failed, f"Evil files accepted: {evil_failed}"


def test_detector_general_timezone_validation():
    rng = random.SystemRandom()
    valid = {"Z", "+00:00", "-00:00", "+14:00", "-12:00"}
    while len(valid) < 90:
        sign = rng.choice(("+", "-"))
        if sign == "+":
            hour = rng.randrange(0, 15)
            minute = 0 if hour == 14 else rng.randrange(0, 60)
        else:
            hour = rng.randrange(0, 13)
            minute = 0 if hour == 12 else rng.randrange(0, 60)
        valid.add(f"{sign}{hour:02d}:{minute:02d}")

    invalid = {
        "+14:01", "+14:59", "-12:01", "-12:59", "+15:00", "-13:00",
        "+00:60", "-04:60", "+99:99", "00:00", "+1:00", "+01:0",
        "+01:000", "+01", "+0100", "+01-00", "++01:00", "--01:00",
        "+ 01:00", "+01:00junk", "junk-01:00", "invalid", "z", "",
    }
    for _ in range(50):
        sign = rng.choice(("+", "-"))
        if rng.choice((True, False)):
            invalid.add(f"{sign}{rng.randrange(15, 100):02d}:{rng.randrange(60):02d}")
        else:
            invalid.add(f"{sign}{rng.randrange(15):02d}:{rng.randrange(60, 100):02d}")

    nonce = rng.randrange(1 << 60)
    for tz in valid:
        payload = {"message": f"valid-{nonce}", "timezone": tz, "timestamp": rng.randrange(1, 2_000_000_000)}
        assert run_detector(payload) == 0, f"Valid timezone rejected: {tz!r}"
    for tz in invalid:
        payload = {"timestamp": rng.randrange(1, 2_000_000_000), "timezone": tz, "message": f"invalid-{nonce}"}
        assert run_detector(payload) == 1, f"Invalid timezone accepted: {tz!r}"


def test_log_processor_exists_and_executable():
    assert_elf_executable(PROCESSOR)


def test_log_processor_source_contains_utc_conversion_formula():
    assert os.path.isfile(PROCESSOR_SOURCE), f"Missing source file {PROCESSOR_SOURCE}"
    source = open(PROCESSOR_SOURCE, encoding="utf-8").read()
    code = re.sub(r"/\*.*?\*/", "", source, flags=re.S)
    code = re.sub(r"//.*", "", code)
    assert re.search(r'["\\]timestamp', code), "Processor does not parse the timestamp field"

    statements = code.split(";")
    formula_found = False
    for statement in statements:
        lower = statement.lower()
        has_time = any(word in lower for word in ("timestamp", "unix", "epoch", "utc"))
        has_offset = "offset_minutes" in lower or "total_offset" in lower
        if has_time and has_offset and "60" in lower and "-" in statement and "=" in statement:
            formula_found = True
            break
    assert formula_found, "No UTC = timestamp - signed_offset_minutes * 60 conversion was found"


def redis_command(*parts):
    request = f"*{len(parts)}\r\n".encode()
    for part in parts:
        data = str(part).encode()
        request += f"${len(data)}\r\n".encode() + data + b"\r\n"
    with socket.create_connection(("127.0.0.1", 6379), timeout=2) as sock:
        sock.sendall(request)
        data = sock.recv(4096)
    if not data:
        raise RuntimeError("Redis returned no response")
    if data[:1] == b"$":
        first, rest = data.split(b"\r\n", 1)
        length = int(first[1:])
        return None if length == -1 else rest[:length].decode()
    if data[:1] == b":" or data[:1] == b"+":
        return data[1:].split(b"\r\n", 1)[0].decode()
    raise RuntimeError(f"Redis error response: {data!r}")


def wait_for_port(port, process, timeout=12):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if process.poll() is not None:
            raise AssertionError(f"Process exited before opening port {port}, code {process.returncode}")
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=.2):
                return
        except OSError:
            time.sleep(.1)
    raise AssertionError(f"Timed out waiting for TCP port {port}")


def send_log(payload):
    data = (json.dumps(payload) + "\n").encode()
    with socket.create_connection(("127.0.0.1", 8080), timeout=2) as sock:
        sock.sendall(data)


def test_log_processor_runtime_redis_bounds_and_memory_safety():
    rebuilt = "/tmp/log_processor_verified"
    subprocess.run([
        "g++", "-O2", "-std=c++17", PROCESSOR_SOURCE, "-o", rebuilt,
        "-lhiredis", "-lpthread",
    ], check=True, timeout=60)
    assert_elf_executable(rebuilt)

    subprocess.run(["pkill", "-f", "/home/user/bin/log_processor"], check=False)
    subprocess.run(["pkill", "-f", "/tmp/log_processor_verified"], check=False)
    subprocess.run(["pkill", "redis-server"], check=False)
    time.sleep(.3)

    redis_proc = subprocess.Popen([
        "redis-server", "--port", "6379", "--save", "", "--appendonly", "no",
    ], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    processor_proc = None
    valgrind_log = "/tmp/log_processor.valgrind"
    try:
        wait_for_port(6379, redis_proc)
        redis_command("FLUSHALL")
        processor_proc = subprocess.Popen([
            "valgrind", "--leak-check=full", "--show-leak-kinds=definite",
            "--errors-for-leak-kinds=definite", "--error-exitcode=97",
            f"--log-file={valgrind_log}", rebuilt,
        ], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        wait_for_port(8080, processor_proc)

        valid = ["Z", "+05:30", "+14:00", "-12:00"]
        invalid = ["+14:01", "-12:01", "+15:00", "-13:00", "+04:60", "invalid"]
        base = random.SystemRandom().randrange(1_000_000_000, 1_900_000_000)

        for index, tz in enumerate(valid):
            send_log({"timestamp": base + index, "timezone": tz, "metric": "requests"})
        for index, tz in enumerate(invalid):
            send_log({"timestamp": base + 100 + index, "timezone": tz, "metric": "requests"})

        deadline = time.time() + 4
        count = None
        while time.time() < deadline:
            count = redis_command("GET", "processed_logs")
            if count == str(len(valid)):
                break
            time.sleep(.1)
        assert count == str(len(valid)), (
            f"processed_logs should increase only for valid timezone payloads; got {count!r}"
        )
        assert processor_proc.poll() is None, "Processor crashed while handling timezone edge cases"
    finally:
        if processor_proc is not None and processor_proc.poll() is None:
            processor_proc.terminate()
            try:
                processor_proc.wait(timeout=8)
            except subprocess.TimeoutExpired:
                processor_proc.kill()
                processor_proc.wait(timeout=3)
        if redis_proc.poll() is None:
            redis_proc.terminate()
            try:
                redis_proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                redis_proc.kill()

    assert os.path.isfile(valgrind_log), "Valgrind did not produce a report"
    report = open(valgrind_log, encoding="utf-8", errors="replace").read()
    definite = re.findall(r"definitely lost:\s*([0-9,]+) bytes", report)
    assert definite, f"Valgrind report lacks a definite-leak summary:\n{report}"
    assert all(int(value.replace(",", "")) == 0 for value in definite), (
        f"Processor leaked memory while handling malformed timezone payloads:\n{report}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
