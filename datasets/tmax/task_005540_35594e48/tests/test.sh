#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import subprocess

RESOLVER = "/home/user/project/resolver.py"
DEPS_PATH = "/home/user/project/deps.json"
COSTS_PATH = "/home/user/project/costs.json"
BUILD_ORDER_PATH = "/home/user/build_order.txt"
CRITICAL_PATH_PATH = "/home/user/critical_path.txt"


def expected_critical_path(deps, costs):
    memo = {}

    def path_cost(module):
        if module not in memo:
            child_cost = max((path_cost(dep) for dep in deps[module]), default=0)
            memo[module] = costs[module] + child_cost
        return memo[module]

    return max((path_cost(module) for module in deps), default=0)


def validate_generated_outputs(deps, costs):
    assert os.path.isfile(BUILD_ORDER_PATH), "resolver.py did not create build_order.txt"
    assert os.path.isfile(CRITICAL_PATH_PATH), "resolver.py did not create critical_path.txt"

    with open(BUILD_ORDER_PATH, "r") as f:
        order_str = f.read().strip()
    assert order_str, "resolver.py generated an empty build order"
    order = [item.strip() for item in order_str.split(",")]

    assert len(order) == len(deps), "Generated build order has duplicates or missing modules"
    assert set(order) == set(deps), "Generated build order has incorrect modules"

    positions = {module: index for index, module in enumerate(order)}
    for module, dependencies in deps.items():
        for dependency in dependencies:
            assert positions[dependency] < positions[module], (
                f"Dependency {dependency!r} was emitted after {module!r}"
            )

    with open(CRITICAL_PATH_PATH, "r") as f:
        actual_cp = f.read().strip()
    expected_cp = expected_critical_path(deps, costs)
    assert actual_cp == str(expected_cp), (
        f"Expected critical path {expected_cp}, got {actual_cp!r}"
    )


def test_resolver_executes_and_handles_fresh_graphs():
    assert os.path.isfile(RESOLVER), f"File {RESOLVER} does not exist."
    assert not os.path.islink(RESOLVER), "resolver.py must be a regular Python source file"

    with open(DEPS_PATH, "rb") as f:
        original_deps = f.read()
    with open(COSTS_PATH, "rb") as f:
        original_costs = f.read()

    rng = secrets.SystemRandom()
    try:
        for case_number in range(3):
            count = rng.randrange(8, 14)
            token = secrets.token_hex(6)
            nodes = [f"mod_{token}_{i}" for i in range(count)]
            deps = {}
            for i, module in enumerate(nodes):
                earlier = nodes[:i]
                selected = [d for d in earlier if rng.random() < 0.30]
                if i > 0 and not selected and rng.random() < 0.75:
                    selected = [rng.choice(earlier)]
                deps[module] = selected

            # Ensure each generated graph has both a nontrivial chain and branching.
            deps[nodes[1]] = [nodes[0]]
            deps[nodes[2]] = [nodes[0]]
            deps[nodes[3]] = [nodes[1], nodes[2]]
            costs = {module: rng.randrange(1, 40) for module in nodes}

            with open(DEPS_PATH, "w") as f:
                json.dump(deps, f)
            with open(COSTS_PATH, "w") as f:
                json.dump(costs, f)

            for output in (BUILD_ORDER_PATH, CRITICAL_PATH_PATH):
                try:
                    os.remove(output)
                except FileNotFoundError:
                    pass

            result = subprocess.run(
                ["python3", RESOLVER],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=10,
            )
            assert result.returncode == 0, (
                f"resolver.py failed on generated case {case_number}: {result.stderr}"
            )
            validate_generated_outputs(deps, costs)
    finally:
        with open(DEPS_PATH, "wb") as f:
            f.write(original_deps)
        with open(COSTS_PATH, "wb") as f:
            f.write(original_costs)
        subprocess.run(
            ["python3", RESOLVER],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=10,
            check=False,
        )


def test_build_order_valid():
    deps_path = "/home/user/project/deps.json"
    build_order_path = "/home/user/build_order.txt"

    assert os.path.isfile(deps_path), f"File {deps_path} does not exist."
    assert os.path.isfile(build_order_path), f"File {build_order_path} does not exist."

    with open(deps_path, 'r') as f:
        deps = json.load(f)

    with open(build_order_path, 'r') as f:
        order_str = f.read().strip()

    assert order_str, "build_order.txt is empty."

    order = [x.strip() for x in order_str.split(',')]

    expected_modules = set(deps.keys())
    actual_modules = set(order)

    assert expected_modules == actual_modules, f"Build order modules do not match expected. Expected: {expected_modules}, Got: {actual_modules}"
    assert len(order) == len(expected_modules), "Build order contains duplicate modules."

    seen = set()
    for module in order:
        module_deps = deps.get(module, [])
        for d in module_deps:
            assert d in seen, f"Dependency '{d}' of module '{module}' appears after it in the build order."
        seen.add(module)


def test_critical_path_correct():
    cp_path = "/home/user/critical_path.txt"
    assert os.path.isfile(cp_path), f"File {cp_path} does not exist."

    with open(cp_path, 'r') as f:
        cp_str = f.read().strip()

    assert cp_str == "48", f"Critical path value is incorrect. Expected '48', got '{cp_str}'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
