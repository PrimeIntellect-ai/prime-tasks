#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess
import pytest


def test_math_init_conf():
    path = "/home/user/.config/math_init.conf"
    assert os.path.isfile(path), f"Configuration file {path} is missing."
    with open(path, "r") as f:
        content = f.read().strip()
    try:
        val = float(content)
        assert val == 100.0, f"Expected initial state 100.0 in {path}, got {val}"
    except ValueError:
        pytest.fail(f"Configuration file {path} does not contain a valid float: {content}")


def test_recovered_wal():
    path = "/home/user/recovered.wal"
    assert os.path.isfile(path), f"Recovered WAL file {path} is missing."

    with open(path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = [
        "ADD 50.0",
        "MUL 2.0",
        "SUB 25.0",
        "ADD 10.0"
    ]

    assert lines == expected_lines, f"Recovered WAL file {path} does not match expected valid lines. Got: {lines}"


def test_result_txt():
    path = "/home/user/result.txt"
    assert os.path.isfile(path), f"Result file {path} is missing."

    with open(path, "r") as f:
        content = f.read().strip()

    try:
        val = float(content)
        assert val == 285.0, f"Expected result 285.0 in {path}, got {val}"
    except ValueError:
        pytest.fail(f"Result file {path} does not contain a valid float: {content}")

    number = r"[+-]?(?:(?:\d+(?:\.\d*)?)|(?:\.\d+))(?:[eE][+-]?\d+)?"
    assert re.fullmatch(number, content), "result.txt must contain only a standard floating-point number"


def test_engine_output_matches_saved_result():
    proc = subprocess.run(
        ["/home/user/calc_engine", "-file", "/home/user/recovered.wal"],
        cwd="/home/user",
        text=True,
        capture_output=True,
        timeout=10,
    )
    assert proc.returncode == 0, f"calc_engine failed: {proc.stderr}"
    output = proc.stdout.strip()
    assert len(output.splitlines()) == 1, f"Unexpected calc_engine output: {proc.stdout!r}"
    with open("/home/user/result.txt", "r") as f:
        saved = f.read().strip()
    assert float(output) == float(saved), f"Saved result {saved!r} does not match calc_engine output {output!r}"


def test_recover_go_filters_generated_wals_and_engine_accepts_them():
    source = "/home/user/recover.go"
    tx_path = "/home/user/tx.wal"
    recovered_path = "/home/user/recovered.wal"

    assert os.path.isfile(source), f"Go recovery script {source} is missing."
    with open(source, "rb") as f:
        assert f.read(1), f"Go recovery script {source} is empty."

    original_tx = open(tx_path, "rb").read() if os.path.exists(tx_path) else None
    original_recovered = open(recovered_path, "rb").read() if os.path.exists(recovered_path) else None

    try:
        for _ in range(2):
            n = secrets.randbelow(9000) + 1000
            expected = [
                f"ADD {n}.25",
                "MUL 2.0",
                "SUB 5.5",
                "ADD 3e1",
                "DIV 2.0",
            ]
            wal_lines = [
                expected[0],
                f"ADD {n}.25x",
                "UNKNOWN 10.0",
                expected[1],
                "ADD  7.0",
                "SUB\t4.0",
                expected[2],
                "MUL",
                "DIV 2.0 extra",
                expected[3],
                "add 9.0",
                expected[4],
            ]
            with open(tx_path, "w", newline="\n") as f:
                f.write("\n".join(wal_lines) + "\n")
            if os.path.exists(recovered_path):
                os.remove(recovered_path)

            proc = subprocess.run(
                ["go", "run", source],
                cwd="/home/user",
                text=True,
                capture_output=True,
                timeout=30,
            )
            assert proc.returncode == 0, f"recover.go failed on a generated WAL: {proc.stderr}"
            assert os.path.isfile(recovered_path), "recover.go did not create /home/user/recovered.wal"
            with open(recovered_path, "r") as f:
                actual = f.read().splitlines()
            assert actual == expected, f"recover.go did not correctly filter the generated WAL. Got: {actual}"

            engine = subprocess.run(
                ["/home/user/calc_engine", "-file", recovered_path],
                cwd="/home/user",
                text=True,
                capture_output=True,
                timeout=10,
            )
            assert engine.returncode == 0, f"calc_engine rejected recover.go output: {engine.stderr}"
            state = (((100.0 + (n + 0.25)) * 2.0) - 5.5 + 30.0) / 2.0
            assert engine.stdout.strip() == f"{state:.2f}", (
                f"Unexpected result from generated recovered WAL: {engine.stdout!r}"
            )
    finally:
        if original_tx is None:
            if os.path.exists(tx_path):
                os.remove(tx_path)
        else:
            with open(tx_path, "wb") as f:
                f.write(original_tx)
        if original_recovered is None:
            if os.path.exists(recovered_path):
                os.remove(recovered_path)
        else:
            with open(recovered_path, "wb") as f:
                f.write(original_recovered)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
