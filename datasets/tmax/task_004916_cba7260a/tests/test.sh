#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import stat
import string
import subprocess


def test_test_results_log():
    log_path = "/home/user/test_results.log"
    assert os.path.isfile(log_path), f"Log file {log_path} does not exist. Did you run the tests and redirect output?"

    with open(log_path, "r") as f:
        content = f.read().strip()

    assert content == "ALL TESTS PASSED", f"Expected log file to contain 'ALL TESTS PASSED', but got: {content}"


def test_requested_executable_exists_and_runs():
    executable = "/home/user/test_validator"
    assert os.path.isfile(executable), "The requested /home/user/test_validator executable is missing."
    assert os.access(executable, os.X_OK), "/home/user/test_validator is not executable."
    with open(executable, "rb") as f:
        assert f.read(4) == b"\x7fELF", "/home/user/test_validator is not a compiled ELF executable."

    result = subprocess.run([executable], cwd="/home/user", capture_output=True, text=True, timeout=10)
    assert result.returncode == 0, f"The requested executable failed:\n{result.stderr}"
    assert result.stdout.strip() == "ALL TESTS PASSED", f"Unexpected executable output: {result.stdout!r}"


def test_validator_cpp_fixes():
    cpp_path = "/home/user/validator.cpp"
    assert os.path.isfile(cpp_path), f"File {cpp_path} is missing."

    with open(cpp_path, "r") as f:
        content = f.read()

    # Check that the rate limit threshold was updated to 100
    assert ">= 100" in content, "The rate limit threshold in check_rate_limit was not correctly updated to 100."

    # Check that the regex was updated to include quotes around the data value
    assert '\"[a-zA-Z]+\"' in content or r'\"[a-zA-Z]+\"' in content or '"[a-zA-Z]+"' in content or r'\"[a-zA-Z]+\"' in content.replace('\\"', '"'), "The regex in validate_payload does not correctly account for the string quotes around the data value."


def test_compilation_and_execution():
    # Compile the files to ensure they are valid and tests pass
    compile_cmd = [
        "g++", "-std=c++17",
        "/home/user/test_validator.cpp",
        "/home/user/validator.cpp",
        "-o", "/tmp/verify_test"
    ]

    compile_result = subprocess.run(compile_cmd, capture_output=True, text=True)
    assert compile_result.returncode == 0, f"Compilation failed:\n{compile_result.stderr}"

    run_result = subprocess.run(["/tmp/verify_test"], capture_output=True, text=True)
    assert run_result.returncode == 0, f"Running the compiled executable failed (assertion error likely):\n{run_result.stderr}"
    assert "ALL TESTS PASSED" in run_result.stdout, "The executable did not output the expected success message."


def build_behavior_runner():
    source = r'''
#include "validator.h"
#include <iostream>
#include <string>
#include <vector>

static std::string decode_hex(const std::string& encoded) {
    if (encoded == "-") return "";
    std::string result;
    for (size_t i = 0; i < encoded.size(); i += 2) {
        unsigned int value = 0;
        for (size_t j = 0; j < 2; ++j) {
            char c = encoded[i + j];
            value = value * 16 + (c >= '0' && c <= '9' ? c - '0' : c >= 'a' && c <= 'f' ? c - 'a' + 10 : c - 'A' + 10);
        }
        result.push_back(static_cast<char>(value));
    }
    return result;
}

int main(int argc, char** argv) {
    if (argc != 2) return 2;
    if (std::string(argv[1]) == "payload") {
        WsValidator validator;
        std::string encoded;
        while (std::cin >> encoded)
            std::cout << (validator.validate_payload(decode_hex(encoded)) ? '1' : '0') << '\n';
        return 0;
    }
    if (std::string(argv[1]) == "rate") {
        size_t count;
        while (std::cin >> count) {
            WsValidator validator;
            for (size_t i = 0; i < count; ++i) {
                long long timestamp;
                std::cin >> timestamp;
                std::cout << (validator.check_rate_limit(timestamp) ? '1' : '0');
            }
            std::cout << '\n';
        }
        return 0;
    }
    return 2;
}
'''
    with open("/tmp/behavior_runner.cpp", "w") as f:
        f.write(source)
    result = subprocess.run([
        "g++", "-std=c++17", "-I/home/user",
        "/tmp/behavior_runner.cpp", "/home/user/validator.cpp",
        "-o", "/tmp/behavior_runner"
    ], capture_output=True, text=True)
    assert result.returncode == 0, f"Hidden behavior harness failed to compile:\n{result.stderr}"


