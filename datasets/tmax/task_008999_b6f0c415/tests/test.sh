#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import stat
import subprocess
from decimal import Decimal, ROUND_FLOOR, ROUND_HALF_UP
from pathlib import Path

import pytest

HOME = Path("/home/user")
DATA = HOME / "data.csv"
SOURCE = HOME / "etl.cpp"
BINARY = HOME / "etl"
PREDICTIONS = HOME / "predictions.csv"


@pytest.fixture(scope="session", autouse=True)
def restore_input_and_output():
    original_data = DATA.read_bytes()
    prediction_existed = PREDICTIONS.exists()
    original_predictions = PREDICTIONS.read_bytes() if prediction_existed else None
    yield
    DATA.write_bytes(original_data)
    if prediction_existed:
        PREDICTIONS.write_bytes(original_predictions)
    elif PREDICTIONS.exists():
        PREDICTIONS.unlink()


def test_predictions_csv_correct():
    path = "/home/user/predictions.csv"
    assert os.path.isfile(path), f"File {path} is missing. Did you compile and run the fixed C++ code?"

    with open(path, "r") as f:
        content = f.read().strip()

    expected = """id,prediction
101,7.6
102,2.3
103,17.1
104,0.1"""

    assert content == expected, f"Content of {path} is incorrect.\nExpected:\n{expected}\n\nActual:\n{content}"


def make_hidden_case():
    rng = random.SystemRandom()
    while True:
        ids = rng.sample(range(200, 5000), 5)
        rows = []
        grouped = {}
        valid = True

        for identifier in ids:
            values = []
            for _ in range(rng.randint(2, 4)):
                f1 = Decimal(rng.randint(-80, 160)) / Decimal(4)
                f2 = Decimal(rng.randint(-80, 160)) / Decimal(4)
                values.append((f1, f2))
                rows.append((identifier, f1, f2))
            grouped[identifier] = values

        expected_lines = ["id,prediction"]
        for identifier in sorted(grouped):
            values = grouped[identifier]
            count = Decimal(len(values))
            mean_f1 = sum((v[0] for v in values), Decimal(0)) / count
            mean_f2 = sum((v[1] for v in values), Decimal(0)) / count
            prediction = mean_f1 * Decimal("0.5") + mean_f2 * Decimal("1.2") + Decimal("0.1")

            # Avoid rounding ties and values which could format as negative zero.
            scaled = prediction * Decimal(10)
            fraction = scaled - scaled.to_integral_value(rounding=ROUND_FLOOR)
            if abs(fraction - Decimal("0.5")) < Decimal("0.1") or abs(prediction) < Decimal("1"):
                valid = False
                break

            rendered = prediction.quantize(Decimal("0.1"), rounding=ROUND_HALF_UP)
            expected_lines.append(f"{identifier},{rendered:.1f}")

        if valid:
            rng.shuffle(rows)
            input_lines = ["id,f1,f2"] + [f"{i},{f1},{f2}" for i, f1, f2 in rows]
            return "\n".join(input_lines) + "\n", "\n".join(expected_lines)


def run_and_check(executable, expected):
    result = subprocess.run(
        [str(executable)], cwd=str(HOME), text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10
    )
    assert result.returncode == 0, (
        f"{executable} failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert PREDICTIONS.is_file(), "The ETL executable did not create predictions.csv"
    actual = PREDICTIONS.read_text().strip()
    assert actual == expected, f"Hidden-input output is incorrect.\nExpected:\n{expected}\n\nActual:\n{actual}"


def test_fixed_source_and_compiled_pipeline_on_hidden_input(tmp_path):
    assert SOURCE.is_file(), "/home/user/etl.cpp is missing"
    assert BINARY.is_file(), "/home/user/etl is missing; compile the fixed source as instructed"
    assert stat.S_ISREG(BINARY.stat().st_mode), "/home/user/etl is not a regular file"
    assert os.access(BINARY, os.X_OK), "/home/user/etl is not executable"
    assert BINARY.read_bytes()[:4] == b"\x7fELF", "/home/user/etl is not a compiled ELF executable"

    hidden_input, expected = make_hidden_case()
    DATA.write_text(hidden_input)

    # Exercise the executable the agent was instructed to build.
    run_and_check(BINARY, expected)

    # Independently compile and exercise the submitted source so the executable
    # cannot mask an unfixed etl.cpp.
    rebuilt = tmp_path / "etl_rebuilt"
    compile_result = subprocess.run(
        ["g++", "-O3", str(SOURCE), "-o", str(rebuilt)],
        cwd=str(HOME), text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        timeout=30
    )
    assert compile_result.returncode == 0, (
        "The submitted etl.cpp does not compile with g++ -O3.\n"
        f"stdout:\n{compile_result.stdout}\nstderr:\n{compile_result.stderr}"
    )
    run_and_check(rebuilt, expected)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
