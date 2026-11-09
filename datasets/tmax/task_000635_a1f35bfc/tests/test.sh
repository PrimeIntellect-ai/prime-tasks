#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess

SOURCE_FILE = "/home/user/log_processor.c"
PROGRAM_FILE = "/home/user/log_processor"
INPUT_FILE = "/home/user/raw_logs.txt"
OUTPUT_FILE = "/home/user/rolling_sim.csv"


def test_rolling_sim_output():
    output_file = "/home/user/rolling_sim.csv"
    assert os.path.exists(output_file), f"Output file {output_file} does not exist."
    assert os.path.isfile(output_file), f"{output_file} is not a file."

    expected_content = (
        "Line,Jaccard,Rolling_Avg\n"
        "1,0.0000,0.0000\n"
        "2,1.0000,0.5000\n"
        "3,0.6250,0.5417\n"
        "4,0.0000,0.5417\n"
        "5,0.6000,0.4083"
    )

    with open(output_file, "r") as f:
        actual_content = f.read().strip()

    assert actual_content == expected_content, (
        f"Content of {output_file} does not match the expected output.\n"
        f"Expected:\n{expected_content}\n"
        f"Got:\n{actual_content}"
    )


def test_c_source_exists():
    source_file = "/home/user/log_processor.c"
    assert os.path.exists(source_file), f"C source file {source_file} is missing."
    assert os.path.isfile(source_file), f"{source_file} is not a file."


def test_compiled_program_exists_and_is_elf():
    assert os.path.exists(PROGRAM_FILE), f"Compiled program {PROGRAM_FILE} is missing."
    assert os.path.isfile(PROGRAM_FILE), f"{PROGRAM_FILE} is not a file."
    assert os.access(PROGRAM_FILE, os.X_OK), f"{PROGRAM_FILE} is not executable."
    with open(PROGRAM_FILE, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{PROGRAM_FILE} is not a compiled ELF program."


def expected_csv(lines):
    previous = set()
    scores = []
    rows = ["Line,Jaccard,Rolling_Avg"]

    for number, line in enumerate(lines, 1):
        current = {token.lower() for token in re.findall(r"[A-Za-z0-9]+", line)}
        union = previous | current
        similarity = 1.0 if not union else len(previous & current) / len(union)
        scores.append(similarity)
        rolling = sum(scores[-3:]) / len(scores[-3:])
        rows.append(f"{number},{similarity:.4f},{rolling:.4f}")
        previous = current

    return "\n".join(rows)


def test_source_compiles_and_program_handles_additional_inputs():
    compile_result = subprocess.run(
        ["gcc", SOURCE_FILE, "-o", PROGRAM_FILE],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert compile_result.returncode == 0, (
        "C source did not compile with the required command:\n" + compile_result.stderr
    )

    with open(PROGRAM_FILE, "rb") as f:
        assert f.read(4) == b"\x7fELF", "gcc output is not an ELF executable."

    random_tokens = [secrets.token_hex(8) for _ in range(4)]
    a, b, c, d = random_tokens
    cases = [
        ["!!!", "   ", "Alpha alpha ALPHA", "alpha,beta", "BETA beta"],
        ["A1 b2 C3 c3", "a1---B2 d4", "d4", "", "d4 d4"],
        [
            f"{a} {b} {b}",
            f"{b},{c}",
            f"{a};{c};{d}",
            f"{d} {d} {a}",
            "punctuation_only!!!",
        ],
    ]

    with open(INPUT_FILE, "rb") as f:
        original_input = f.read()
    with open(OUTPUT_FILE, "rb") as f:
        original_output = f.read()

    try:
        for lines in cases:
            with open(INPUT_FILE, "w", newline="") as f:
                f.write("\n".join(lines) + "\n")

            run_result = subprocess.run(
                [PROGRAM_FILE],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=10,
            )
            assert run_result.returncode == 0, (
                f"Program failed with exit code {run_result.returncode}.\n"
                f"stderr:\n{run_result.stderr}"
            )
            assert os.path.isfile(OUTPUT_FILE), "Program did not create rolling_sim.csv."

            with open(OUTPUT_FILE, "r") as f:
                actual = f.read().strip()
            expected = expected_csv(lines)
            assert actual == expected, (
                f"Incorrect output for input {lines!r}.\n"
                f"Expected:\n{expected}\nGot:\n{actual}"
            )
    finally:
        with open(INPUT_FILE, "wb") as f:
            f.write(original_input)
        with open(OUTPUT_FILE, "wb") as f:
            f.write(original_output)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
