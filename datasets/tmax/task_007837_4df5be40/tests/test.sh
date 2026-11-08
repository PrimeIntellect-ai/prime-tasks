#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import asyncio
import importlib.util
import json
import os
import subprocess
import sys


def test_corrupted_id_identified():
    """Verify that the corrupted message ID was correctly identified."""
    path = "/home/user/corrupted_id.txt"
    assert os.path.isfile(path), f"{path} does not exist. Did you create it?"

    with open(path, "r") as f:
        content = f.read().strip()

    assert content == "MSG_004", (
        f"Incorrect corrupted ID found. Expected 'MSG_004', got '{content}'"
    )


def test_bad_commit_identified():
    """Verify that the bad commit hash was correctly identified."""
    path = "/home/user/bad_commit.txt"
    assert os.path.isfile(path), f"{path} does not exist. Did you create it?"

    with open(path, "r") as f:
        student_commit = f.read().strip()

    assert len(student_commit) == 40, "bad_commit.txt must contain a full 40-character hash"

    repo_path = "/home/user/message_processor"
    assert os.path.isdir(repo_path), f"Git repository missing at {repo_path}"

    # Preserve the original dynamic assertion for the introducing commit.
    result = subprocess.run(
        ["git", "log", "--reverse", "-S", "asyncio.sleep", "--format=%H"],
        cwd=repo_path,
        capture_output=True,
        text=True,
        check=True,
    )

    hashes = result.stdout.strip().split("\n")
    assert hashes and hashes[0], (
        "Could not dynamically determine the bad commit hash from repository history."
    )
    expected_commit = hashes[0].strip()

    assert student_commit == expected_commit, (
        f"Incorrect bad commit hash. Expected '{expected_commit}', got '{student_commit}'"
    )


def test_fuzzer_exists_and_exercises_1000_concurrent_requests():
    """Execute the requested fuzzer and verify its calls are concurrent."""
    fuzz_path = "/home/user/fuzz_test.py"
    processor_path = "/home/user/message_processor/processor.py"
    report_path = "/tmp/fuzz_probe.json"

    assert os.path.isfile(fuzz_path), f"{fuzz_path} does not exist. Did you create it?"
    assert os.path.isfile(processor_path), f"{processor_path} is missing"

    with open(fuzz_path, "r", encoding="utf-8") as f:
        source = f.read()
    tree = ast.parse(source, filename=fuzz_path)

    uses_gather = any(
        isinstance(node, ast.Call)
        and (
            (isinstance(node.func, ast.Attribute) and node.func.attr == "gather")
            or (isinstance(node.func, ast.Name) and node.func.id == "gather")
        )
        for node in ast.walk(tree)
    )
    calls_processor = any(
        isinstance(node, ast.Call)
        and (
            (isinstance(node.func, ast.Attribute) and node.func.attr == "process_messages")
            or (isinstance(node.func, ast.Name) and node.func.id == "process_messages")
        )
        for node in ast.walk(tree)
    )
    assert uses_gather, "fuzz_test.py must use asyncio.gather"
    assert calls_processor, "fuzz_test.py must call process_messages()"

    probe_processor = r'''
import asyncio
import atexit
import json

shared_counter = 0
_active = 0
_max_active = 0
_calls = 0
_report = "/tmp/fuzz_probe.json"

async def process_messages():
    global shared_counter, _active, _max_active, _calls
    _calls += 1
    call_number = _calls
    _active += 1
    _max_active = max(_max_active, _active)
    await asyncio.sleep(0.001)
    _active -= 1
    shared_counter = call_number
    return call_number

@atexit.register
def _write_report():
    with open(_report, "w", encoding="utf-8") as f:
        json.dump({"calls": _calls, "max_active": _max_active}, f)
'''

    with open(processor_path, "rb") as f:
        original_processor = f.read()
    original_mode = os.stat(processor_path).st_mode

    try:
        if os.path.exists(report_path):
            os.remove(report_path)
        with open(processor_path, "w", encoding="utf-8") as f:
            f.write(probe_processor)

        result = subprocess.run(
            [sys.executable, fuzz_path],
            cwd="/home/user",
            capture_output=True,
            text=True,
            timeout=30,
        )
        assert result.returncode == 0, (
            "fuzz_test.py failed when executed.\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
        assert os.path.isfile(report_path), (
            "fuzz_test.py did not execute process_messages() from processor.py"
        )
        with open(report_path, "r", encoding="utf-8") as f:
            report = json.load(f)

        assert report.get("calls") == 1000, (
            f"fuzz_test.py must send exactly 1000 requests; observed {report.get('calls')}"
        )
        assert report.get("max_active") == 1000, (
            "The 1000 process_messages() requests were not all scheduled concurrently "
            "with asyncio.gather"
        )
    finally:
        with open(processor_path, "wb") as f:
            f.write(original_processor)
        os.chmod(processor_path, original_mode)
        if os.path.exists(report_path):
            os.remove(report_path)


def test_race_condition_fixed():
    """Verify that the race condition in processor.py has been fixed."""
    file_path = "/home/user/message_processor/processor.py"
    assert os.path.isfile(file_path), f"{file_path} is missing"

    spec = importlib.util.spec_from_file_location("processor_final_verification", file_path)
    processor = importlib.util.module_from_spec(spec)
    sys.modules["processor_final_verification"] = processor
    spec.loader.exec_module(processor)

    if hasattr(processor, "shared_counter"):
        processor.shared_counter = 0

    async def run_test():
        num_tasks = 5000
        tasks = [processor.process_messages() for _ in range(num_tasks)]
        results = await asyncio.gather(*tasks)
        unique_results = set(results)

        assert len(unique_results) == num_tasks, (
            f"Race condition still present: Expected {num_tasks} unique sequence numbers, "
            f"but got {len(unique_results)}. Ensure thread-safe/async-safe operations."
        )
        assert max(unique_results) == num_tasks, (
            f"Race condition still present: Expected the maximum sequence number to be "
            f"{num_tasks}, but got {max(unique_results)}."
        )

    # Run directly so this test does not depend on the uninstalled pytest-asyncio plugin.
    asyncio.run(run_test())
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
