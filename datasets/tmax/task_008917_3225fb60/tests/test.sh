#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import string
import subprocess
import pytest


def test_root_cause_json_exists_and_valid():
    """Test that root_cause.json exists and is valid JSON."""
    file_path = "/home/user/root_cause.json"
    assert os.path.exists(file_path), f"Expected file {file_path} is missing."
    assert os.path.isfile(file_path), f"Expected {file_path} to be a file."

    try:
        with open(file_path, "r") as f:
            json.load(f)
    except json.JSONDecodeError as e:
        pytest.fail(f"File {file_path} is not valid JSON: {e}")


def test_root_cause_json_content():
    """Test that root_cause.json contains exactly the correct findings."""
    file_path = "/home/user/root_cause.json"
    assert os.path.exists(file_path), f"Expected file {file_path} is missing."

    with open(file_path, "r") as f:
        data = json.load(f)

    expected_keys = {"crash_timestamp", "crashing_seq_id", "buggy_function"}
    assert set(data.keys()) == expected_keys, \
        f"Expected exactly keys {sorted(expected_keys)}, got {sorted(data.keys())}."
    assert data["crash_timestamp"] == "2024-05-10 14:32:08", \
        f"Expected crash_timestamp to be '2024-05-10 14:32:08', got {data['crash_timestamp']}."
    assert data["crashing_seq_id"] == 102, \
        f"Expected crashing_seq_id to be 102, got {data['crashing_seq_id']}."
    assert data["buggy_function"] == "process_metrics", \
        f"Expected buggy_function to be 'process_metrics', got {data['buggy_function']}."


def test_fixed_cpp_exists_and_compiles():
    """Test that metrics_processor_fixed.cpp exists and compiles successfully."""
    file_path = "/home/user/metrics_processor_fixed.cpp"
    assert os.path.exists(file_path), f"Expected file {file_path} is missing."
    assert os.path.isfile(file_path), f"Expected {file_path} to be a file."

    compile_cmd = ["g++", "-std=c++17", "-o", "/tmp/fixed_test", file_path]
    try:
        subprocess.run(compile_cmd, check=True, stdout=subprocess.PIPE,
                       stderr=subprocess.PIPE, text=True, timeout=30)
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Compilation of {file_path} failed.\nCommand: {' '.join(compile_cmd)}\nError output:\n{e.stderr}")

    assert os.path.exists("/tmp/fixed_test"), \
        "Compiled executable /tmp/fixed_test was not created."

    result = subprocess.run(["/tmp/fixed_test"], stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, text=True, timeout=5)
    assert result.returncode == 0, f"Compiled executable failed: {result.stderr}"
    assert result.stdout == "Metrics processor running...\n", \
        f"The fixed program's entry point changed unexpectedly: {result.stdout!r}"


def test_process_metrics_functionality_and_bounds_safety():
    """Exercise the submitted function under ASan, including oversized packets."""
    driver_source = r'''
#include <cstdint>
#include <cstdlib>
#include <iostream>
#include <string>
#include <vector>

#define main metrics_processor_submission_main
#include "/home/user/metrics_processor_fixed.cpp"
#undef main

int main(int argc, char** argv) {
    if (argc != 4) return 64;
    const uint32_t seq = static_cast<uint32_t>(std::stoul(argv[1]));
    const unsigned long parsed_type = std::stoul(argv[2]);
    if (parsed_type > 255) return 65;
    const uint8_t type = static_cast<uint8_t>(parsed_type);
    const std::string payload(argv[3]);

    std::vector<uint8_t> packet;
    packet.reserve(5 + payload.size());
    packet.push_back(static_cast<uint8_t>(seq & 0xff));
    packet.push_back(static_cast<uint8_t>((seq >> 8) & 0xff));
    packet.push_back(static_cast<uint8_t>((seq >> 16) & 0xff));
    packet.push_back(static_cast<uint8_t>((seq >> 24) & 0xff));
    packet.push_back(type);
    packet.insert(packet.end(), payload.begin(), payload.end());
    process_metrics(packet);
    return 0;
}
'''
    with open("/tmp/metrics_driver.cpp", "w") as f:
        f.write(driver_source)

    compile_cmd = [
        "g++", "-std=c++17", "-O0", "-g", "-fno-omit-frame-pointer",
        "-fsanitize=address", "-o", "/tmp/metrics_driver",
        "/tmp/metrics_driver.cpp"
    ]
    result = subprocess.run(compile_cmd, stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, text=True, timeout=30)
    assert result.returncode == 0, \
        f"Could not build behavioral test driver:\n{result.stderr}"

    rng = random.Random(int.from_bytes(os.urandom(16), "big"))
    alphabet = string.ascii_letters + string.digits

    cases = []
    for payload_len in (1, 7, 31):
        seq = rng.randrange(1, 2**32)
        payload = "".join(rng.choice(alphabet) for _ in range(payload_len))
        cases.append((seq, 1, payload, f"Processing metric seq {seq}\n"))

    # A 16-byte local buffer permits at most 15 text bytes plus the terminator.
    # Exercise the boundary and several runtime-selected oversized payloads.
    for payload_len in (15, 16, 30, rng.randrange(40, 200), rng.randrange(512, 2048)):
        seq = rng.randrange(1, 2**32)
        payload = "".join(rng.choice(alphabet) for _ in range(payload_len))
        expected = f"High priority metric seq {seq}: {payload[:15]}\n"
        cases.append((seq, 2, payload, expected))

    # Unknown packet types must retain their existing no-op behavior.
    seq = rng.randrange(1, 2**32)
    cases.append((seq, 99, "ignored", ""))

    env = os.environ.copy()
    env["ASAN_OPTIONS"] = "detect_leaks=0:halt_on_error=1:abort_on_error=1"
    for seq, packet_type, payload, expected in cases:
        run = subprocess.run(
            ["/tmp/metrics_driver", str(seq), str(packet_type), payload],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
            timeout=10, env=env
        )
        assert run.returncode == 0, \
            (f"process_metrics failed for type {packet_type} and payload length "
             f"{len(payload)}. This commonly indicates the buffer overflow remains.\n"
             f"stderr:\n{run.stderr}")
        assert run.stdout == expected, \
            (f"process_metrics changed behavior for type {packet_type} and payload "
             f"length {len(payload)}. Expected {expected!r}, got {run.stdout!r}.")
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
