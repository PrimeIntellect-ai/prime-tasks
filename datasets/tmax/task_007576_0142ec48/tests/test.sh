#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import sys
import csv
import math
import random
import runpy
import signal
import importlib

HOME = "/home/user"
if HOME not in sys.path:
    sys.path.insert(0, HOME)


def simulate_mutations(args):
    seq, seed = args
    random.seed(seed)
    energy = len(seq) * 0.01
    for _ in range(100):
        energy += random.uniform(-0.1, 0.1) * math.pi
    return energy


def get_expected_energy_truth(seq, num_trials=500):
    args = [(seq, i) for i in range(num_trials)]
    results = list(map(simulate_mutations, args))
    return math.fsum(results) / num_trials


def test_mc_energy_fixed():
    path = "/home/user/mc_energy.py"
    assert os.path.exists(path), f"File missing: {path}"
    assert os.path.isfile(path), f"Not a regular file: {path}"
    with open(path, "r") as f:
        content = f.read()
    assert "imap_unordered" not in content, "mc_energy.py still contains 'imap_unordered'."
    assert "fsum" in content, "mc_energy.py must use math.fsum() for summation."

    sys.modules.pop("mc_energy", None)
    mod = importlib.import_module("mc_energy")
    assert callable(getattr(mod, "get_expected_energy", None)), \
        "mc_energy.py must define callable get_expected_energy()."

    # Exercise the real implementation and compare against independently derived answers.
    for seq, trials in [("ACGTACG", 17), ("G" * 53, 31)]:
        expected = get_expected_energy_truth(seq, trials)
        first = mod.get_expected_energy(seq, num_trials=trials)
        second = mod.get_expected_energy(seq, num_trials=trials)
        assert first == expected, \
            f"get_expected_energy returned {first!r}; expected exactly {expected!r}."
        assert second == first, "Repeated calls are not strictly reproducible."

    # Instrument reduction so comments or fake implementations cannot satisfy the check.
    pool_calls = []
    fsum_inputs = []
    prescribed = [1.0e16, 1.0, -1.0e16]

    class FakePool:
        def __init__(self, *args, **kwargs):
            pool_calls.append("constructed")
        def __enter__(self):
            return self
        def __exit__(self, exc_type, exc, tb):
            return False
        def map(self, func, iterable, *args, **kwargs):
            list(iterable)
            pool_calls.append("map")
            return list(prescribed)
        def imap(self, func, iterable, *args, **kwargs):
            list(iterable)
            pool_calls.append("imap")
            return iter(prescribed)
        def imap_unordered(self, *args, **kwargs):
            raise AssertionError("get_expected_energy used nondeterministic imap_unordered")

    original_pool = mod.Pool
    original_fsum = mod.math.fsum

    def recording_fsum(values):
        values = list(values)
        fsum_inputs.append(values)
        return original_fsum(values)

    try:
        mod.Pool = FakePool
        mod.math.fsum = recording_fsum
        result = mod.get_expected_energy("ACGT", num_trials=3)
    finally:
        mod.Pool = original_pool
        mod.math.fsum = original_fsum

    assert "constructed" in pool_calls, "get_expected_energy did not use its worker pool."
    assert "map" in pool_calls or "imap" in pool_calls, \
        "Pool results were not collected with deterministic map/imap."
    assert fsum_inputs == [prescribed], \
        "get_expected_energy did not pass the collected results to math.fsum()."
    assert result == original_fsum(prescribed) / 3, \
        "get_expected_energy did not average the math.fsum() result correctly."


