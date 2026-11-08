#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import resource
import secrets
import shutil
import string
import subprocess
import tempfile

import pytest

INPUT = "/home/user/data/input.csv"
OUTPUT = "/home/user/data/output.csv"
SOURCE = "/home/user/dedup.c"
EXECUTABLE = "/home/user/dedup"


@pytest.fixture(scope="session", autouse=True)
def restore_original_files():
    saved_input = open(INPUT, "rb").read() if os.path.isfile(INPUT) else None
    saved_output = open(OUTPUT, "rb").read() if os.path.isfile(OUTPUT) else None
    yield
    if saved_input is not None:
        with open(INPUT, "wb") as f:
            f.write(saved_input)
    if saved_output is not None:
        with open(OUTPUT, "wb") as f:
            f.write(saved_output)
    elif os.path.exists(OUTPUT):
        os.unlink(OUTPUT)


def test_output_file_exists():
    assert os.path.isfile(OUTPUT), "/home/user/data/output.csv does not exist"


def test_output_file_content():
    try:
        with open(OUTPUT, "rb") as f:
            content = f.read()
            text = content.decode("utf-8")
    except UnicodeDecodeError:
        pytest.fail("output.csv is not valid UTF-8")

    expected_lines = [
        "1,René,Boss",
        "3,Françoise,Dev",
        "5,Günter,Admin",
        "8,Gunterxy,AdminDup3",
        "9,João,User"
    ]
    actual_lines = [line.strip() for line in text.splitlines() if line.strip()]
    assert actual_lines == expected_lines, f"Output file content does not match expected. Got: {actual_lines}"


def test_c_source_and_executable_exist():
    assert os.path.isfile(SOURCE), "C source code /home/user/dedup.c does not exist"
    assert os.path.isfile(EXECUTABLE), "Executable /home/user/dedup does not exist"
    assert os.access(EXECUTABLE, os.X_OK), "/home/user/dedup is not executable"
    with open(EXECUTABLE, "rb") as f:
        assert f.read(4) == b"\x7fELF", "/home/user/dedup is not a compiled ELF executable"


def levenshtein(a, b):
    if len(a) < len(b):
        a, b = b, a
    previous = list(range(len(b) + 1))
    for i, ca in enumerate(a, 1):
        current = [i]
        for j, cb in enumerate(b, 1):
            current.append(min(current[-1] + 1,
                               previous[j] + 1,
                               previous[j - 1] + (ca != cb)))
        previous = current
    return previous[-1]


def expected_for_rows(rows):
    emitted = []
    last_name = None
    for raw in rows:
        text = raw.decode("iso-8859-1")
        parts = text.rstrip("\r\n").split(",", 2)
        assert len(parts) == 3
        name = parts[1]
        if last_name is None or levenshtein(name, last_name) > 1:
            emitted.append(text.encode("utf-8"))
            last_name = name
    return b"".join(emitted)


def run_and_check(program, rows, expected, memory_limit=None, timeout=20):
    with open(INPUT, "wb") as f:
        for row in rows:
            f.write(row)
    if os.path.exists(OUTPUT):
        os.unlink(OUTPUT)

    def limit_memory():
        if memory_limit is not None:
            resource.setrlimit(resource.RLIMIT_AS, (memory_limit, memory_limit))

    result = subprocess.run(
        [program], cwd="/home/user", stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        timeout=timeout, preexec_fn=limit_memory
    )
    assert result.returncode == 0, (
        f"{program} exited with {result.returncode}; stderr: "
        f"{result.stderr.decode('utf-8', 'replace')[:1000]}"
    )
    assert os.path.isfile(OUTPUT), f"{program} did not create output.csv"
    with open(OUTPUT, "rb") as f:
        actual = f.read(len(expected) + 1)
    try:
        actual.decode("utf-8")
    except UnicodeDecodeError:
        pytest.fail(f"Output from {program} is not valid UTF-8")
    assert actual == expected, f"Incorrect output from {program}: got {actual!r}, expected {expected!r}"


def test_program_behavior_and_streaming():
    token = "".join(secrets.choice(string.ascii_letters) for _ in range(12))
    text_rows = [
        f"101,{token}é,First\n",
        f"102,{token}e,DropCodepointDistanceOne\n",
        f"103,{token}ex,KeepComparedToLastKept\n",
        f"104,{token}éx,DropAgainstLastKept\n",
        f"105,Niño-{token},Keep\n",
        f"106,Nino-{token},DropUnicodeReplacement\n",
        f"107,Ninox-{token},KeepDistanceTwoFromLastKept\n",
        f"108,Ångström-{token},FinalWithoutNewline"
    ]
    rows = [row.encode("iso-8859-1") for row in text_rows]
    expected = expected_for_rows(rows)

    compiled = tempfile.NamedTemporaryFile(prefix="dedup-built-", delete=False)
    compiled.close()
    try:
        build = subprocess.run(
            ["gcc", "-O2", SOURCE, "-o", compiled.name],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
        )
        assert build.returncode == 0, (
            "dedup.c does not compile: " + build.stderr.decode("utf-8", "replace")[:2000]
        )
        os.chmod(compiled.name, 0o755)

        # Exercise both the submitted executable and a fresh build of submitted source.
        for program in (EXECUTABLE, compiled.name):
            run_and_check(program, rows, expected)

        # A file larger than the address-space limit must still work when processed line by line.
        count = 1000000
        role = "R" * 64
        with open(INPUT, "wb") as f:
            for i in range(count):
                f.write(f"{i},SameName,{role}\n".encode("ascii"))
        large_expected = f"0,SameName,{role}\n".encode("utf-8")

        for program in (EXECUTABLE, compiled.name):
            if os.path.exists(OUTPUT):
                os.unlink(OUTPUT)

            def memory_limit():
                limit = 64 * 1024 * 1024
                resource.setrlimit(resource.RLIMIT_AS, (limit, limit))

            result = subprocess.run(
                [program], cwd="/home/user", stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                timeout=45, preexec_fn=memory_limit
            )
            assert result.returncode == 0, (
                f"{program} failed the streaming test with code {result.returncode}; stderr: "
                f"{result.stderr.decode('utf-8', 'replace')[:1000]}"
            )
            assert os.path.isfile(OUTPUT), f"{program} did not create output.csv in streaming test"
            with open(OUTPUT, "rb") as f:
                actual = f.read(len(large_expected) + 1)
            assert actual == large_expected, "Incorrect output for large streaming input"
    finally:
        if os.path.exists(compiled.name):
            os.unlink(compiled.name)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
