#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import subprocess

SERVICES = "/home/user/services.csv"
DEPENDENCIES = "/home/user/dependencies.csv"
SOURCE = "/home/user/calculate_costs.rs"
OUTPUT = "/home/user/highest_cost.txt"
BINARY = "/tmp/calculate_costs_verifier"

CANONICAL_SERVICES = """id,base_cost
S1,50
S2,120
S3,30
S4,200
S5,10
S6,80
S7,45
S8,15
"""

CANONICAL_DEPENDENCIES = """service_id,depends_on_id
S1,S2
S1,S3
S2,S4
S2,S5
S3,S5
S3,S6
S6,S7
S6,S8
"""


def test_highest_cost_file_exists_and_content():
    file_path = "/home/user/highest_cost.txt"
    assert os.path.isfile(file_path), f"Output file {file_path} is missing."

    with open(file_path, 'r') as f:
        content = f.read().strip()

    assert content == "S1:560", f"Expected 'S1:560' in {file_path}, but found '{content}'."


def test_rust_source_file_exists():
    file_path = "/home/user/calculate_costs.rs"
    assert os.path.isfile(file_path), f"Rust source file {file_path} is missing."


def expected_winners(costs, edges):
    dependencies = {service: [] for service in costs}
    for service, dependency in edges:
        dependencies[service].append(dependency)

    memo = {}

    def cumulative(service):
        if service not in memo:
            memo[service] = costs[service] + sum(
                cumulative(dependency) for dependency in dependencies[service]
            )
        return memo[service]

    totals = {service: cumulative(service) for service in costs}
    maximum = max(totals.values())
    return {f"{service}:{total}" for service, total in totals.items() if total == maximum}


def write_inputs(costs, edges, rng):
    service_rows = list(costs.items())
    dependency_rows = list(edges)
    rng.shuffle(service_rows)
    rng.shuffle(dependency_rows)

    with open(SERVICES, "w") as f:
        f.write("id,base_cost\n")
        for service, cost in service_rows:
            f.write(f"{service},{cost}\n")

    with open(DEPENDENCIES, "w") as f:
        f.write("service_id,depends_on_id\n")
        for service, dependency in dependency_rows:
            f.write(f"{service},{dependency}\n")


def run_and_check(accepted):
    if os.path.exists(OUTPUT):
        os.remove(OUTPUT)

    result = subprocess.run(
        [BINARY],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )
    assert result.returncode == 0, (
        f"Compiled program exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(OUTPUT), f"Program did not generate {OUTPUT}."
    with open(OUTPUT, "r") as f:
        actual = f.read().strip()
    assert actual in accepted, f"Expected one of {sorted(accepted)}, but found '{actual}'."


def test_program_compiles_runs_and_uses_csv_inputs():
    saved_services = open(SERVICES, "rb").read()
    saved_dependencies = open(DEPENDENCIES, "rb").read()
    saved_output = open(OUTPUT, "rb").read() if os.path.isfile(OUTPUT) else None

    try:
        compile_result = subprocess.run(
            ["rustc", SOURCE, "-o", BINARY],
            cwd="/home/user",
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
        )
        assert compile_result.returncode == 0, (
            f"Failed to compile {SOURCE}.\n"
            f"stdout:\n{compile_result.stdout}\nstderr:\n{compile_result.stderr}"
        )
        assert os.path.isfile(BINARY) and os.access(BINARY, os.X_OK)

        with open(SERVICES, "w") as f:
            f.write(CANONICAL_SERVICES)
        with open(DEPENDENCIES, "w") as f:
            f.write(CANONICAL_DEPENDENCIES)
        run_and_check({"S1:560"})

        rng = random.SystemRandom()
        for _ in range(3):
            tag = secrets.token_hex(6)
            ids = [f"svc_{tag}_{i}" for i in range(8)]
            costs = {service: rng.randint(7, 400) for service in ids}

            # A randomized DAG with a chain plus extra forward dependencies.
            # Positive costs make the first chain node the unique maximum, while
            # its exact cumulative value depends on both input files.
            edges = [(ids[i], ids[i + 1]) for i in range(len(ids) - 1)]
            for i in range(len(ids) - 2):
                for j in range(i + 2, len(ids)):
                    if rng.randrange(4) == 0:
                        edges.append((ids[i], ids[j]))

            accepted = expected_winners(costs, edges)
            write_inputs(costs, edges, rng)
            run_and_check(accepted)
    finally:
        with open(SERVICES, "wb") as f:
            f.write(saved_services)
        with open(DEPENDENCIES, "wb") as f:
            f.write(saved_dependencies)
        if saved_output is None:
            if os.path.exists(OUTPUT):
                os.remove(OUTPUT)
        else:
            with open(OUTPUT, "wb") as f:
                f.write(saved_output)
        if os.path.exists(BINARY):
            os.remove(BINARY)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
