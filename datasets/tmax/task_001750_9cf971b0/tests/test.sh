#!/bin/bash
set -e
mkdir -p /logs/verifier

cd /home/user/project
if ! timeout 30s make test; then
    echo "0" > /logs/verifier/reward.txt
    exit 0
fi

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import subprocess

import pytest

PROJECT = "/home/user/project"
SOURCE = os.path.join(PROJECT, "src", "decoder.cpp")
OUTPUT = os.path.join(PROJECT, "output.txt")


def test_output_file_exists():
    output_file = "/home/user/project/output.txt"
    assert os.path.isfile(output_file), f"Expected output file {output_file} does not exist. Did you run 'make test'?"


def test_output_content_correct():
    output_file = "/home/user/project/output.txt"
    assert os.path.isfile(output_file), f"Output file {output_file} is missing."

    expected_output = "Read: Hello\nRead: C++\nRead: Café\nRead: World"

    with open(output_file, "r", encoding="utf-8") as f:
        actual_content = f.read().strip()

    assert actual_content == expected_output, (
        f"The content of {output_file} is incorrect.\n"
        f"Expected:\n{expected_output}\n\n"
        f"Actual:\n{actual_content}\n\n"
        "Ensure your C++ code correctly reads the number of UTF-8 characters, not bytes."
    )


@pytest.fixture(scope="module")
def decoder_binary(tmp_path_factory):
    assert os.path.isfile(SOURCE), f"Expected decoder source {SOURCE} does not exist."
    assert os.path.getsize(SOURCE) > 0, f"Decoder source {SOURCE} is empty."

    binary = tmp_path_factory.mktemp("build") / "decoder"
    result = subprocess.run(
        ["g++", "-std=c++17", "-Wall", "-Wextra", "-o", str(binary), SOURCE],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, f"src/decoder.cpp did not compile:\n{result.stderr}"
    return binary


def test_decoder_handles_utf8_character_lengths(decoder_binary, tmp_path):
    rng = random.SystemRandom()
    alphabet = list("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789") + [
        "é", "ñ", "λ", "Ж", "中", "界", "🙂", "🚀"
    ]

    records = [
        "ASCII",
        "Café",
        "你好世界",
        "a🙂b🚀c",
        "ééééé",
    ]
    for _ in range(12):
        records.append("".join(rng.choice(alphabet) for _ in range(rng.randint(1, 30))))

    data = bytearray()
    for record in records:
        assert len(record) <= 255
        data.append(len(record))
        data.extend(record.encode("utf-8"))

    input_file = tmp_path / "generated.dat"
    input_file.write_bytes(data)

    result = subprocess.run(
        [str(decoder_binary), str(input_file)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )
    assert result.returncode == 0, (
        f"Decoder exited with {result.returncode}. stderr:\n"
        + result.stderr.decode("utf-8", errors="replace")
    )

    expected = "".join(f"Read: {record}\n" for record in records).encode("utf-8")
    assert result.stdout == expected, (
        "Decoder failed on independently generated protocol-v2 records whose "
        "length prefixes count UTF-8 characters rather than bytes."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
