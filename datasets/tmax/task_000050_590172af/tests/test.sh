#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import math
import os
import subprocess
import tempfile


def test_fixed_script_exists():
    path = "/home/user/fixed_aggregate.py"
    assert os.path.isfile(path), f"The fixed script {path} does not exist."


def test_stable_result_exists():
    path = "/home/user/stable_result.txt"
    assert os.path.isfile(path), f"The result file {path} does not exist."


def test_stable_result_value():
    import h5py
    import numpy as np
    import networkx as nx

    data_path = "/home/user/data.h5"
    assert os.path.isfile(data_path), f"Data file {data_path} is missing."

    # Compute the expected deterministic truth
    with h5py.File(data_path, 'r') as f:
        signals = f['signals'][:]
        edges = f['edges'][:]

    G = nx.Graph()
    G.add_edges_from(edges)
    largest_cc = max(nx.connected_components(G), key=len)

    # Sort nodes to guarantee deterministic order
    sorted_nodes = sorted(list(largest_cc))
    cc_signals = [signals[i] for i in sorted_nodes]

    total_power = 0.0
    for sig in cc_signals:
        fft_vals = np.fft.rfft(sig)
        power = float(np.max(np.abs(fft_vals)))
        total_power += power

    expected_value = total_power

    result_path = "/home/user/stable_result.txt"
    with open(result_path, "r") as f:
        content = f.read().strip()

    try:
        student_value = float(content)
    except ValueError:
        assert False, f"The file {result_path} does not contain a valid float. Content: '{content}'"

    # Preserve the original correctness assertion.
    assert math.isclose(student_value, expected_value, rel_tol=1e-11), \
        f"The computed value {student_value} does not match the expected deterministic value {expected_value}."


def test_script_is_sorted_and_does_not_use_unordered_mapping():
    path = "/home/user/fixed_aggregate.py"
    with open(path, "r", encoding="utf-8") as f:
        source = f.read()
    tree = ast.parse(source, filename=path)

    assert any(
        isinstance(node, ast.Call)
        and isinstance(node.func, ast.Name)
        and node.func.id == "sorted"
        for node in ast.walk(tree)
    ), "The corrected script must explicitly sort the component's node IDs."

    assert not any(
        isinstance(node, ast.Attribute) and node.attr == "imap_unordered"
        for node in ast.walk(tree)
    ), "The corrected script still uses imap_unordered."


def _expected_value(data_path):
    import h5py
    import numpy as np
    import networkx as nx

    with h5py.File(data_path, "r") as f:
        signals = f["signals"][:]
        edges = f["edges"][:]

    graph = nx.Graph()
    graph.add_edges_from(edges)
    largest_cc = max(nx.connected_components(graph), key=len)

    total = 0.0
    for node_id in sorted(largest_cc):
        peak = float(np.max(np.abs(np.fft.rfft(signals[node_id]))))
        total += peak
    return total


def _run_and_check(script_path, data_path):
    expected = _expected_value(data_path)
    completed = subprocess.run(
        ["python3", script_path],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=60,
        check=False,
    )
    assert completed.returncode == 0, \
        f"The corrected script failed with exit code {completed.returncode}: {completed.stderr}"

    lines = [line.strip() for line in completed.stdout.splitlines() if line.strip()]
    assert len(lines) == 1, \
        f"The script must print exactly one scalar value, but printed: {completed.stdout!r}"
    try:
        actual = float(lines[0])
    except ValueError:
        assert False, f"The script output is not a float: {completed.stdout!r}"
    assert math.isfinite(actual), f"The script produced a non-finite value: {actual}"

    # Accept either a full-precision representation or the original script's
    # 12-decimal formatting, while requiring the sorted-order result exactly.
    displayed_expected = float(f"{expected:.12f}")
    assert actual == expected or actual == displayed_expected, \
        f"Script output {actual} is not the sorted-order result {expected}."
    return lines[0]


def test_fixed_script_executes_on_original_and_derived_inputs():
    import h5py
    import numpy as np

    script_path = "/home/user/fixed_aggregate.py"
    data_path = "/home/user/data.h5"
    result_path = "/home/user/stable_result.txt"

    with open(result_path, "r", encoding="utf-8") as f:
        saved_result = f.read().strip()

    original_stdout = _run_and_check(script_path, data_path)
    assert saved_result == original_stdout, \
        "stable_result.txt must contain the standard output produced by the corrected script."

    backup_fd, backup_path = tempfile.mkstemp(suffix=".h5")
    os.close(backup_fd)
    os.replace(data_path, backup_path)
    try:
        # Verification-time data prevents a precomputed scalar from passing.
        rng = np.random.default_rng(int.from_bytes(os.urandom(16), "little"))
        for _ in range(2):
            while True:
                nodes = rng.choice(np.arange(1, 510), size=73, replace=False).tolist()
                if list(set(nodes)) != sorted(nodes):
                    break

            edge_order = nodes[:]
            rng.shuffle(edge_order)
            edges = [(edge_order[i], edge_order[i + 1]) for i in range(len(edge_order) - 1)]

            remaining = [i for i in range(512) if i not in set(nodes)]
            small = remaining[:5]
            edges.extend((small[i], small[i + 1]) for i in range(len(small) - 1))
            rng.shuffle(edges)

            signals = rng.standard_normal((512, 257))
            scales = 10.0 ** rng.uniform(-7.0, 7.0, size=len(nodes))
            for node, scale in zip(nodes, scales):
                signals[node] *= scale

            with h5py.File(data_path, "w") as f:
                f.create_dataset("signals", data=signals)
                f.create_dataset("edges", data=np.asarray(edges, dtype=np.int64))

            _run_and_check(script_path, data_path)
    finally:
        if os.path.exists(data_path):
            os.remove(data_path)
        os.replace(backup_path, data_path)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