def test_generate_data_script_exists_and_executes():
    path = "/home/user/generate_data.py"
    assert os.path.exists(path), f"File missing: {path}"
    assert os.path.isfile(path), f"Not a regular file: {path}"

    import mc_energy
    calls = []

    def fake_expected_energy(seq, num_trials=500):
        calls.append((seq, num_trials))
        return len(calls) + 0.125

    output_paths = [
        "/home/user/training_dataset.csv",
        "/home/user/visualization.png",
    ]
    backups = {}
    for output in output_paths:
        if os.path.exists(output):
            with open(output, "rb") as f:
                backups[output] = f.read()
        if os.path.exists(output):
            os.remove(output)

    old_function = mc_energy.get_expected_energy
    old_cwd = os.getcwd()
    old_handler = signal.getsignal(signal.SIGALRM)

    def timeout_handler(signum, frame):
        raise TimeoutError("generate_data.py did not finish within 180 seconds")

    try:
        mc_energy.get_expected_energy = fake_expected_energy
        os.chdir(HOME)
        signal.signal(signal.SIGALRM, timeout_handler)
        signal.alarm(180)
        runpy.run_path(path, run_name="__main__")
        signal.alarm(0)

        random.seed(42)
        expected_sequences = [
            ''.join(random.choices("ACGT", k=50)) for _ in range(100)
        ]
        assert calls == [(seq, 500) for seq in expected_sequences], \
            "generate_data.py must sequentially generate 100 seeded sequences and call get_expected_energy(seq, num_trials=500) for each."

        csv_path = "/home/user/training_dataset.csv"
        assert os.path.isfile(csv_path), "Executing generate_data.py did not create training_dataset.csv."
        with open(csv_path, newline="") as f:
            rows = list(csv.reader(f))
        assert rows and rows[0] == ["Sequence", "Energy"], \
            "Generated CSV header must be Sequence,Energy."
        assert len(rows) == 101, "Executing generate_data.py must generate exactly 100 data rows."
        for i, row in enumerate(rows[1:]):
            assert len(row) == 2
            assert row[0] == expected_sequences[i]
            assert float(row[1]) == i + 1.125, \
                "The CSV must contain the values returned by get_expected_energy."

        png_path = "/home/user/visualization.png"
        assert os.path.isfile(png_path), "Executing generate_data.py did not create visualization.png."
        assert os.path.getsize(png_path) > 0, "Visualization image is empty."
        with open(png_path, "rb") as f:
            assert f.read(8) == b"\x89PNG\r\n\x1a\n", "visualization.png is not a PNG file."
        import matplotlib.image as mpimg
        image = mpimg.imread(png_path)
        assert image.size > 0 and image.ndim in (2, 3), "visualization.png is not a decodable plot image."
    finally:
        signal.alarm(0)
        signal.signal(signal.SIGALRM, old_handler)
        os.chdir(old_cwd)
        mc_energy.get_expected_energy = old_function
        for output in output_paths:
            if output in backups:
                with open(output, "wb") as f:
                    f.write(backups[output])
            elif os.path.exists(output):
                os.remove(output)


def test_visualization_exists():
    path = "/home/user/visualization.png"
    assert os.path.exists(path), f"File missing: {path}"
    assert os.path.getsize(path) > 0, "Visualization image is empty."


def test_training_dataset():
    path = "/home/user/training_dataset.csv"
    assert os.path.exists(path), f"File missing: {path}"

    random.seed(42)
    expected_sequences = [''.join(random.choices("ACGT", k=50)) for _ in range(100)]

    with open(path, "r") as f:
        reader = csv.reader(f)
        header = next(reader, None)
        assert header == ["Sequence", "Energy"], "CSV header must be Sequence,Energy"
        rows = list(reader)

    assert len(rows) == 100, f"Expected 100 rows in CSV, got {len(rows)}"

    for i, row in enumerate(rows):
        assert len(row) == 2, f"Row {i+1} does not have exactly 2 columns."
        seq, energy_str = row
        assert seq == expected_sequences[i], f"Sequence at row {i+1} is incorrect."

        expected_energy = get_expected_energy_truth(seq)
        try:
            energy_val = float(energy_str)
        except ValueError:
            assert False, f"Energy value at row {i+1} is not a valid float: {energy_str}"

        assert math.isclose(energy_val, expected_energy, rel_tol=1e-12), \
            f"Energy value at row {i+1} is incorrect. Expected ~{expected_energy}, got {energy_val}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
