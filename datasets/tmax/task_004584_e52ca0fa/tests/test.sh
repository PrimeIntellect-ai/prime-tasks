#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import heapq
import json
import os
import secrets
import shutil
import stat
import string
import subprocess

import pytest

SOURCE = "/home/user/build_env.go"
DSL = "/home/user/mesh.dsl"
CONFIG = "/home/user/proxy_config.json"
BINARY = "/tmp/build_env_submission"


def run_program():
    if os.path.lexists(CONFIG):
        os.remove(CONFIG)
    subprocess.run([BINARY], check=True, timeout=20)
    assert os.path.isfile(CONFIG), f"The program did not generate {CONFIG}."


@pytest.fixture(scope="session", autouse=True)
def compile_and_run_submission():
    assert os.path.isfile(SOURCE), f"The required Go program {SOURCE} is missing."
    assert not os.path.islink(SOURCE), f"{SOURCE} must be a regular Go source file, not a symlink."
    assert stat.S_ISREG(os.stat(SOURCE).st_mode), f"{SOURCE} is not a regular file."
    subprocess.run(
        ["go", "build", "-o", BINARY, SOURCE],
        check=True,
        timeout=60,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    run_program()


def test_proxy_config_exists():
    file_path = "/home/user/proxy_config.json"
    assert os.path.isfile(file_path), f"The file {file_path} is missing. The Go program might not have generated it."


def test_proxy_config_content():
    file_path = "/home/user/proxy_config.json"
    assert os.path.isfile(file_path), f"The file {file_path} is missing."

    with open(file_path, "r") as f:
        try:
            config = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {file_path} does not contain valid JSON.")

    expected_config = {
        "DB": "http://localhost:8000",
        "Analytics": "http://localhost:8001",
        "Auth": "http://localhost:8002",
        "Ledger": "http://localhost:8003",
        "Notification": "http://localhost:8004",
        "Payment": "http://localhost:8005"
    }

    assert config == expected_config, f"The content of {file_path} does not match the expected topological sort and port assignment."


def derive_expected(dsl_text):
    dependencies = {}
    dependents = {}
    nodes = set()

    for raw_line in dsl_text.splitlines():
        line = raw_line.strip()
        if not line:
            continue
        left, right = (part.strip() for part in line.split("->", 1))
        nodes.add(left)
        dependencies.setdefault(left, set())
        if right != "NONE":
            nodes.add(right)
            dependencies[left].add(right)

    for node in nodes:
        dependencies.setdefault(node, set())
        dependents.setdefault(node, set())
    for service, deps in dependencies.items():
        for dependency in deps:
            dependents[dependency].add(service)

    ready = [node for node in nodes if not dependencies[node]]
    heapq.heapify(ready)
    order = []
    remaining = {node: set(deps) for node, deps in dependencies.items()}

    while ready:
        node = heapq.heappop(ready)
        order.append(node)
        for dependent in dependents[node]:
            remaining[dependent].discard(node)
            if not remaining[dependent]:
                heapq.heappush(ready, dependent)

    assert len(order) == len(nodes), "Verifier generated a cyclic test graph."
    return {
        service: f"http://localhost:{8000 + index}"
        for index, service in enumerate(order)
    }


def test_interprets_changed_dsl_and_performs_topological_sort():
    with open(DSL, "r") as f:
        original_dsl = f.read()

    alphabet = string.ascii_uppercase
    names = []
    while len(names) < 8:
        candidate = "Service" + "".join(secrets.choice(alphabet) for _ in range(8))
        if candidate not in names:
            names.append(candidate)

    dependencies = {
        names[0]: [],
        names[1]: [],
        names[2]: [names[0]],
        names[3]: [names[0]],
        names[4]: [names[1]],
        names[5]: [names[2], names[4]],
        names[6]: [names[2]],
        names[7]: [names[3], names[5]],
    }

    lines = []
    for service, deps in dependencies.items():
        if deps:
            lines.extend(f"{service} -> {dependency}" for dependency in deps)
        else:
            lines.append(f"{service} -> NONE")
    secrets.SystemRandom().shuffle(lines)
    changed_dsl = "\n".join(lines) + "\n"
    expected = derive_expected(changed_dsl)

    try:
        with open(DSL, "w") as f:
            f.write(changed_dsl)
        run_program()
        with open(CONFIG, "r") as f:
            actual = json.load(f)
        assert actual == expected, "The Go program did not interpret and topologically sort the changed DSL correctly."
    finally:
        with open(DSL, "w") as f:
            f.write(original_dsl)
        run_program()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
