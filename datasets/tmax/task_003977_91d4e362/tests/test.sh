#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess

SOURCE_PATH = "/home/user/mc_bvp.c"
EXE_PATH = "/home/user/mc_bvp"
RESULT_PATH = "/home/user/mc_pde_result.txt"


def get_expected():
    state = 42
    total_score = 0
    for _ in range(100000):
        pos = 30
        while pos > 0 and pos < 100:
            state = (1103515245 * state + 12345) & 0x7FFFFFFF
            bit = (state // 65536) % 2
            if bit == 0:
                pos -= 1
            else:
                pos += 1
        if pos == 0:
            total_score += 10
        else:
            total_score += 50
    return f"{total_score / 100000:.4f}"


def code_without_comments_or_literals(source):
    source = re.sub(r"/\*.*?\*/", " ", source, flags=re.S)
    source = re.sub(r"//[^\n]*", " ", source)
    source = re.sub(r'"(?:\\.|[^"\\])*"', '""', source)
    source = re.sub(r"'(?:\\.|[^'\\])*'", "''", source)
    return source


def test_c_source_exists():
    assert os.path.isfile(SOURCE_PATH), "The C source code file /home/user/mc_bvp.c does not exist."


def test_executable_exists():
    assert os.path.isfile(EXE_PATH), f"The executable {EXE_PATH} does not exist."
    assert os.access(EXE_PATH, os.X_OK), f"The file {EXE_PATH} is not executable."
    with open(EXE_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"The executable {EXE_PATH} is not a compiled ELF program."


def test_source_contains_required_lcg_and_walk_logic():
    with open(SOURCE_PATH, "r", encoding="utf-8", errors="replace") as f:
        source = code_without_comments_or_literals(f.read())

    compact = re.sub(r"\s+", "", source)
    assert not re.search(r"\brand\s*\(", source), "The standard rand() function must not be used."

    state_declarations = re.findall(
        r"(?:static)?unsignedlong(?:int)?state=42(?:[uUlL]*);", compact
    )
    assert len(state_declarations) == 1, "The source must define a single unsigned long state initialized to 42."

    assert re.search(
        r"state=\(1103515245(?:[uUlL]*)\*state\+12345(?:[uUlL]*)\)&0x7FFFFFFF(?:[uUlL]*);",
        compact,
    ), "The required LCG state update is missing."
    assert re.search(
        r"intbit=\(state/65536(?:[uUlL]*)\)%2(?:[uUlL]*);", compact
    ), "The required LCG bit extraction is missing."
    assert "if(bit==0)" in compact, "The walk must choose its direction using bit == 0."

    for value in ("100000", "30", "100", "10", "50"):
        assert value in compact, f"The required random-walk constant {value} is missing."

    assert re.search(r"--|-=1|=[A-Za-z_]\w*-1", compact), "No left-step operation was found."
    assert re.search(r"\+\+|\+=1|=[A-Za-z_]\w*\+1", compact), "No right-step operation was found."
    assert "while(" in compact or "for(" in compact, "No random-walk loop was found."


def test_compile_and_execute_submission():
    subprocess.run(
        ["gcc", "-O3", SOURCE_PATH, "-o", EXE_PATH],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=60,
    )
    assert os.path.isfile(EXE_PATH) and os.access(EXE_PATH, os.X_OK)
    with open(EXE_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF"

    if os.path.exists(RESULT_PATH):
        os.remove(RESULT_PATH)

    subprocess.run(
        [EXE_PATH],
        check=True,
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=60,
    )
    assert os.path.isfile(RESULT_PATH), "Executing /home/user/mc_bvp did not create the result file."


def test_result_file_correct():
    result_path = RESULT_PATH
    assert os.path.isfile(result_path), f"The result file {result_path} does not exist."

    with open(result_path, "r") as f:
        raw_content = f.read()
        content = raw_content.strip()

    assert re.fullmatch(r"[0-9]+\.[0-9]{4}\n?", raw_content), "The result must contain one number formatted to exactly 4 decimal places."
    expected = get_expected()
    assert content == expected, f"Expected the result file to contain '{expected}', but got '{content}'."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