def test_exact_payload_language():
    build_behavior_runner()
    rng = random.Random(918273)
    candidates = [
        '{"id": 0, "data": "A"}',
        '{"id": 1234567890, "data": "alphabeticONLY"}',
        '', '{}',
        '{"id": 1, "data": ""}',
        '{"id": , "data": "abc"}',
        '{"id": -1, "data": "abc"}',
        '{"id": +1, "data": "abc"}',
        '{"id": 1.0, "data": "abc"}',
        '{"id": 1, "data": abc}',
        '{"id": 1, "data": "abc123"}',
        '{"id": 1, "data": "abc def"}',
        '{"id": 1, "data": "abc_"}',
        '{"id": 1, "data": "abc", "extra": 2}',
        ' {"id": 1, "data": "abc"}',
        '{"id":1, "data": "abc"}',
        '{"id": 1,"data": "abc"}',
        '{"data": "abc", "id": 1}',
        '{"id": 1, "data":"abc"}',
        '{"id": 1, "data": "abc"} ',
        '{\n"id": 1, "data": "abc"}',
    ]

    for _ in range(80):
        digits = ''.join(rng.choice(string.digits) for _ in range(rng.randint(1, 20)))
        letters = ''.join(rng.choice(string.ascii_letters) for _ in range(rng.randint(1, 25)))
        valid = f'{{"id": {digits}, "data": "{letters}"}}'
        candidates.append(valid)
        candidates.extend([
            valid.replace('"data": "', '"data": ', 1).replace('"}', '}', 1),
            valid.replace(', "data"', ',  "data"', 1),
            valid.replace('"id": ', '"id": "', 1).replace(', "data"', '", "data"', 1),
            valid[:-1] + ', "x": 0}',
        ])

    arbitrary_chars = '{}[]":, +-_.\\' + string.ascii_letters + string.digits + ' \t\n'
    for _ in range(250):
        candidates.append(''.join(rng.choice(arbitrary_chars) for _ in range(rng.randint(0, 70))))

    expected = ['1' if re.fullmatch(r'\{"id": [0-9]+, "data": "[A-Za-z]+"\}', value) else '0' for value in candidates]
    encoded = '\n'.join(value.encode('utf-8').hex() or '-' for value in candidates) + '\n'
    result = subprocess.run(["/tmp/behavior_runner", "payload"], input=encoded, capture_output=True, text=True, timeout=15)
    assert result.returncode == 0, f"Payload behavior harness failed:\n{result.stderr}"
    actual = result.stdout.splitlines()
    assert actual == expected, "validate_payload accepts a string outside the exact format or rejects a valid format."


def test_rate_limit_uses_last_accepted_timestamp():
    build_behavior_runner()
    rng = random.Random(564738)
    sequences = [
        [0, 99, 100, 199, 200, 299, 300],
        [1000, 1099, 1050, 1100, 1101, 1199, 1200],
        [100, 50, 199, 200, 150, 300],
        [-1000, -1, 0, 99, 100, 101, 200],
        [5000, 4999, 5099, 5100, 5100, 5200],
    ]
    for _ in range(60):
        current = rng.randint(-500, 1500)
        sequence = []
        for _ in range(rng.randint(8, 35)):
            current += rng.choice([-250, -101, -100, -1, 0, 1, 9, 10, 50, 99, 100, 101, 175, 400])
            sequence.append(current)
        sequences.append(sequence)

    expected = []
    for sequence in sequences:
        last = 0
        bits = []
        for timestamp in sequence:
            accepted = timestamp - last >= 100
            bits.append('1' if accepted else '0')
            if accepted:
                last = timestamp
        expected.append(''.join(bits))

    data = ''.join(str(len(sequence)) + ' ' + ' '.join(map(str, sequence)) + '\n' for sequence in sequences)
    result = subprocess.run(["/tmp/behavior_runner", "rate"], input=data, capture_output=True, text=True, timeout=15)
    assert result.returncode == 0, f"Rate-limit behavior harness failed:\n{result.stderr}"
    assert result.stdout.splitlines() == expected, "check_rate_limit does not enforce a 100ms interval from the last accepted timestamp."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
