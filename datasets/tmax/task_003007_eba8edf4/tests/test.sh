#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
from decimal import Decimal
from pathlib import Path

import pytest

WORKDIR = Path("/home/user/etl_task")
DATA = WORKDIR / "data.csv"
MATRIX = WORKDIR / "matrix.csv"
OUTPUT = WORKDIR / "reduced_data.csv"
SOURCE = WORKDIR / "etl.c"
BINARY = WORKDIR / "etl"
VALIDATOR = WORKDIR / "validate.sh"


def test_etl_c_exists():
    assert os.path.isfile(SOURCE), "etl.c is missing. You must write the C program."


def test_etl_binary_exists_and_executable():
    assert os.path.isfile(BINARY), "Compiled etl binary is missing. Did you compile etl.c?"
    assert os.access(BINARY, os.X_OK), "etl binary is not executable."
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", "etl must be a compiled native executable."


def test_reduced_data_csv():
    assert os.path.isfile(OUTPUT), "reduced_data.csv is missing. Did you run the etl program?"

    with open(OUTPUT, "r") as f:
        content = f.read().strip()

    expected_content = (
        "UserID,P1,P2\n"
        "1,-0.30,2.30\n"
        "2,2.40,0.30\n"
        "3,1.20,1.40"
    )

    assert content == expected_content, f"Content of {OUTPUT} does not match the expected output. Got:\n{content}"


def test_validate_sh():
    assert os.path.isfile(VALIDATOR), "validate.sh is missing."
    assert os.access(VALIDATOR, os.X_OK), "validate.sh is not executable."

    result = subprocess.run(
        [str(VALIDATOR)], cwd=WORKDIR, capture_output=True, text=True, timeout=10
    )
    assert result.returncode == 0, f"validate.sh did not exit with code 0. Exit code: {result.returncode}"
    assert result.stdout.strip() == "VALID", f"validate.sh did not print 'VALID'. Output: {result.stdout.strip()}"


def make_fixture(records, matrix):
    data_text = "UserID,F1,F2,F3,F4,F5\n" + "\n".join(
        ",".join(str(value) for value in row) for row in records
    ) + "\n"
    matrix_text = "\n".join(
        ",".join(str(value) for value in row) for row in matrix
    ) + "\n"

    sums = {}
    for row in records:
        user_id = row[0]
        sums.setdefault(user_id, [0, 0, 0, 0, 0])
        for i, value in enumerate(row[1:]):
            sums[user_id][i] += value

    lines = ["UserID,P1,P2"]
    decimal_matrix = [[Decimal(str(value)) for value in row] for row in matrix]
    for user_id in sorted(sums):
        projected = []
        for column in range(2):
            value = sum(
                Decimal(sums[user_id][i]) * decimal_matrix[i][column]
                for i in range(5)
            )
            projected.append(format(value, ".2f"))
        lines.append(f"{user_id},{projected[0]},{projected[1]}")
    return data_text, matrix_text, "\n".join(lines)


def run_and_check(program, fixture):
    data_text, matrix_text, expected = fixture
    DATA.write_text(data_text)
    MATRIX.write_text(matrix_text)
    if OUTPUT.exists():
        OUTPUT.unlink()

    result = subprocess.run(
        [str(program)], cwd=WORKDIR, capture_output=True, text=True, timeout=10
    )
    assert result.returncode == 0, (
        f"{program} failed on a test fixture with exit code {result.returncode}. "
        f"stdout={result.stdout!r}, stderr={result.stderr!r}"
    )
    assert OUTPUT.is_file(), f"{program} did not generate reduced_data.csv"
    assert OUTPUT.read_text().strip() == expected, (
        f"{program} produced incorrect output.\n"
        f"Expected:\n{expected}\nGot:\n{OUTPUT.read_text().strip()}"
    )


def test_etl_behavior_on_additional_inputs(tmp_path):
    original_data = DATA.read_bytes()
    original_matrix = MATRIX.read_bytes()
    original_output = OUTPUT.read_bytes() if OUTPUT.exists() else None
    compiled_source = tmp_path / "etl_from_source"

    fixtures = [
        make_fixture(
            [
                (42, 1, 2, 3, 4, 5),
                (7, 2, -1, 0, 3, 1),
                (42, -1, 1, 2, 0, -2),
                (105, 0, 4, -2, 1, 3),
                (7, 3, 2, 1, -1, 0),
            ],
            [
                ("0.5", "-0.25"),
                ("-1", "0.5"),
                ("0.25", "1"),
                ("0", "-0.5"),
                ("1.5", "0.25"),
            ],
        ),
        make_fixture(
            [
                (9, 2, 0, 1, -2, 3),
                (2, 1, 4, -1, 0, 2),
                (9, -1, 3, 2, 1, 0),
                (2, 2, -2, 0, 5, -1),
            ],
            [
                ("-0.5", "1"),
                ("0.25", "0"),
                ("1.5", "-0.5"),
                ("-1", "0.25"),
                ("0.5", "2"),
            ],
        ),
    ]

    try:
        compile_result = subprocess.run(
            ["gcc", "-std=c11", "-O2", str(SOURCE), "-o", str(compiled_source), "-lm"],
            cwd=WORKDIR,
            capture_output=True,
            text=True,
            timeout=20,
        )
        assert compile_result.returncode == 0, (
            "etl.c does not compile successfully. "
            f"Compiler output: {compile_result.stderr}"
        )

        for fixture in fixtures:
            run_and_check(BINARY, fixture)
            run_and_check(compiled_source, fixture)
    finally:
        DATA.write_bytes(original_data)
        MATRIX.write_bytes(original_matrix)
        if original_output is None:
            if OUTPUT.exists():
                OUTPUT.unlink()
        else:
            OUTPUT.write_bytes(original_output)


def test_validate_sh_rejects_invalid_files():
    original_output = OUTPUT.read_bytes() if OUTPUT.exists() else None
    cases = [
        ("UserID,P1,P2\n8,1.25,-3.50\n3,0.00,2.00\n", 0, "VALID"),
        ("UserID,P1,P2,Extra\n8,1.25,-3.50,x\n", 1, "INVALID"),
        ("UserID,P1\n8,1.25\n", 1, "INVALID"),
        ("UserID,P1,P2\n8,,3.50\n", 1, "INVALID"),
        ("UserID,P1,P2\n8,1.25,\n", 1, "INVALID"),
        ("UserID,P1,P2\n8,NaN,3.50\n", 1, "INVALID"),
        ("UserID,P1,P2\n8,1.25,NaN\n", 1, "INVALID"),
    ]

    try:
        for content, expected_code, expected_output in cases:
            OUTPUT.write_text(content)
            result = subprocess.run(
                [str(VALIDATOR)], cwd=WORKDIR, capture_output=True, text=True, timeout=10
            )
            assert result.returncode == expected_code, (
                f"validate.sh returned {result.returncode} for input {content!r}; "
                f"expected {expected_code}"
            )
            assert result.stdout.strip() == expected_output, (
                f"validate.sh printed {result.stdout.strip()!r} for input {content!r}; "
                f"expected {expected_output!r}"
            )
    finally:
        if original_output is None:
            if OUTPUT.exists():
                OUTPUT.unlink()
        else:
            OUTPUT.write_bytes(original_output)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
