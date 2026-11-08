#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import subprocess
import pytest


def get_particles():
    path = "/home/user/particles.csv"
    particles = []
    with open(path, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            parts = line.split(',')
            particles.append({
                'id': int(parts[0]),
                'x': float(parts[1]),
                'y': float(parts[2]),
                'z': float(parts[3]),
                'q': float(parts[4])
            })
    return particles


def compute_expected_edges(particles):
    edges = []
    for i in range(len(particles)):
        for j in range(i + 1, len(particles)):
            p1 = particles[i]
            p2 = particles[j]
            if p1['id'] >= p2['id']:
                continue
            dx = p1['x'] - p2['x']
            dy = p1['y'] - p2['y']
            dz = p1['z'] - p2['z']
            dist = math.sqrt(dx * dx + dy * dy + dz * dz)
            if dist < 4.0:
                energy = (p1['q'] * p2['q']) / dist
                edges.append((p1['id'], p2['id'], round(energy, 4)))
    edges.sort(key=lambda e: (e[0], e[1]))
    return edges


def read_edges(path):
    actual_edges = []
    with open(path, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            parts = line.split(',')
            assert len(parts) == 3, f"Malformed edge line: {line}"
            actual_edges.append((int(parts[0]), int(parts[1]), float(parts[2])))
    return actual_edges


def assert_edges_match(actual_edges, expected_edges):
    actual_edges.sort(key=lambda e: (e[0], e[1]))
    assert len(actual_edges) == len(expected_edges), \
        f"Expected {len(expected_edges)} edges, got {len(actual_edges)}"
    for act, exp in zip(actual_edges, expected_edges):
        assert act[0] == exp[0] and act[1] == exp[1], \
            f"Edge ID mismatch: {act} vs {exp}"
        assert math.isclose(act[2], exp[2], abs_tol=1e-4), \
            f"Energy mismatch for edge {act[0]}-{act[1]}: expected {exp[2]}, got {act[2]}"


def parse_ci(path):
    with open(path, "r") as f:
        content = f.read().strip()

    lines = content.split('\n')
    assert len(lines) == 2, f"Expected 2 lines in {path}, got {len(lines)}"
    assert lines[0].startswith("Lower: "), "First line must start with 'Lower: '"
    assert lines[1].startswith("Upper: "), "Second line must start with 'Upper: '"

    lower_val = lines[0].split("Lower: ", 1)[1].strip()
    upper_val = lines[1].split("Upper: ", 1)[1].strip()
    try:
        lower_f = float(lower_val)
        upper_f = float(upper_val)
    except ValueError:
        pytest.fail("Lower and Upper values in ci.txt must be numeric.")

    assert math.isfinite(lower_f) and math.isfinite(upper_f), \
        "Lower and Upper values must be finite."
    assert lower_f <= upper_f, \
        "Lower bound should be less than or equal to Upper bound."
    return lower_f, upper_f


def test_step1_pairwise_and_edges():
    script_path = "/home/user/step1_pairwise.sh"
    assert os.path.isfile(script_path), f"Missing {script_path}"
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable"

    edges_path = "/home/user/edges.csv"
    assert os.path.isfile(edges_path), f"Missing {edges_path}"

    expected_edges = compute_expected_edges(get_particles())
    assert_edges_match(read_edges(edges_path), expected_edges)

    # Execute the submitted artifact and require it to regenerate the output.
    os.remove(edges_path)
    result = subprocess.run(
        [script_path], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, timeout=30
    )
    assert result.returncode == 0, \
        f"{script_path} failed: {result.stderr}"
    assert os.path.isfile(edges_path), \
        f"{script_path} did not create {edges_path}"
    assert_edges_match(read_edges(edges_path), expected_edges)


def expected_truncated_total(edges):
    total = 0.0
    for edge in sorted(edges, key=lambda e: (e[0], e[1])):
        total += edge[2]
        total = int(total * 100) / 100.0
    return f"Total Energy: {total:.2f}"


def test_total_energy_fixed():
    script_path = "/home/user/total_energy.sh"
    assert os.path.isfile(script_path), f"Missing {script_path}"
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable"

    with open(script_path, "r") as f:
        content = f.read()

    # Preserve the original assertion.
    assert "sort" in content, \
        "The script /home/user/total_energy.sh does not use 'sort' to fix the reduction order."

    fixed_path = "/home/user/total_fixed.txt"
    assert os.path.isfile(fixed_path), f"Missing {fixed_path}"

    expected_edges = compute_expected_edges(get_particles())
    total = 0.0
    for e in sorted(expected_edges, key=lambda e: (e[0], e[1])):
        total += e[2]
        total = int(total * 100) / 100.0

    with open(fixed_path, "r") as f:
        fixed_content = f.read().strip()

    expected_str = f"Total Energy: {total:.2f}"
    assert expected_str in fixed_content, \
        f"Expected '{expected_str}' in {fixed_path}, got '{fixed_content}'"

    # Execute the script on the real data as well as adversarially ordered data.
    real_run = subprocess.run(
        [script_path], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, timeout=30
    )
    assert real_run.returncode == 0, real_run.stderr
    assert real_run.stdout.strip() == expected_str, \
        f"Executing {script_path} produced {real_run.stdout!r}, expected {expected_str!r}"

    edges_path = "/home/user/edges.csv"
    with open(edges_path, "rb") as f:
        original_edges = f.read()

    cases = [
        # Numeric sorting by the first field must produce +,+,- in this order.
        "10,1,-0.019\n3,1,0.019\n2,1,0.019\n",
        # Numeric sorting by the second field must produce +,+,- in this order.
        "1,10,-0.019\n1,3,0.019\n1,2,0.019\n",
    ]
    try:
        for data in cases:
            with open(edges_path, "w") as f:
                f.write(data)
            # Repeated runs also reject a remaining shuffle after the sort.
            for _ in range(8):
                run = subprocess.run(
                    [script_path], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                    text=True, timeout=30
                )
                assert run.returncode == 0, run.stderr
                assert run.stdout.strip() == "Total Energy: 0.00", \
                    "total_energy.sh did not numerically sort both IDs before applying " \
                    f"the original per-line truncating sum; got {run.stdout!r}"
    finally:
        with open(edges_path, "wb") as f:
            f.write(original_edges)


def test_step3_bootstrap_and_ci():
    script_path = "/home/user/step3_bootstrap.sh"
    assert os.path.isfile(script_path), f"Missing {script_path}"
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable"

    ci_path = "/home/user/ci.txt"
    assert os.path.isfile(ci_path), f"Missing {ci_path}"

    # Preserve the original shape and ordering assertions on the submitted result.
    parse_ci(ci_path)

    edges_path = "/home/user/edges.csv"
    with open(edges_path, "rb") as f:
        original_edges = f.read()
    with open(ci_path, "rb") as f:
        original_ci = f.read()

    try:
        # Ten rows containing five zeros and five ones have bootstrap sums
        # distributed as Binomial(10, 0.5). For 1000 samples, the requested
        # empirical 25th and 975th order statistics are overwhelmingly 2 and 8.
        # Sampling without replacement instead gives the fixed sum 5.
        with open(edges_path, "w") as f:
            for i in range(1, 6):
                f.write(f"{i},{i + 100},0.0000\n")
            for i in range(6, 11):
                f.write(f"{i},{i + 100},1.0000\n")

        os.remove(ci_path)
        run = subprocess.run(
            [script_path], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True, timeout=120
        )
        assert run.returncode == 0, f"{script_path} failed: {run.stderr}"
        assert os.path.isfile(ci_path), f"{script_path} did not create {ci_path}"

        lower, upper = parse_ci(ci_path)
        assert lower == pytest.approx(2.0, abs=1e-9), \
            f"Expected the 25th bootstrap sum to be 2.0000, got {lower}"
        assert upper == pytest.approx(8.0, abs=1e-9), \
            f"Expected the 975th bootstrap sum to be 8.0000, got {upper}"
    finally:
        with open(edges_path, "wb") as f:
            f.write(original_edges)
        with open(ci_path, "wb") as f:
            f.write(original_ci)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
