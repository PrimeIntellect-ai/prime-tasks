#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import importlib.util
import os
import subprocess
import sys

SCRIPT_PATH = "/home/user/transaction_processor.py"
LOG_PATH = "/home/user/success.log"


def load_processor():
    spec = importlib.util.spec_from_file_location("transaction_processor_under_test", SCRIPT_PATH)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_script_runs_to_completion():
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} does not exist or is not a regular file."

    # A pre-created success.log must not satisfy the verifier.
    if os.path.exists(LOG_PATH):
        os.remove(LOG_PATH)

    try:
        result = subprocess.run(
            [sys.executable, SCRIPT_PATH],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=20,
        )
    except subprocess.TimeoutExpired as exc:
        raise AssertionError("The transaction processor did not complete within 20 seconds; it may still deadlock.") from exc

    assert result.returncode == 0, (
        f"The transaction processor exited with code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def test_success_log_exists_and_correct():
    assert os.path.exists(LOG_PATH), f"The file {LOG_PATH} does not exist. Did the script run to completion?"

    with open(LOG_PATH, "r") as f:
        content = f.read().strip()

    expected = "Total balance: 5000"
    assert content == expected, f"Expected '{expected}' in {LOG_PATH}, but got '{content}'"


def test_transfer_preserves_required_behavior():
    module = load_processor()
    source = module.Account(1, 100)
    destination = module.Account(2, 50)

    module.transfer(source, destination, 30)
    assert (source.balance, destination.balance) == (70, 80), "A valid transfer must move the requested amount."

    module.transfer(source, destination, 1000)
    assert (source.balance, destination.balance) == (70, 80), "An underfunded transfer must not change balances."


def test_main_was_not_modified():
    with open(SCRIPT_PATH, "r") as f:
        tree = ast.parse(f.read())

    actual_main = next(
        (node for node in tree.body if isinstance(node, ast.FunctionDef) and node.name == "main"),
        None,
    )
    assert actual_main is not None, "The main function must remain present."

    expected_main = ast.parse('''
def main():
    random.seed(42)
    accounts = [Account(i, 1000) for i in range(5)]
    threads = []
    for _ in range(10):
        t = threading.Thread(target=worker, args=(accounts, 50))
        threads.append(t)
        t.start()

    for t in threads:
        t.join()

    total_balance = sum(a.balance for a in accounts)
    with open('/home/user/success.log', 'w') as f:
        f.write(f"Total balance: {total_balance}")
    print("Done")
''').body[0]

    assert ast.dump(actual_main, include_attributes=False) == ast.dump(expected_main, include_attributes=False), (
        "Do not modify the main function or the number of threads/iterations."
    )


def test_no_global_lock_used():
    assert os.path.exists(SCRIPT_PATH), f"{SCRIPT_PATH} does not exist."

    with open(SCRIPT_PATH, "r") as f:
        source = f.read()

    tree = ast.parse(source)

    # Check that Account class still initializes a lock
    account_has_lock = False
    for node in ast.walk(tree):
        if isinstance(node, ast.ClassDef) and node.name == "Account":
            for subnode in ast.walk(node):
                if isinstance(subnode, ast.Attribute) and subnode.attr == "lock":
                    account_has_lock = True
                    break

    assert account_has_lock, "The Account class must still use individual locks. Do not use a single global lock."

    # Check that transfer function is defined and uses locks
    transfer_found = False
    for node in ast.walk(tree):
        if isinstance(node, ast.FunctionDef) and node.name == "transfer":
            transfer_found = True
            with_count = 0
            for subnode in ast.walk(node):
                if isinstance(subnode, ast.With):
                    with_count += 1
            assert with_count >= 1, "The transfer function must use locks (with statements)."

    assert transfer_found, "The transfer function must be defined."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
