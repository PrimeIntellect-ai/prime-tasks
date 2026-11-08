#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import heapq
import os
import random
import secrets
import subprocess
import tempfile

SCRIPT_PATH = "/home/user/resolve_env.sh"
ORDER_PATH = "/home/user/startup_order.txt"
PORTS_PATH = "/home/user/port_assignments.txt"


def read_nonempty_lines(path):
    with open(path, "r") as f:
        return [line.strip() for line in f if line.strip()]


def test_script_exists_and_executable():
    """Check that the bash script exists and is executable."""
    assert os.path.exists(SCRIPT_PATH), f"The script {SCRIPT_PATH} does not exist."
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is not a file."
    assert os.access(SCRIPT_PATH, os.X_OK), f"The script {SCRIPT_PATH} is not executable."


def test_startup_order_output():
    """Verify the topological sort output in startup_order.txt."""
    assert os.path.exists(ORDER_PATH), f"The output file {ORDER_PATH} does not exist."

    expected_lines = [
        "cache",
        "db",
        "auth",
        "backend",
        "frontend",
        "metrics"
    ]
    actual_lines = read_nonempty_lines(ORDER_PATH)

    assert actual_lines == expected_lines, (
        f"Contents of {ORDER_PATH} do not match the expected topological sort order.\n"
        f"Expected: {expected_lines}\n"
        f"Got: {actual_lines}"
    )


def test_port_assignments_output():
    """Verify the port allocation output in port_assignments.txt."""
    assert os.path.exists(PORTS_PATH), f"The output file {PORTS_PATH} does not exist."

    expected_lines = [
        "cache: 6379",
        "db: 5432",
        "auth: 5000",
        "backend: 5001",
        "frontend: 80",
        "metrics: 5002"
    ]
    actual_lines = read_nonempty_lines(PORTS_PATH)

    assert actual_lines == expected_lines, (
        f"Contents of {PORTS_PATH} do not match the expected port assignments.\n"
        f"Expected: {expected_lines}\n"
        f"Got: {actual_lines}"
    )


def resolve_expected(services, dependencies, ranges):
    indegree = {service: len(dependencies[service]) for service in services}
    dependents = {service: [] for service in services}
    for service in services:
        for dependency in dependencies[service]:
            dependents[dependency].append(service)

    eligible = [service for service in services if indegree[service] == 0]
    heapq.heapify(eligible)
    order = []
    while eligible:
        service = heapq.heappop(eligible)
        order.append(service)
        for dependent in dependents[service]:
            indegree[dependent] -= 1
            if indegree[dependent] == 0:
                heapq.heappush(eligible, dependent)

    assert len(order) == len(services)

    used = set()
    allocations = []
    for service in order:
        minimum, maximum = ranges[service]
        port = next(port for port in range(minimum, maximum + 1) if port not in used)
        used.add(port)
        allocations.append(f"{service}: {port}")
    return order, allocations


def test_script_executes_and_resolves_alternate_inputs():
    rng = random.SystemRandom()

    for _ in range(3):
        services = [f"svc_{secrets.token_hex(5)}" for _ in range(7)]
        dependencies = {
            services[0]: [],
            services[1]: [],
            services[2]: [services[0]],
            services[3]: [services[0], services[1]],
            services[4]: [services[2], services[3]],
            services[5]: [services[1]],
            services[6]: [services[2]],
        }

        base_port = rng.randint(20000, 40000)
        ranges = {
            service: (base_port + (index % 3), base_port + len(services) + 5)
            for index, service in enumerate(services)
        }
        expected_order, expected_allocations = resolve_expected(
            services, dependencies, ranges
        )

        with tempfile.TemporaryDirectory(prefix="resolve_env_test_") as temp_dir:
            os.chmod(temp_dir, 0o755)
            deps_path = os.path.join(temp_dir, "alternate.deps")
            ports_path = os.path.join(temp_dir, "alternate.ports")

            deps_lines = []
            for service in services:
                suffix = " " + " ".join(dependencies[service]) if dependencies[service] else ""
                deps_lines.append(f"{service}:{suffix}")
            rng.shuffle(deps_lines)

            port_lines = [
                f"{service}: {ranges[service][0]}-{ranges[service][1]}"
                for service in services
            ]
            rng.shuffle(port_lines)

            with open(deps_path, "w") as f:
                f.write("\n".join(deps_lines) + "\n")
            with open(ports_path, "w") as f:
                f.write("\n".join(port_lines) + "\n")
            os.chmod(deps_path, 0o644)
            os.chmod(ports_path, 0o644)

            for output_path in (ORDER_PATH, PORTS_PATH):
                if os.path.exists(output_path):
                    os.remove(output_path)

            result = subprocess.run(
                [SCRIPT_PATH, deps_path, ports_path],
                cwd="/home/user",
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=10,
            )
            assert result.returncode == 0, (
                f"Script failed on alternate inputs with exit code {result.returncode}.\n"
                f"stdout: {result.stdout}\nstderr: {result.stderr}"
            )
            assert os.path.isfile(ORDER_PATH), "Script did not create startup_order.txt"
            assert os.path.isfile(PORTS_PATH), "Script did not create port_assignments.txt"
            assert read_nonempty_lines(ORDER_PATH) == expected_order
            assert read_nonempty_lines(PORTS_PATH) == expected_allocations
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
