#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import itertools
import pytest

def solve_dependencies(api_dump):
    packages = api_dump.get("packages", {})
    dependencies = api_dump.get("dependencies", {})
    root = api_dump.get("root", {})

    def satisfies(version, min_v, max_v):
        return float(min_v) <= float(version) <= float(max_v)

    best_cost = float('inf')
    best_resolution = None

    pkg_names = list(packages.keys())

    # Generate all possible subsets of packages to find valid resolutions
    for r in range(1, len(pkg_names) + 1):
        for subset in itertools.combinations(pkg_names, r):
            if root.get("package") not in subset:
                continue

            version_lists = [[v["version"] for v in packages[name]] for name in subset]
            for combo in itertools.product(*version_lists):
                current_assignment = dict(zip(subset, combo))

                # Determine required packages and constraints based on current assignment
                required = {root["package"]: [(root["min_version"], root["max_version"])]}

                changed = True
                while changed:
                    changed = False
                    for pkg, ver in current_assignment.items():
                        if pkg in required:
                            dep_key = f"{pkg}@{ver}"
                            deps = dependencies.get(dep_key, [])
                            for d in deps:
                                req_pkg = d["package"]
                                req_min = d["min_version"]
                                req_max = d["max_version"]
                                if req_pkg not in required:
                                    required[req_pkg] = []
                                    changed = True
                                if (req_min, req_max) not in required[req_pkg]:
                                    required[req_pkg].append((req_min, req_max))
                                    changed = True

                # The assignment must contain exactly the required packages
                if set(current_assignment.keys()) != set(required.keys()):
                    continue

                # Check if all constraints are satisfied
                is_valid = True
                for pkg, reqs in required.items():
                    ver = current_assignment[pkg]
                    for min_v, max_v in reqs:
                        if not satisfies(ver, min_v, max_v):
                            is_valid = False
                            break
                    if not is_valid:
                        break

                if not is_valid:
                    continue

                # Calculate total cost
                cost = 0.0
                for pkg, ver in current_assignment.items():
                    for v_info in packages[pkg]:
                        if v_info["version"] == ver:
                            cost += v_info["cost"]
                            break

                if cost < best_cost:
                    best_cost = cost
                    best_resolution = current_assignment

    return best_cost, best_resolution

@pytest.fixture(scope="module")
def expected_solution():
    api_dump_path = "/home/user/api_dump.json"
    assert os.path.exists(api_dump_path), f"Input file {api_dump_path} is missing."
    with open(api_dump_path, "r") as f:
        api_dump = json.load(f)

    best_cost, best_resolution = solve_dependencies(api_dump)
    assert best_resolution is not None, "Could not find a valid resolution from the API dump."
    return best_cost, best_resolution

def test_min_cost_file(expected_solution):
    expected_cost, _ = expected_solution
    min_cost_path = "/home/user/min_cost.txt"

    assert os.path.exists(min_cost_path), f"Output file {min_cost_path} is missing."
    with open(min_cost_path, "r") as f:
        content = f.read().strip()

    try:
        actual_cost = float(content)
    except ValueError:
        pytest.fail(f"Content of {min_cost_path} is not a valid float: '{content}'")

    expected_cost_str = f"{expected_cost:.2f}"
    assert content == expected_cost_str, f"Expected cost to be formatted as '{expected_cost_str}', but got '{content}'."
    assert abs(actual_cost - expected_cost) < 1e-9, f"Expected minimum cost {expected_cost}, but got {actual_cost}."

def test_resolution_file(expected_solution):
    _, expected_resolution = expected_solution
    resolution_path = "/home/user/resolution.json"

    assert os.path.exists(resolution_path), f"Output file {resolution_path} is missing."
    with open(resolution_path, "r") as f:
        try:
            actual_resolution = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {resolution_path} does not contain valid JSON.")

    assert actual_resolution == expected_resolution, (
        f"Resolution mismatch.\nExpected: {expected_resolution}\nActual: {actual_resolution}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
