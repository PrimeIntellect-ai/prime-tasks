#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'RUNNER_EOF' > /tmp/service_runner.py
import importlib.util
import sys

script_path = "/home/user/service.py"
spec = importlib.util.spec_from_file_location("submitted_service", script_path)
service = importlib.util.module_from_spec(spec)
spec.loader.exec_module(service)

if not callable(getattr(service, "process_data", None)):
    raise RuntimeError("service.py must provide process_data")
if not callable(getattr(service, "main", None)):
    raise RuntimeError("service.py must provide main")

original_process_data = service.process_data
expected_iteration = 0
checkpoints = {499: "CHECKPOINT 500", 4999: "CHECKPOINT 5000", 5099: "CHECKPOINT 5100"}

def monitored_process_data(iteration):
    global expected_iteration
    if iteration != expected_iteration:
        raise RuntimeError(
            f"Expected iteration {expected_iteration}, received {iteration}"
        )
    result = original_process_data(iteration)
    expected_iteration += 1
    marker = checkpoints.get(iteration)
    if marker is not None:
        print(marker, flush=True)
        if sys.stdin.readline() == "":
            raise RuntimeError("Verifier closed checkpoint control pipe")
    return result

service.process_data = monitored_process_data
service.main()
RUNNER_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib.util
import os
import select
import subprocess
import time

SCRIPT_PATH = "/home/user/service.py"


def get_rss_mb(pid):
    """Return the Resident Set Size of a process in megabytes."""
    try:
        with open(f"/proc/{pid}/statm", "r") as f:
            rss_pages = int(f.read().split()[1])
        return rss_pages * os.sysconf("SC_PAGE_SIZE") / (1024 * 1024)
    except (FileNotFoundError, ProcessLookupError, IndexError, ValueError):
        return None


def load_service():
    spec = importlib.util.spec_from_file_location("service_function_test", SCRIPT_PATH)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_core_stream_processing_is_preserved():
    assert os.path.isfile(SCRIPT_PATH), f"Expected file {SCRIPT_PATH} does not exist."
    service = load_service()
    assert callable(getattr(service, "process_data", None)), "process_data is missing"
    assert callable(getattr(service, "main", None)), "main is missing"

    observed = {"other": [], "data": []}

    class OtherRecorder:
        def __init__(self, data):
            observed["other"].append(data)

    class DataRecorder:
        def __init__(self, data):
            observed["data"].append(data)

    service.OtherNode = OtherRecorder
    service.DataNode_773X_Obfuscated = DataRecorder
    service.cache = []
    service.process_data(37)

    assert observed["other"] == ["data_37"], "OtherNode stream data was not processed correctly"
    assert observed["data"] == ["leak_37" * 10000], "DataNode stream data was not processed correctly"


def wait_for_marker(process, expected, timeout=30):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if process.poll() is not None:
            stderr = process.stderr.read()
            raise AssertionError(
                f"Service terminated before {expected!r} with code {process.returncode}: {stderr}"
            )
        remaining = deadline - time.monotonic()
        ready, _, _ = select.select([process.stdout], [], [], min(0.25, remaining))
        if ready:
            line = process.stdout.readline()
            if line == "" and process.poll() is not None:
                stderr = process.stderr.read()
                raise AssertionError(f"Service terminated before {expected!r}: {stderr}")
            if line.strip() == expected:
                return
    raise AssertionError(f"Service did not process enough iterations to reach {expected!r}")


def release_checkpoint(process):
    process.stdin.write("continue\n")
    process.stdin.flush()


def test_memory_leak_fixed_while_iterations_are_processed():
    assert os.path.isfile(SCRIPT_PATH), f"Expected file {SCRIPT_PATH} does not exist."

    process = subprocess.Popen(
        ["python3", "/tmp/service_runner.py", "--test-mode"],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        bufsize=1,
    )

    try:
        wait_for_marker(process, "CHECKPOINT 500")
        assert process.poll() is None, "Service process terminated prematurely during warmup."
        mem_start = get_rss_mb(process.pid)
        assert mem_start is not None, "Could not read initial memory usage of the process."

        release_checkpoint(process)
        wait_for_marker(process, "CHECKPOINT 5000")
        assert process.poll() is None, "Service process terminated prematurely before final memory measurement."
        mem_end = get_rss_mb(process.pid)
        assert mem_end is not None, "Could not read final memory usage of the process."

        growth = mem_end - mem_start
        assert growth <= 2.0, (
            f"Memory leak detected! RSS memory growth was {growth:.2f} MB "
            f"(from {mem_start:.2f} MB to {mem_end:.2f} MB), "
            "which exceeds the maximum allowed growth of 2.0 MB."
        )

        # Ensure the daemon continues processing after the measured interval.
        release_checkpoint(process)
        wait_for_marker(process, "CHECKPOINT 5100")
        assert process.poll() is None, "Service stopped after completing 5000 iterations."
    finally:
        if process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=3)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
