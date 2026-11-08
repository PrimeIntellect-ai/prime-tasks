#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess
from decimal import Decimal, ROUND_DOWN

import pytest

SCRIPT_PATH = "/home/user/analyze_pipeline.sh"
DATA_PATH = "/home/user/processed/data.csv"
OUTPUT_PATH = "/home/user/posterior.txt"


def test_posterior_file_exists():
    assert os.path.isfile(OUTPUT_PATH), "The file /home/user/posterior.txt does not exist."


def test_posterior_value():
    # Dynamically calculate the expected value based on the CSV file
    assert os.path.isfile(DATA_PATH), f"Data file {DATA_PATH} is missing."

    with open(DATA_PATH, "r") as f:
        lines = f.read().strip().split("\n")

    assert len(lines) > 1, "Data file is empty or missing rows."

    header = lines[0].split(",")
    try:
        user_id_idx = header.index("user_id")
    except ValueError:
        pytest.fail("Column 'user_id' not found in data.csv header.")

    total_tx = len(lines) - 1
    corrupt_tx = 0

    for line in lines[1:]:
        cols = line.split(",")
        if len(cols) > user_id_idx:
            user_id_val = cols[user_id_idx]
            if "." in user_id_val or "NaN" in user_id_val:
                corrupt_tx += 1

    assert total_tx > 0, "No transactions found."
    assert corrupt_tx > 0, "No corrupted transactions found."

    p_corrupt = corrupt_tx / total_tx
    p_fraud = 0.05
    p_corrupt_given_fraud = 0.80

    # P(Fraud|Corrupt) = (P(Corrupt|Fraud) * P(Fraud)) / P(Corrupt)
    p_fraud_given_corrupt = (p_corrupt_given_fraud * p_fraud) / p_corrupt

    # bc with scale=4 truncates, it does not round.
    expected_val_str = f"{p_fraud_given_corrupt:.5f}"[:-1]

    with open(OUTPUT_PATH, "r") as f:
        actual_val = f.read().strip()

    # Accept both '0.3333' and '.3333' (bc default behavior)
    acceptable_values = [expected_val_str, expected_val_str.lstrip("0")]

    assert actual_val in acceptable_values, (
        f"Expected posterior value to be one of {acceptable_values} (derived from "
        f"{corrupt_tx} corrupted out of {total_tx} total transactions), but got '{actual_val}'."
    )


def test_script_exists():
    assert os.path.isfile(SCRIPT_PATH), f"The script {SCRIPT_PATH} does not exist."


def test_script_uses_bc_scale_four_and_recomputes_from_csv():
    with open(SCRIPT_PATH, "r", encoding="utf-8") as f:
        source = f.read()

    active_source = "\n".join(
        line for line in source.splitlines()
        if not line.lstrip().startswith("#")
    )
    assert re.search(r"\bscale\s*=\s*4(?![\d.])", active_source), (
        "The script must configure bc with scale=4."
    )

    with open(DATA_PATH, "rb") as f:
        original_data = f.read()
    output_existed = os.path.exists(OUTPUT_PATH)
    original_output = None
    if output_existed:
        with open(OUTPUT_PATH, "rb") as f:
            original_output = f.read()

    # Use a runtime-generated fixture so a hard-coded answer for the image's CSV
    # cannot pass. Include both specified forms of corruption.
    total_tx = 80 + secrets.randbelow(81)
    corrupt_tx = max(2, total_tx // 10 + secrets.randbelow(total_tx // 3))
    corrupt_tx = min(corrupt_tx, total_tx - 1)

    rows = ["tx_id,user_id,amount"]
    for i in range(1, total_tx + 1):
        if i <= corrupt_tx:
            user_id = "NaN" if i % 2 else f"{700000 + i}.0"
        else:
            user_id = str(700000 + i)
        rows.append(f"DYN{i:04d},{user_id},10.00")
    dynamic_data = ("\n".join(rows) + "\n").encode()

    try:
        with open(DATA_PATH, "wb") as f:
            f.write(dynamic_data)
        if os.path.exists(OUTPUT_PATH):
            os.unlink(OUTPUT_PATH)

        result = subprocess.run(
            ["/bin/bash", "-x", SCRIPT_PATH],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=20,
        )
        assert result.returncode == 0, (
            "analyze_pipeline.sh failed when executed against a new CSV fixture.\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
        assert re.search(
            r"(?m)^\++\s+(?:command\s+)?(?:/[^\s]*/)?bc(?:\s|$)",
            result.stderr,
        ), "Execution trace shows that the script did not invoke bc."
        assert os.path.isfile(OUTPUT_PATH), (
            "The executed script did not create /home/user/posterior.txt."
        )

        p_corrupt = Decimal(corrupt_tx) / Decimal(total_tx)
        posterior = (Decimal("0.80") * Decimal("0.05")) / p_corrupt
        expected = format(
            posterior.quantize(Decimal("0.0001"), rounding=ROUND_DOWN),
            ".4f",
        )

        with open(OUTPUT_PATH, "r") as f:
            actual = f.read().strip()
        assert re.fullmatch(r"(?:\d+\.\d{4}|\.\d{4})", actual), (
            f"The script output must be only a numeric value with exactly four decimal places; got {actual!r}."
        )
        assert actual in (expected, expected.lstrip("0")), (
            f"For the runtime fixture ({corrupt_tx}/{total_tx} corrupt), expected "
            f"{expected!r} or {expected.lstrip('0')!r}, but got {actual!r}."
        )
    finally:
        with open(DATA_PATH, "wb") as f:
            f.write(original_data)
        if output_existed:
            with open(OUTPUT_PATH, "wb") as f:
                f.write(original_output)
        elif os.path.exists(OUTPUT_PATH):
            os.unlink(OUTPUT_PATH)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
