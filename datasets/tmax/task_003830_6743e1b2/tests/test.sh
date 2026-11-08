#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib.util
import inspect
import json
import os
import secrets
import subprocess

import pytest

PARSER_PATH = "/home/user/log_parser.py"
TRANSACTIONS_PATH = "/home/user/transactions.json"
TIMELINE_PATH = "/home/user/reconstructed_timeline.log"


def run_parser():
    try:
        result = subprocess.run(
            ["python3", PARSER_PATH],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=10,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("log_parser.py did not terminate within 10 seconds.")

    assert result.returncode == 0, (
        "log_parser.py exited unsuccessfully.\n"
        f"stdout:\n{result.stdout}\n"
        f"stderr:\n{result.stderr}"
    )
    assert os.path.isfile(TIMELINE_PATH), (
        "log_parser.py did not create reconstructed_timeline.log."
    )


@pytest.fixture(scope="session", autouse=True)
def execute_and_behaviorally_check_parser():
    assert os.path.isfile(PARSER_PATH), f"File {PARSER_PATH} is missing."
    assert os.path.isfile(TRANSACTIONS_PATH), f"File {TRANSACTIONS_PATH} is missing."

    with open(TRANSACTIONS_PATH, "rb") as f:
        original_transactions = f.read()

    suffix = secrets.token_hex(12)
    standard_mid = f"STD-{suffix}"
    cycle_first = f"CYCLE-A-{suffix}"
    cycle_second = f"CYCLE-B-{suffix}"
    distractor = f"UNUSED-{suffix}"
    dynamic_transactions = {
        distractor: {"next": None, "timestamp": "unused"},
        "TX-997": {"next": cycle_first, "timestamp": "dynamic"},
        cycle_second: {"next": cycle_first, "timestamp": "dynamic"},
        "TX-001": {"next": standard_mid, "timestamp": "dynamic"},
        cycle_first: {"next": cycle_second, "timestamp": "dynamic"},
        standard_mid: {"next": None, "timestamp": "dynamic"},
    }
    expected_dynamic = [
        "TX-001",
        standard_mid,
        "TX-997",
        cycle_first,
        cycle_second,
        "[CORRUPTED]",
    ]

    dynamic_error = None
    try:
        with open(TRANSACTIONS_PATH, "w") as f:
            json.dump(dynamic_transactions, f)
        if os.path.exists(TIMELINE_PATH):
            os.remove(TIMELINE_PATH)
        run_parser()
        with open(TIMELINE_PATH, "r") as f:
            actual_dynamic = [line.strip() for line in f if line.strip()]
        if actual_dynamic != expected_dynamic:
            dynamic_error = (
                "log_parser.py failed a dynamically generated transaction graph.\n"
                f"Expected: {expected_dynamic}\nGot: {actual_dynamic}"
            )
    finally:
        with open(TRANSACTIONS_PATH, "wb") as f:
            f.write(original_transactions)
        if os.path.exists(TIMELINE_PATH):
            os.remove(TIMELINE_PATH)
        run_parser()

    assert dynamic_error is None, dynamic_error
    yield


def load_parser_module():
    spec = importlib.util.spec_from_file_location(
        f"submitted_log_parser_{secrets.token_hex(8)}", PARSER_PATH
    )
    assert spec is not None and spec.loader is not None, (
        f"Could not load Python module from {PARSER_PATH}."
    )
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def call_resolve_chain(resolve_chain, tx_id, transactions, timeline):
    signature = inspect.signature(resolve_chain)
    try:
        signature.bind(tx_id, transactions, timeline)
        return resolve_chain(tx_id, transactions, timeline)
    except TypeError as bind_error:
        try:
            signature.bind(tx_id, transactions, timeline, set())
        except TypeError:
            raise bind_error
        return resolve_chain(tx_id, transactions, timeline, set())


def test_resolve_chain_dynamic_behavior():
    module = load_parser_module()
    assert hasattr(module, "resolve_chain"), "log_parser.py has no resolve_chain function."
    resolve_chain = module.resolve_chain
    assert callable(resolve_chain), "resolve_chain is not callable."

    for _ in range(5):
        token = secrets.token_hex(10)
        nodes = [f"NODE-{i}-{token}" for i in range(5)]
        transactions = {
            f"DISTRACTOR-{token}": {"next": None},
            nodes[2]: {"next": nodes[3]},
            nodes[0]: {"next": nodes[1]},
            nodes[4]: {"next": nodes[2]},
            nodes[1]: {"next": nodes[2]},
            nodes[3]: {"next": nodes[4]},
        }
        timeline = []
        call_resolve_chain(resolve_chain, nodes[0], transactions, timeline)
        assert timeline == nodes + ["[CORRUPTED]"], (
            "resolve_chain did not follow a dynamically generated cycle correctly. "
            f"Expected {nodes + ['[CORRUPTED]']}, got {timeline}."
        )

    token = secrets.token_hex(10)
    root_one = f"ROOT-ONE-{token}"
    root_two = f"ROOT-TWO-{token}"
    shared = f"SHARED-{token}"
    transactions = {
        root_one: {"next": shared},
        root_two: {"next": shared},
        shared: {"next": None},
    }
    timeline = []
    call_resolve_chain(resolve_chain, root_one, transactions, timeline)
    call_resolve_chain(resolve_chain, root_two, transactions, timeline)
    assert timeline == [root_one, shared, root_two, shared], (
        "Visited transactions must be tracked per current chain, not globally. "
        f"Got {timeline}."
    )


def test_crash_report_content():
    report_path = "/home/user/crash_report.txt"
    assert os.path.isfile(report_path), f"File {report_path} is missing."

    with open(report_path, "r") as f:
        content = f.read().strip()

    expected_content = "Crashed at: TX-999"
    assert content == expected_content, f"Expected '{expected_content}' in {report_path}, but got '{content}'."


def test_reconstructed_timeline_content():
    log_path = "/home/user/reconstructed_timeline.log"
    assert os.path.isfile(log_path), f"File {log_path} is missing. Did you run the log_parser.py script?"

    with open(log_path, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    expected_lines = [
        "TX-001",
        "TX-002",
        "TX-003",
        "TX-997",
        "TX-998",
        "TX-999",
        "[CORRUPTED]"
    ]

    assert lines == expected_lines, (
        f"Contents of {log_path} do not match the expected timeline.\n"
        f"Expected: {expected_lines}\n"
        f"Got: {lines}"
    )


def test_log_parser_modified():
    parser_path = "/home/user/log_parser.py"
    assert os.path.isfile(parser_path), f"File {parser_path} is missing."

    with open(parser_path, "r") as f:
        content = f.read()

    assert "[CORRUPTED]" in content, f"The string '[CORRUPTED]' was not found in {parser_path}. Ensure you updated the script to handle circular references."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
