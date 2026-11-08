#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess
import tempfile
from decimal import Decimal

PARSER_PATH = "/home/user/parser_fixed"
SOURCE_PATH = "/home/user/parser.cpp"
TRANSACTIONS_PATH = "/home/user/transactions.txt"
CORRECT_SUM = "13345579.1233"


def run_parser(parser_path, input_path):
    try:
        result = subprocess.run(
            [parser_path, input_path],
            capture_output=True,
            text=True,
            check=True,
            timeout=10,
        )
    except subprocess.CalledProcessError as e:
        assert False, (
            f"Running {parser_path} {input_path} failed with return code "
            f"{e.returncode}. Stderr: {e.stderr}"
        )
    except subprocess.TimeoutExpired:
        assert False, f"Running {parser_path} timed out."
    return result.stdout.strip()


def make_unseen_input():
    lines = []
    total = Decimal("0")

    # Values are generated only after the agent has finished, and large FX values
    # make the original float conversion fail by substantially more than 0.0001.
    for i in range(24):
        whole = 10_000_000 + secrets.randbelow(80_000_000)
        frac = 1000 + secrets.randbelow(8999)
        amount = f"{whole}.{frac:04d}"
        kind = "FX_TRADE" if i % 2 == 0 else "REGULAR"
        suffix = "!" if kind == "FX_TRADE" and i % 4 == 0 else ""
        lines.append(f"{kind},{amount}{suffix}")
        total += Decimal(amount)

    # Add small values and both forms of the FX formatting edge case.
    for kind, amount, suffix in [
        ("REGULAR", "0.0001", ""),
        ("FX_TRADE", "12345678.1234", "!"),
        ("FX_TRADE", "87654321.4321", ""),
    ]:
        lines.append(f"{kind},{amount}{suffix}")
        total += Decimal(amount)

    path = tempfile.NamedTemporaryFile(mode="w", delete=False, suffix=".txt")
    try:
        path.write("\n".join(lines) + "\n")
        path.close()
        return path.name, format(total, ".4f")
    except Exception:
        path.close()
        os.unlink(path.name)
        raise


def test_mre_txt_content():
    path = "/home/user/mre.txt"
    assert os.path.isfile(path), f"{path} is missing. You must create an MRE file."

    with open(path, "r") as f:
        content = f.read().strip()

    expected_mre = "FX_TRADE,12345678.1234!"
    assert content == expected_mre, (
        f"Content of {path} is incorrect. Expected '{expected_mre}', found '{content}'."
    )


def test_parser_fixed_exists_and_executable():
    assert os.path.isfile(PARSER_PATH), (
        f"{PARSER_PATH} is missing. Did you compile the fixed C++ code?"
    )
    assert os.access(PARSER_PATH, os.X_OK), f"{PARSER_PATH} is not executable."
    with open(PARSER_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", (
            f"{PARSER_PATH} is not a compiled executable produced by the requested build."
        )


def test_parser_fixed_output():
    assert os.path.isfile(PARSER_PATH), f"Cannot test execution: {PARSER_PATH} is missing."
    assert os.path.isfile(TRANSACTIONS_PATH), (
        f"Cannot test execution: {TRANSACTIONS_PATH} is missing."
    )

    output = run_parser(PARSER_PATH, TRANSACTIONS_PATH)
    assert output == CORRECT_SUM, (
        f"The fixed parser output is incorrect. Expected '{CORRECT_SUM}', got '{output}'."
    )


def test_parser_fixed_on_unseen_input():
    input_path, expected = make_unseen_input()
    try:
        output = run_parser(PARSER_PATH, input_path)
        assert output == expected, (
            f"The fixed parser loses precision or mishandles FX formatting on an unseen "
            f"input. Expected '{expected}', got '{output}'."
        )
    finally:
        os.unlink(input_path)


def test_fixed_source_builds_and_handles_unseen_input():
    assert os.path.isfile(SOURCE_PATH), f"{SOURCE_PATH} is missing."
    built_path = f"/tmp/parser_from_source_{secrets.token_hex(8)}"
    try:
        result = subprocess.run(
            ["g++", "-O2", SOURCE_PATH, "-o", built_path],
            capture_output=True,
            text=True,
            timeout=30,
        )
        assert result.returncode == 0, (
            f"The fixed source does not compile with the requested command. Stderr: {result.stderr}"
        )

        input_path, expected = make_unseen_input()
        try:
            output = run_parser(built_path, input_path)
            assert output == expected, (
                f"A fresh build of parser.cpp is incorrect on an unseen input. "
                f"Expected '{expected}', got '{output}'."
            )
        finally:
            os.unlink(input_path)
    finally:
        if os.path.exists(built_path):
            os.unlink(built_path)


def test_final_sum_txt_content():
    path = "/home/user/final_sum.txt"
    assert os.path.isfile(path), f"{path} is missing. You must save the output to this file."

    with open(path, "r") as f:
        content = f.read().strip()

    assert content == CORRECT_SUM, (
        f"Content of {path} is incorrect. Expected '{CORRECT_SUM}', found '{content}'."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
