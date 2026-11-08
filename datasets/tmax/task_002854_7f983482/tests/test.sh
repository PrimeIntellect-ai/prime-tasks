#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import contextlib
import importlib
import io
import json
import os
import re
import runpy
import secrets
import string
import subprocess
import sys
from decimal import Decimal

HOME = "/home/user"
PROCESSOR_PATH = os.path.join(HOME, "processor.py")
TRANSACTIONS_PATH = os.path.join(HOME, "transactions.txt")
SYSDUMP_PATH = os.path.join(HOME, "sysdump.bin")
CRASH_ID = "TX-8374-ERR"
ORIGINAL_RAW_LINE = 'TX-8374-ERR|{"amount": 9007199254740995.05, "currency": "USD", }'


def crash_details():
    with open(SYSDUMP_PATH, "rb") as f:
        dump = f.read()
    matches = re.findall(rb"FATAL_CRASH_TX_ID: ([^\r\n]+)", dump)
    assert matches, "sysdump.bin does not contain a fatal crash transaction ID."
    tx_id = matches[-1].decode("ascii")
    assert tx_id == CRASH_ID, f"Unexpected crash transaction ID in sysdump.bin: {tx_id}."

    with open(TRANSACTIONS_PATH, "r") as f:
        lines = [line.rstrip("\r\n") for line in f]
    matching = [line for line in lines if line.startswith(tx_id + "|")]
    assert len(matching) == 1, "transactions.txt must contain exactly one crash transaction line."
    raw_line = matching[0]
    assert raw_line == ORIGINAL_RAW_LINE, "The crash transaction input was unexpectedly modified."

    payload = raw_line.split("|", 1)[1]
    cleaned = re.sub(r",\s*}$", "}", payload)
    data = json.loads(cleaned, parse_float=Decimal, parse_int=Decimal)
    amount = data["amount"]
    tax = amount * Decimal("0.05")
    return tx_id, raw_line, amount, tax


def load_processor():
    assert os.path.exists(PROCESSOR_PATH), f"{PROCESSOR_PATH} does not exist."
    if HOME not in sys.path:
        sys.path.insert(0, HOME)
    try:
        module = importlib.import_module("processor")
    except Exception as exc:
        raise AssertionError(f"Failed to import processor.py: {exc}") from exc
    assert hasattr(module, "process_tx"), "processor.py missing process_tx function."
    assert callable(module.process_tx), "processor.process_tx is not callable."
    return module


def assert_processed(processor, raw_line, expected_id, expected_amount):
    try:
        result = processor.process_tx(raw_line)
    except Exception as exc:
        raise AssertionError(f"process_tx failed for {raw_line!r}: {exc}") from exc

    assert result is not None, "process_tx returned None for a valid transaction."
    assert isinstance(result, tuple), f"process_tx should return a tuple, got {type(result)}."
    assert len(result) == 3, f"process_tx should return a tuple of length 3, got {len(result)}."
    tx_id, amount, tax = result
    assert tx_id == expected_id, f"process_tx returned incorrect tx_id: {tx_id}."
    assert isinstance(amount, Decimal), f"Amount should be a Decimal, got {type(amount)}."
    assert isinstance(tax, Decimal), f"Tax should be a Decimal, got {type(tax)}."
    assert amount == expected_amount, f"process_tx returned incorrect amount: {amount}."
    expected_tax = expected_amount * Decimal("0.05")
    assert tax == expected_tax, f"process_tx returned incorrect tax: {tax}; expected {expected_tax}."


def test_solution_json_correctness():
    solution_path = os.path.join(HOME, "solution.json")
    assert os.path.exists(solution_path), f"{solution_path} does not exist."
    with open(solution_path, "r") as f:
        try:
            sol = json.load(f)
        except json.JSONDecodeError as exc:
            raise AssertionError(f"{solution_path} contains invalid JSON: {exc}") from exc

    assert "crash_tx_id" in sol, "solution.json missing 'crash_tx_id' key."
    assert "precise_tax_value" in sol, "solution.json missing 'precise_tax_value' key."
    assert set(sol) == {"crash_tx_id", "precise_tax_value"}, "solution.json has an incorrect structure."

    expected_tx_id, _, _, expected_tax = crash_details()
    assert sol["crash_tx_id"] == expected_tx_id, f"Incorrect crash_tx_id: {sol['crash_tx_id']}."
    assert sol["precise_tax_value"] == str(expected_tax), f"Incorrect precise_tax_value: {sol['precise_tax_value']}."


def test_processor_fixes_on_crash_input():
    processor = load_processor()
    tx_id, raw_line, amount, _ = crash_details()
    assert_processed(processor, raw_line, tx_id, amount)


def test_processor_generalizes_to_unseen_inputs():
    processor = load_processor()

    cases = []
    for index in range(5):
        tx_id = "TX-" + secrets.token_hex(9).upper()
        whole = str(secrets.randbelow(8_000_000_000_000_000) + 1_000_000_000_000_000)
        fraction = f"{secrets.randbelow(10000):04d}"
        amount_text = whole + "." + fraction
        currency = "".join(secrets.choice(string.ascii_uppercase) for _ in range(3))

        if index == 0:
            payload = f'{{"amount": {amount_text}, "currency": "{currency}"}}'
        elif index % 2:
            payload = f'{{"amount": {amount_text}, "currency": "{currency}",}}'
        else:
            payload = f'{{"amount": {amount_text}, "currency": "{currency}",   }}'
        cases.append((tx_id + "|" + payload, tx_id, Decimal(amount_text)))

    for raw_line, tx_id, amount in cases:
        assert_processed(processor, raw_line, tx_id, amount)

    assert processor.process_tx("   \n") is None, "process_tx should return None for a blank line."


def test_mre_script():
    mre_path = os.path.join(HOME, "mre.py")
    assert os.path.exists(mre_path), f"{mre_path} does not exist."

    processor = load_processor()
    _, raw_line, _, _ = crash_details()
    calls = []
    token = secrets.token_hex(12)
    sentinel = ("SPY-" + token, Decimal("123456789.012345"), Decimal("6172839.45061725"))
    original_process_tx = processor.process_tx

    def spy_process_tx(value):
        calls.append(value)
        return sentinel

    processor.process_tx = spy_process_tx
    captured = io.StringIO()
    try:
        with contextlib.redirect_stdout(captured):
            runpy.run_path(mre_path, run_name="__main__")
    finally:
        processor.process_tx = original_process_tx

    assert raw_line in calls, "mre.py did not call process_tx with the exact crash line from transactions.txt."
    assert repr(sentinel) in captured.getvalue(), "mre.py did not print the tuple returned by process_tx."

    try:
        result = subprocess.run(
            [sys.executable, mre_path],
            capture_output=True,
            text=True,
            check=True,
            cwd=HOME,
        )
    except subprocess.CalledProcessError as exc:
        raise AssertionError(f"mre.py failed to execute. Stderr: {exc.stderr}") from exc

    output = result.stdout.strip()
    assert "TX-8374-ERR" in output, "mre.py output does not contain the expected TX ID."
    assert "450359962737049.7525" in output, "mre.py output does not contain the precise tax value."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
