#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib.util
import multiprocessing
import os
import re
import subprocess
import threading
from decimal import Decimal

SCRIPT_PATH = "/home/user/finance_aggregator.py"
RESULTS_PATH = "/home/user/results.txt"


def load_module(name):
    spec = importlib.util.spec_from_file_location(name, SCRIPT_PATH)
    assert spec is not None and spec.loader is not None, "Unable to load finance_aggregator.py"
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_script_exists_and_runs():
    assert os.path.exists(SCRIPT_PATH), f"The required script {SCRIPT_PATH} is missing."
    assert os.path.isfile(SCRIPT_PATH), f"The path {SCRIPT_PATH} is not a file."

    if os.path.exists(RESULTS_PATH):
        os.remove(RESULTS_PATH)

    completed = subprocess.run(
        ["python3", SCRIPT_PATH],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert completed.returncode == 0, (
        f"finance_aggregator.py exited with status {completed.returncode}.\n"
        f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
    )


def test_results_file_exists():
    file_path = RESULTS_PATH
    assert os.path.exists(file_path), f"The output file {file_path} is missing. Did you run the script?"
    assert os.path.isfile(file_path), f"The path {file_path} is not a file."


def test_results_content():
    file_path = RESULTS_PATH
    with open(file_path, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(lines) == 2, f"Expected exactly 2 lines in {file_path}, found {len(lines)}."

    records_match = re.match(r"^Total Records:\s*(\d+)$", lines[0])
    assert records_match, f"First line format is incorrect. Expected 'Total Records: <integer>', got '{lines[0]}'"
    records = int(records_match.group(1))
    assert records == 10000, f"Expected 10000 Total Records, got {records}. Concurrency or retry logic might still be broken."

    value_match = re.match(r"^Total Value:\s*([0-9\.]+)$", lines[1])
    assert value_match, f"Second line format is incorrect. Expected 'Total Value: <precise string>', got '{lines[1]}'"
    value_str = value_match.group(1)
    assert value_str == "1000.0", f"Expected Total Value to be exactly '1000.0' using Decimal, got '{value_str}'. Floating-point precision issue might not be properly fixed."


def retry_worker(queue):
    try:
        module = load_module("finance_retry_check")
        calls = {"count": 0}

        def always_fail(batch_id):
            calls["count"] += 1
            raise module.NetworkError("forced failure")

        module.do_fetch = always_fail
        module.time.sleep = lambda _seconds: None
        result = module.fetch_data(123)
        queue.put(("ok", calls["count"], result))
    except BaseException as exc:
        queue.put(("error", repr(exc)))


def test_retry_loop_is_bounded():
    ctx = multiprocessing.get_context("fork")
    queue = ctx.Queue()
    process = ctx.Process(target=retry_worker, args=(queue,))
    process.start()
    process.join(3)

    if process.is_alive():
        process.terminate()
        process.join()
        raise AssertionError("fetch_data did not terminate after repeated network failures")

    assert process.exitcode == 0, f"Retry test process exited with status {process.exitcode}"
    assert not queue.empty(), "Retry test returned no result"
    outcome = queue.get()
    assert outcome[0] == "ok", f"Retry test raised an exception: {outcome[1]}"
    _, calls, result = outcome
    assert calls == 5, f"Expected exactly 5 fetch attempts, got {calls}"
    assert result == [], f"Expected an empty result after all retries fail, got {result!r}"


def test_threaded_aggregation_is_lossless_and_decimal():
    module = load_module("finance_concurrency_check")
    assert module.NUM_BATCHES == 10, "NUM_BATCHES must remain 10"
    assert module.RECORDS_PER_BATCH == 1000, "RECORDS_PER_BATCH must remain 1000"
    assert isinstance(module.global_value, Decimal), "global_value must use decimal.Decimal"

    records_per_thread = 250
    module.global_records = 0
    module.global_value = Decimal("0.0")
    module.fetch_data = lambda batch_id: [
        {"id": i, "value": 0.1} for i in range(records_per_thread)
    ]

    threads = [threading.Thread(target=module.process_batch, args=(i,)) for i in range(10)]
    for thread in threads:
        thread.start()
    for thread in threads:
        thread.join(timeout=10)
        assert not thread.is_alive(), "A processing thread failed to terminate"

    assert module.global_records == 2500, (
        f"Expected 2500 records after concurrent processing, got {module.global_records}"
    )
    assert isinstance(module.global_value, Decimal), "Aggregated value must remain a Decimal"
    assert module.global_value == Decimal("250.0"), (
        f"Expected exact Decimal total 250.0, got {module.global_value!r}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
