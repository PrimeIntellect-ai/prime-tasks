#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import secrets
import subprocess

import pytest


def test_c_source_exists():
    path = "/home/user/loc_cleaner.c"
    assert os.path.exists(path), f"The C source file {path} is missing."
    assert os.path.isfile(path), f"The path {path} is not a file."


def test_executable_exists():
    path = "/home/user/loc_cleaner"
    assert os.path.exists(path), f"The executable {path} is missing."
    assert os.path.isfile(path), f"The path {path} is not a file."
    assert os.access(path, os.X_OK), f"The file {path} is not executable."
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"The file {path} is not a compiled ELF executable."


def test_clean_locales_content():
    path = "/home/user/clean_locales.ini"
    assert os.path.exists(path), f"The output file {path} is missing."
    assert os.path.isfile(path), f"The path {path} is not a file."

    expected_content = (
        "ERR_FILE_MISSING=Error: File not found\n"
        "MAIN_MENU_OPTIONS=Options\n"
        "MAIN_MENU_PLAY=Start Game\n"
        "TRICKY_VAL=This value has : a colon\n"
        "VALID_EMPTY=\n"
    )

    with open(path, "r") as f:
        actual_content = f.read()

    assert actual_content == expected_content, f"The content of {path} is incorrect. Expected:\n{expected_content}\nGot:\n{actual_content}"


def expected_output(records):
    output = []
    for line in records:
        if ":" not in line:
            continue
        key, value = line.split(":", 1)
        key = key.strip(" \t")
        value = value.strip(" \t")
        if re.fullmatch(r"[A-Z_]+", key):
            output.append(f"{key}={value}\n")
    return "".join(output).encode("ascii")


def run_and_check(program, records, final_newline):
    data = "\n".join(records)
    if final_newline:
        data += "\n"
    result = subprocess.run(
        [program],
        input=data.encode("ascii"),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=5,
    )
    assert result.returncode == 0, (
        f"{program} exited with status {result.returncode}; stderr was: "
        f"{result.stderr.decode('ascii', errors='replace')}"
    )
    expected = expected_output(records)
    assert result.stdout == expected, (
        f"{program} produced incorrect output.\n"
        f"Expected: {expected!r}\nGot: {result.stdout!r}"
    )


@pytest.fixture(scope="module")
def rebuilt_executable(tmp_path_factory):
    output = tmp_path_factory.mktemp("build") / "loc_cleaner_rebuilt"
    result = subprocess.run(
        ["gcc", "-std=c11", "-O2", "/home/user/loc_cleaner.c", "-o", str(output)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=15,
    )
    assert result.returncode == 0, (
        "loc_cleaner.c did not compile successfully:\n"
        + result.stderr.decode("utf-8", errors="replace")
    )
    return str(output)


def make_cases():
    records = [
        "  KEY  :  value  ",
        "TABS\t:\ttrimmed\t",
        "MULTI_COLON:one:two:three",
        "EMPTY_VALUE:    \t",
        "_:underscore key",
        "___:all underscores",
        ":missing key",
        "   :also missing",
        "lower:invalid",
        "HAS9:invalid",
        "BAD-KEY:invalid",
        "BAD KEY:invalid",
        "BAD\tKEY:invalid",
        "NO_COLON_AT_ALL",
        "KEEP_SPACES:middle  spaces stay",
        "KEEP_TABS:middle\ttab stays",
        "LONG_VALUE:" + ("Ab:c_ " * 50),
    ]

    rng = random.Random(secrets.randbits(128))
    alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ_"
    value_chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 _:-\t"
    for _ in range(80):
        if rng.randrange(3) != 0:
            key = "".join(rng.choice(alphabet) for _ in range(rng.randint(1, 24)))
            value = "".join(rng.choice(value_chars) for _ in range(rng.randint(0, 60)))
            records.append(
                (" " * rng.randint(0, 3))
                + ("\t" * rng.randint(0, 2))
                + key
                + (" " * rng.randint(0, 3))
                + ":"
                + ("\t" * rng.randint(0, 2))
                + value
                + (" " * rng.randint(0, 3))
            )
        elif rng.randrange(2):
            bad_key = rng.choice(["bad", "BAD-KEY", "A1", "A B", "A\tB", ""])
            records.append(f" {bad_key} :discard me")
        else:
            records.append("line without a delimiter " + str(rng.randrange(1000000)))
    rng.shuffle(records)
    return records


def test_cleaner_behavior(rebuilt_executable):
    records = make_cases()
    programs = ["/home/user/loc_cleaner", rebuilt_executable]
    for program in programs:
        run_and_check(program, records, final_newline=True)
        run_and_check(program, list(reversed(records)), final_newline=False)


def test_cleaner_raw_stream_behavior(rebuilt_executable):
    with open("/home/user/raw_locales.txt", "r", encoding="ascii") as f:
        records = f.read().splitlines()
    for program in ["/home/user/loc_cleaner", rebuilt_executable]:
        run_and_check(program, records, final_newline=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
