#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import importlib.util
import multiprocessing as real_mp
import os
import subprocess
import sys

SCRIPT_PATH = "/home/user/integrate_mutation.py"
RESULT_PATH = "/home/user/final_result.txt"
RAW_PATH = "/home/user/raw_sequence.txt"


def get_expected_result():
    script = r'''
import numpy as np
np.random.seed(42)
seq = "".join(np.random.choice(['A', 'C', 'G', 'T'], size=1000000))
chunk_size = 50000
chunks = [(i, seq[i:i+chunk_size]) for i in range(0, len(seq), chunk_size)]
results = []
for idx, chunk in chunks:
    gc_counts = np.array([1.1 if b in 'GC' else 0.9 for b in chunk])
    cum_gc = np.cumsum(gc_counts)
    integral = np.trapz(np.sin(cum_gc))
    results.append(integral)
expected_total = sum(results)
print(f"{expected_total:.12f}")
'''
    result = subprocess.run(
        [sys.executable, "-c", script],
        capture_output=True,
        text=True,
        check=True,
        timeout=120,
    )
    return result.stdout.strip()


def test_script_fixed_and_process_chunk_unchanged():
    with open(SCRIPT_PATH, "r") as f:
        content = f.read()

    assert "imap_unordered" not in content, (
        "The script still contains 'imap_unordered'. You must use a sequential "
        "combination method (like imap or map)."
    )

    submitted = ast.parse(content)
    expected = ast.parse(r'''
def process_chunk(data_tuple):
    idx, chunk = data_tuple
    gc_counts = np.array([1.1 if b in 'GC' else 0.9 for b in chunk])
    cum_gc = np.cumsum(gc_counts)
    integral = np.trapz(np.sin(cum_gc))
    return integral
''')
    submitted_functions = [
        node for node in submitted.body
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef))
        and node.name == "process_chunk"
    ]
    assert len(submitted_functions) == 1, "process_chunk must remain defined exactly once."
    assert ast.dump(submitted_functions[0], include_attributes=False) == ast.dump(
        expected.body[0], include_attributes=False
    ), "Do not change the mathematical logic inside process_chunk."


def test_run_script_and_final_result_correctness():
    completed = subprocess.run(
        [sys.executable, SCRIPT_PATH],
        capture_output=True,
        text=True,
        timeout=120,
    )
    assert completed.returncode == 0, (
        "The submitted script did not run successfully.\n"
        f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
    )

    assert os.path.isfile(RESULT_PATH), (
        f"The file {RESULT_PATH} does not exist. Did the script run successfully?"
    )
    with open(RESULT_PATH, "r") as f:
        actual_result = f.read().strip()
    expected_result = get_expected_result()
    assert actual_result == expected_result, (
        f"The result in {RESULT_PATH} is incorrect.\n"
        f"Expected: {expected_result}\nActual:   {actual_result}\n"
        "Ensure that you are summing the chunks in strict sequential order."
    )


FINAL_ORDERS = []
CONVERSION_ORDER = []


class OrderedProbe:
    def __init__(self, value, order):
        self.value = float(value)
        self.order = list(order)

    @staticmethod
    def _parts(other):
        if isinstance(other, OrderedProbe):
            return other.value, other.order
        return float(other), []

    def __add__(self, other):
        value, order = self._parts(other)
        return OrderedProbe(self.value + value, self.order + order)

    def __radd__(self, other):
        value, order = self._parts(other)
        return OrderedProbe(value + self.value, order + self.order)

    def __float__(self):
        CONVERSION_ORDER.extend(self.order)
        return self.value

    def __format__(self, spec):
        FINAL_ORDERS.append(list(self.order))
        return format(self.value, spec)


def probe_process_chunk(data_tuple):
    idx, chunk = data_tuple
    return OrderedProbe(idx // 50000 + 1, [idx])


class TrackingPool:
    used_process_chunk = False
    REAL_POOL = real_mp.Pool

    def __init__(self, *args, **kwargs):
        self._pool = self.REAL_POOL(*args, **kwargs)

    @classmethod
    def _mark(cls, func):
        if func is probe_process_chunk:
            cls.used_process_chunk = True

    def map(self, func, *args, **kwargs):
        self._mark(func)
        return self._pool.map(func, *args, **kwargs)

    def imap(self, func, *args, **kwargs):
        self._mark(func)
        return self._pool.imap(func, *args, **kwargs)

    def starmap(self, func, *args, **kwargs):
        self._mark(func)
        return self._pool.starmap(func, *args, **kwargs)

    def map_async(self, func, *args, **kwargs):
        self._mark(func)
        return self._pool.map_async(func, *args, **kwargs)

    def starmap_async(self, func, *args, **kwargs):
        self._mark(func)
        return self._pool.starmap_async(func, *args, **kwargs)

    def apply(self, func, *args, **kwargs):
        self._mark(func)
        return self._pool.apply(func, *args, **kwargs)

    def apply_async(self, func, *args, **kwargs):
        self._mark(func)
        return self._pool.apply_async(func, *args, **kwargs)

    def __enter__(self):
        self._pool.__enter__()
        return self

    def __exit__(self, exc_type, exc, tb):
        return self._pool.__exit__(exc_type, exc, tb)

    def __getattr__(self, name):
        return getattr(self._pool, name)


def test_parallel_workers_and_strict_aggregation_order():
    with open(RAW_PATH, "rb") as f:
        original_raw = f.read()
    original_result = None
    if os.path.exists(RESULT_PATH):
        with open(RESULT_PATH, "rb") as f:
            original_result = f.read()

    spec = importlib.util.spec_from_file_location("submitted_integrate_mutation", SCRIPT_PATH)
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)

    old_pool = module.mp.Pool
    FINAL_ORDERS.clear()
    CONVERSION_ORDER.clear()
    TrackingPool.used_process_chunk = False

    try:
        # Four distinct chunks make the aggregation order directly observable.
        with open(RAW_PATH, "w") as f:
            f.write("A" * 200000)

        module.process_chunk = probe_process_chunk
        module.mp.Pool = TrackingPool
        module.main()
    finally:
        module.mp.Pool = old_pool
        with open(RAW_PATH, "wb") as f:
            f.write(original_raw)
        if original_result is None:
            if os.path.exists(RESULT_PATH):
                os.remove(RESULT_PATH)
        else:
            with open(RESULT_PATH, "wb") as f:
                f.write(original_result)

    assert TrackingPool.used_process_chunk, (
        "main() must submit process_chunk to a multiprocessing Pool so parallel "
        "workers compute the chunk integrals."
    )

    expected_order = [0, 50000, 100000, 150000]
    ordered_final = any(order == expected_order for order in FINAL_ORDERS)
    ordered_conversions = CONVERSION_ORDER == expected_order
    assert ordered_final or ordered_conversions, (
        "Chunk results were not accumulated left-to-right in original chunk order. "
        f"Expected {expected_order}; observed final orders {FINAL_ORDERS} and "
        f"conversion order {CONVERSION_ORDER}."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
