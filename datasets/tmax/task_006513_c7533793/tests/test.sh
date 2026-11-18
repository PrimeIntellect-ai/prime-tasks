#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import json
import os
import subprocess
import sys
import textwrap
import pytest

WORKDIR = "/home/user/uptime_monitor"
MAKEFILE = os.path.join(WORKDIR, "Makefile")
SOURCE = os.path.join(WORKDIR, "libmetrics.c")
LIBRARY = os.path.join(WORKDIR, "libmetrics.so")
AGENT = os.path.join(WORKDIR, "agent.py")

EXPECTED_AGENT = b"""import ctypes
import threading
import time
import os

# Load the shared library
lib_path = os.path.join(os.path.dirname(__file__), 'libmetrics.so')
try:
    metrics = ctypes.CDLL(lib_path)
except OSError:
    print("Failed to load libmetrics.so. Did you compile it?")
    exit(1)

def query_cpu():
    for _ in range(50):
        metrics.get_cpu_metrics()

def query_mem():
    for _ in range(50):
        metrics.get_mem_metrics()

def main():
    threads = []

    # Spawn multiple threads to hammer the library and trigger the deadlock
    for i in range(10):
        t1 = threading.Thread(target=query_cpu)
        t2 = threading.Thread(target=query_mem)
        threads.extend([t1, t2])
        t1.start()
        t2.start()

    for t in threads:
        t.join()

    print("Successfully completed all monitoring queries.")

if __name__ == "__main__":
    main()
"""

STRESS_SCRIPT = "/tmp/stress_libmetrics.py"


def run_stress(library_path, timeout=8):
    with open(STRESS_SCRIPT, "w") as f:
        f.write(textwrap.dedent("""
            import ctypes
            import sys
            import threading

            lib = ctypes.CDLL(sys.argv[1])
            cpu = lib.get_cpu_metrics
            mem = lib.get_mem_metrics
            cpu.argtypes = []
            cpu.restype = None
            mem.argtypes = []
            mem.restype = None

            thread_count = 20
            barrier = threading.Barrier(thread_count)

            def worker(fn):
                barrier.wait()
                for _ in range(100):
                    fn()

            threads = []
            for i in range(thread_count):
                fn = cpu if i % 2 == 0 else mem
                threads.append(threading.Thread(target=worker, args=(fn,)))
            for thread in threads:
                thread.start()
            for thread in threads:
                thread.join()
            print("stress completed")
        """))

    try:
        result = subprocess.run(
            [sys.executable, STRESS_SCRIPT, library_path],
            capture_output=True,
            text=True,
            timeout=timeout,
        )
    except subprocess.TimeoutExpired:
        pytest.fail(f"Concurrent calls to {library_path} deadlocked")

    assert result.returncode == 0, (
        f"Concurrent library test failed for {library_path}: {result.stderr}"
    )
    assert "stress completed" in result.stdout


@pytest.fixture(scope="session", autouse=True)
def rebuild_submission():
    assert os.path.isfile(MAKEFILE), f"Makefile is missing at {MAKEFILE}"
    assert os.path.isfile(SOURCE), f"C source is missing at {SOURCE}"

    clean = subprocess.run(
        ["make", "clean"], cwd=WORKDIR, capture_output=True, text=True, timeout=10
    )
    assert clean.returncode == 0, f"make clean failed: {clean.stdout}\n{clean.stderr}"
    assert not os.path.exists(LIBRARY), "make clean did not remove libmetrics.so"

    build = subprocess.run(
        ["make"], cwd=WORKDIR, capture_output=True, text=True, timeout=20
    )
    assert build.returncode == 0, f"make failed: {build.stdout}\n{build.stderr}"


def test_makefile_fixed():
    makefile_path = "/home/user/uptime_monitor/Makefile"
    assert os.path.isfile(makefile_path), f"Makefile is missing at {makefile_path}"
    with open(makefile_path, "r") as f:
        content = f.read()
    assert "-lpthread" in content, "Makefile does not contain the fixed linker flag '-lpthread'"
    assert "-lpthred" not in content, "Makefile still contains the typo '-lpthred'"


def test_libmetrics_so_built():
    so_path = "/home/user/uptime_monitor/libmetrics.so"
    assert os.path.isfile(so_path), f"Shared library {so_path} was not built"
    with open(so_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "libmetrics.so is not an ELF shared library"

    try:
        library = ctypes.CDLL(so_path)
        getattr(library, "get_cpu_metrics")
        getattr(library, "get_mem_metrics")
    except (OSError, AttributeError) as exc:
        pytest.fail(f"Built library is not loadable with both required functions: {exc}")

    run_stress(so_path)


def test_libmetrics_source_itself_is_deadlock_free():
    direct_library = "/tmp/libmetrics_from_source.so"
    compile_result = subprocess.run(
        ["gcc", "-shared", "-fPIC", SOURCE, "-o", direct_library, "-pthread"],
        capture_output=True,
        text=True,
        timeout=20,
    )
    assert compile_result.returncode == 0, (
        f"libmetrics.c does not compile independently: {compile_result.stderr}"
    )
    run_stress(direct_library)


def test_agent_execution_no_deadlock():
    agent_path = "/home/user/uptime_monitor/agent.py"
    assert os.path.isfile(agent_path), f"Agent script {agent_path} is missing"
    with open(agent_path, "rb") as f:
        assert f.read() == EXPECTED_AGENT, "agent.py was modified"

    try:
        result = subprocess.run(
            ["python3", agent_path],
            capture_output=True,
            text=True,
            timeout=10
        )
    except subprocess.TimeoutExpired:
        pytest.fail("Agent script timed out after 10 seconds, indicating the deadlock is not fixed.")

    assert result.returncode == 0, f"Agent script failed with return code {result.returncode}. Stderr: {result.stderr}"
    assert "Successfully completed all monitoring queries." in result.stdout, "Agent script did not output the expected success message."


def test_resolution_json():
    json_path = "/home/user/resolution.json"
    assert os.path.isfile(json_path), f"Resolution file {json_path} is missing"

    with open(json_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{json_path} does not contain valid JSON")

    assert set(data) == {"linker_error_fixed", "deadlocked_functions", "fix_strategy"}, \
        "resolution.json must strictly contain the three required fields"
    assert "linker_error_fixed" in data, "Missing 'linker_error_fixed' in resolution.json"
    assert data["linker_error_fixed"] is True, "'linker_error_fixed' must be true"

    assert "deadlocked_functions" in data, "Missing 'deadlocked_functions' in resolution.json"
    expected_functions = ["get_cpu_metrics", "get_mem_metrics"]
    assert data["deadlocked_functions"] == expected_functions, f"'deadlocked_functions' must be exactly {expected_functions}"

    assert "fix_strategy" in data, "Missing 'fix_strategy' in resolution.json"
    assert isinstance(data["fix_strategy"], str) and len(data["fix_strategy"]) > 0, "'fix_strategy' must be a non-empty string"
    strategy = data["fix_strategy"].lower()
    assert any(term in strategy for term in ("lock", "mutex")), \
        "'fix_strategy' must explain the locking or mutex change"
    assert any(term in strategy for term in ("order", "consistent", "same", "single")), \
        "'fix_strategy' must explain how lock ordering was resolved"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
