#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib.util
import os
import subprocess
import time


def selected_python():
    venv_python = "/home/user/venv/bin/python"
    return venv_python if os.path.isfile(venv_python) else "python3"


def run_script_and_observe_workers():
    result_path = "/home/user/reproducible_result.txt"
    if os.path.exists(result_path):
        os.remove(result_path)

    process = subprocess.Popen(
        [selected_python(), "/home/user/mutation_sim.py"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )

    max_children = 0
    deadline = time.time() + 60
    while process.poll() is None and time.time() < deadline:
        children_path = f"/proc/{process.pid}/task/{process.pid}/children"
        try:
            with open(children_path, "r") as f:
                children = f.read().strip().split()
            max_children = max(max_children, len(children))
        except (FileNotFoundError, ProcessLookupError):
            pass
        time.sleep(0.005)

    if process.poll() is None:
        process.kill()
        stdout, stderr = process.communicate()
        raise AssertionError(f"mutation_sim.py timed out. stdout={stdout!r}, stderr={stderr!r}")

    stdout, stderr = process.communicate()
    assert process.returncode == 0, (
        f"mutation_sim.py failed with exit code {process.returncode}. "
        f"stdout={stdout!r}, stderr={stderr!r}"
    )
    assert max_children >= 2, (
        "The script did not run work in parallel with ProcessPoolExecutor; "
        f"observed at most {max_children} child process(es)."
    )
    assert os.path.isfile(result_path), f"File {result_path} does not exist after running the script."


def test_script_is_executed_and_uses_parallel_workers():
    run_script_and_observe_workers()


def test_reproducible_result_matches_expected():
    result_path = "/home/user/reproducible_result.txt"
    assert os.path.isfile(result_path), f"File {result_path} does not exist. Did you run the script?"

    with open(result_path, "r") as f:
        actual_result = f.read().strip()

    venv_python = "/home/user/venv/bin/python"
    if not os.path.isfile(venv_python):
        venv_python = "python3"

    verifier_script = """
import numpy as np
import random

random.seed(42)
sequences = {}
for i in range(1, 101):
    seq_id = f"SEQ_{i:03d}"
    seq = "".join(random.choices(['A', 'C', 'G', 'T'], k=500))
    sequences[seq_id] = seq

def simulate(seq_id, sequence):
    numeric_id = int(seq_id.split('_')[1])
    np.random.seed(numeric_id)
    mutations = 0.0
    for char in sequence:
        if char == 'A': mutations += np.random.uniform(0, 0.01)
        elif char == 'C': mutations += np.random.uniform(0, 0.02)
        elif char == 'G': mutations += np.random.uniform(0, 0.015)
        elif char == 'T': mutations += np.random.uniform(0, 0.005)
    return mutations

total = 0.0
for sid in sorted(sequences.keys()):
    total += simulate(sid, sequences[sid])

print(f"{total:.15f}")
"""

    process = subprocess.run([venv_python, "-c", verifier_script], capture_output=True, text=True)
    assert process.returncode == 0, f"Failed to run verification script to compute truth. Is numpy installed? Error: {process.stderr}"

    expected_result = process.stdout.strip()
    assert actual_result == expected_result, f"Result mismatch! Expected {expected_result}, but got {actual_result}. Ensure floating point addition happens strictly in lexicographical order."


def test_script_maintains_parallelism():
    script_path = "/home/user/mutation_sim.py"
    assert os.path.isfile(script_path), f"File {script_path} does not exist."
    with open(script_path, "r") as f:
        content = f.read()

    assert "concurrent.futures.ProcessPoolExecutor" in content, "The script must maintain parallel execution using ProcessPoolExecutor."


def test_reduction_is_lexicographical_not_completion_or_input_order():
    script_path = "/home/user/mutation_sim.py"
    fasta_path = "/home/user/sequences.fasta"
    result_path = "/home/user/reproducible_result.txt"

    with open(fasta_path, "rb") as f:
        original_fasta = f.read()

    class FakeFuture:
        def __init__(self, fn, args):
            self.fn = fn
            self.args = args

        def result(self):
            return self.fn(*self.args)

    class FakeExecutor:
        def __init__(self, *args, **kwargs):
            pass

        def __enter__(self):
            return self

        def __exit__(self, exc_type, exc, tb):
            return False

        def submit(self, fn, *args, **kwargs):
            assert not kwargs
            return FakeFuture(fn, args)

        def map(self, fn, *iterables, **kwargs):
            return [fn(*args) for args in zip(*iterables)]

        def shutdown(self, *args, **kwargs):
            pass

    scenarios = [
        ["SEQ_002", "SEQ_003", "SEQ_001"],
        ["SEQ_001", "SEQ_003", "SEQ_002"],
    ]
    values = {"SEQ_001": 1.0, "SEQ_002": 1.0e16, "SEQ_003": 1.0}
    expected_total = 0.0
    for sid in sorted(values):
        expected_total += values[sid]
    expected = f"{expected_total:.15f}"

    try:
        for index, insertion_order in enumerate(scenarios):
            with open(fasta_path, "w") as f:
                for sid in insertion_order:
                    f.write(f">{sid}\nA\n")

            spec = importlib.util.spec_from_file_location(f"mutation_sim_under_test_{index}", script_path)
            module = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(module)

            assert hasattr(module, "main"), "mutation_sim.py must provide and execute its main workflow."
            assert hasattr(module, "concurrent") and hasattr(module.concurrent, "futures"), (
                "The required concurrent.futures.ProcessPoolExecutor workflow is missing."
            )

            def fake_simulate(seq_id, sequence):
                return seq_id, values[seq_id]

            module.simulate_mutations = fake_simulate
            futures_module = module.concurrent.futures
            old_executor = futures_module.ProcessPoolExecutor
            old_as_completed = futures_module.as_completed
            futures_module.ProcessPoolExecutor = FakeExecutor
            futures_module.as_completed = lambda futures: list(reversed(list(futures)))
            try:
                if os.path.exists(result_path):
                    os.remove(result_path)
                module.main()
            finally:
                futures_module.ProcessPoolExecutor = old_executor
                futures_module.as_completed = old_as_completed

            assert os.path.isfile(result_path), "Running main() did not create reproducible_result.txt."
            with open(result_path, "r") as f:
                actual = f.read().strip()
            assert actual == expected, (
                "The reduction is not performed strictly in lexicographical Sequence-ID order. "
                f"Expected {expected}, got {actual} for insertion order {insertion_order}."
            )
    finally:
        with open(fasta_path, "wb") as f:
            f.write(original_fasta)
        process = subprocess.run(
            [selected_python(), script_path], capture_output=True, text=True, timeout=60
        )
        assert process.returncode == 0, (
            "mutation_sim.py failed after restoring the original dataset: " + process.stderr
        )


TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
