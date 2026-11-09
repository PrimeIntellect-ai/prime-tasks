#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import string
import subprocess


def read_nonempty_lines(path):
    with open(path, "r") as f:
        return [line.strip() for line in f.read().splitlines() if line.strip()]


def test_malicious_ips_output():
    output_file = "/home/user/malicious_ips.txt"
    assert os.path.isfile(output_file), f"The output file {output_file} was not generated."

    expected_lines = [
        "Detected SQL_INJECTION from 192.168.1.100",
        "Detected CROSS_SITE_SCRIPTING_XSS from 10.0.0.5",
        "Detected REMOTE_CODE_EXECUTION from 172.16.0.42"
    ]

    content = read_nonempty_lines(output_file)
    assert len(content) == len(expected_lines), f"Expected {len(expected_lines)} lines in {output_file}, but found {len(content)}."

    for i, expected in enumerate(expected_lines):
        assert content[i] == expected, f"Line {i+1} mismatch: expected '{expected}', got '{content[i]}'."


def test_binary_exists():
    binary_file = "/home/user/parse_logs"
    assert os.path.isfile(binary_file), f"The compiled binary {binary_file} does not exist. Did you compile the C file?"
    assert os.access(binary_file, os.X_OK), f"The file {binary_file} is not executable."
    with open(binary_file, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"The file {binary_file} is not a compiled native executable."


def test_c_file_modified():
    c_file = "/home/user/parse_logs.c"
    assert os.path.isfile(c_file), f"The source file {c_file} is missing."

    input_file = "/home/user/attack_logs.dat"
    output_file = "/home/user/malicious_ips.txt"
    binary_file = "/home/user/parse_logs"
    asan_binary = "/tmp/parse_logs_asan"

    with open(c_file, "r") as f:
        content = f.read()
    assert content.strip(), f"The source file {c_file} is empty."

    subprocess.run(
        ["gcc", "-O0", "-g", "-fsanitize=address", "-fno-omit-frame-pointer", c_file, "-o", asan_binary],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )

    old_input = open(input_file, "rb").read()
    old_output_exists = os.path.exists(output_file)
    old_output = open(output_file, "rb").read() if old_output_exists else b""

    rng = random.SystemRandom()
    alphabet = string.ascii_uppercase
    attacks = [
        "".join(rng.choice(alphabet) for _ in range(17)),
        "".join(rng.choice(alphabet) for _ in range(21)),
        "".join(rng.choice(alphabet) for _ in range(24)),
    ]
    ips = [
        f"198.51.100.{rng.randrange(1, 255)}",
        f"203.0.113.{rng.randrange(1, 255)}",
        f"192.0.2.{rng.randrange(1, 255)}",
    ]
    test_input = "".join(f"IP:{ip}:ATTACK:{attack}:\n" for ip, attack in zip(ips, attacks))
    expected = [f"Detected {attack} from {ip}" for ip, attack in zip(ips, attacks)]

    try:
        with open(input_file, "w") as f:
            f.write(test_input)

        for executable in (binary_file, asan_binary):
            if os.path.exists(output_file):
                os.remove(output_file)
            env = os.environ.copy()
            env["ASAN_OPTIONS"] = "detect_leaks=0:halt_on_error=1:abort_on_error=1"
            result = subprocess.run(
                [executable],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                env=env,
                timeout=15,
            )
            assert result.returncode == 0, (
                f"{executable} failed on valid long attack tokens with exit code {result.returncode}. "
                f"stderr: {result.stderr}"
            )
            assert os.path.isfile(output_file), f"{executable} did not generate {output_file}."
            actual = read_nonempty_lines(output_file)
            assert actual == expected, f"{executable} produced incorrect output: expected {expected}, got {actual}."
    finally:
        with open(input_file, "wb") as f:
            f.write(old_input)
        if old_output_exists:
            with open(output_file, "wb") as f:
                f.write(old_output)
        elif os.path.exists(output_file):
            os.remove(output_file)
        if os.path.exists(asan_binary):
            os.remove(asan_binary)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
