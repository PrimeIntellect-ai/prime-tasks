#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import os
import random
import re
import subprocess


def test_telemetry_source_exists():
    path = "/home/user/telemetry.c"
    assert os.path.exists(path), f"Source file {path} is missing."
    assert os.path.isfile(path), f"{path} is not a file."


def test_telemetry_executable_exists():
    path = "/home/user/telemetry"
    assert os.path.exists(path), f"Executable {path} is missing."
    assert os.path.isfile(path), f"{path} is not a file."
    assert os.access(path, os.X_OK), f"File {path} is not executable."
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{path} is not a compiled executable."


def test_prop_test_exists_and_uses_hypothesis():
    path = "/home/user/prop_test.py"
    assert os.path.exists(path), f"Python test file {path} is missing."
    assert os.path.isfile(path), f"{path} is not a file."

    with open(path, "r", encoding="utf-8") as f:
        content = f.read()

    assert "hypothesis" in content, f"File {path} does not contain 'hypothesis'."
    tree = ast.parse(content, filename=path)
    imported = set()
    names = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            imported.update(alias.name for alias in node.names)
        elif isinstance(node, ast.ImportFrom) and node.module:
            imported.add(node.module)
            imported.update(alias.name for alias in node.names)
        elif isinstance(node, ast.Name):
            names.add(node.id)
        elif isinstance(node, ast.Attribute):
            names.add(node.attr)

    assert any(x == "hypothesis" or x.startswith("hypothesis.") for x in imported)
    assert "strategies" in imported or "strategies" in names or "st" in names
    assert "subprocess" in imported or "subprocess" in names
    assert "/home/user/telemetry" in content
    assert sum(isinstance(node, ast.Assert) for node in ast.walk(tree)) >= 2

    completed = subprocess.run(
        ["python3", "-m", "pytest", path, "-q", "--tb=short"],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=120,
    )
    assert completed.returncode == 0, completed.stdout.decode("utf-8", "replace")


def test_results_log_content():
    path = "/home/user/results.log"
    assert os.path.exists(path), f"Results log file {path} is missing."
    assert os.path.isfile(path), f"{path} is not a file."

    expected_content = (
        "OK A1B2 100\n"
        "OK A1B2 200\n"
        "LIMIT A1B2\n"
        "LIMIT A1B2\n"
        "OK FFFF 5\n"
        "ERROR\n"
        "ERROR\n"
        "OK 1234 99999999\n"
    )

    with open(path, "r") as f:
        content = f.read()

    assert content == expected_content, f"Content of {path} does not match the expected output."

    completed = subprocess.run(
        ["/home/user/telemetry"],
        stdin=open("/home/user/ws_stream.txt", "rb"),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )
    assert completed.returncode == 0, completed.stderr.decode("utf-8", "replace")
    assert completed.stdout.decode("utf-8") == content


def reference_output(payloads):
    counts = {}
    output = []
    pattern = re.compile(rb"DEVICE=([0-9A-F]{4});DATA=([0-9]+)")
    for payload in payloads:
        match = pattern.fullmatch(payload)
        if match is None:
            output.append(b"ERROR")
            continue
        device, value = match.groups()
        seen = counts.get(device, 0)
        counts[device] = seen + 1
        if seen < 2:
            output.append(b"OK " + device + b" " + value)
        else:
            output.append(b"LIMIT " + device)
    return b"\n".join(output) + b"\n"


def run_and_check(program, input_data, expected):
    completed = subprocess.run(
        [program],
        input=input_data,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )
    assert completed.returncode == 0, completed.stderr.decode("utf-8", "replace")
    assert completed.stdout == expected
    assert len(completed.stdout.splitlines()) == len(input_data.splitlines())


def test_source_compiles_and_parser_handles_derived_cases():
    source = "/home/user/telemetry.c"
    with open(source, "r", encoding="utf-8", errors="replace") as f:
        source_text = f.read()
    assert "sscanf" not in source_text, "The parser must not use sscanf."

    rebuilt = "/tmp/telemetry_from_source"
    compilation = subprocess.run(
        ["gcc", "-O2", source, "-o", rebuilt],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert compilation.returncode == 0, compilation.stderr.decode("utf-8", "replace")

    payloads = [
        b"DEVICE=0A0F;DATA=1",
        b"DEVICE=0A0F;DATA=987654321012345678901234567890",
        b"DEVICE=BEEF;DATA=7",
        b"DEVICE=0A0F;DATA=3",
        b"DEVICE=BEEF;DATA=8",
        b"DEVICE=BEEF;DATA=9",
        b"DEVICE=CAFE;DATA=42",
        b"",
        b"DEVICE=ABC;DATA=1",
        b"DEVICE=ABCDE;DATA=1",
        b"DEVICE=abcd;DATA=1",
        b"DEVICE=ABCG;DATA=1",
        b"DEVICE=ABCD;DATA=",
        b"DEVICE=ABCD;DATA=-1",
        b"DEVICE=ABCD;DATA=+1",
        b"DEVICE=ABCD;DATA=12x",
        b"DEVICE=ABCD; DATA=12",
        b" DEVICE=ABCD;DATA=12",
        b"DEVICE=ABCD;DATA=12 ",
        b"DATA=12;DEVICE=ABCD",
        b"DEVICE=ABCD;DATA=12;",
        b"DEVICE=ABCD;DATA=1\x00",
        b"DEVICE=ABCD;DATA=1\r",
    ]

    rng = random.Random(739391)
    alphabet = [x for x in range(256) if x != 10]
    for _ in range(150):
        payloads.append(bytes(rng.choice(alphabet) for _ in range(rng.randrange(0, 65))))

    for i in range(30):
        device = f"{(i * 7919) & 0xffff:04X}".encode("ascii")
        value = str(rng.randrange(1, 10**18)).encode("ascii")
        payloads.append(b"DEVICE=" + device + b";DATA=" + value)

    input_data = b"".join(payload + b"\n" for payload in payloads)
    expected = reference_output(payloads)
    run_and_check("/home/user/telemetry", input_data, expected)
    run_and_check(rebuilt, input_data, expected)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
