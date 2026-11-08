#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import heapq
import json
import os
import re
import secrets
import subprocess
from pathlib import Path

HOME = Path("/home/user")
CONFIG = HOME / "ci_config.json"
BUILDER = HOME / "builder.py"
LOG = HOME / "build_order.log"
MAKEFILE = HOME / "Makefile"

EXPECTED_CONFIG = {
    "services": {
        "database": {"version": "3.0.1", "depends_on": []},
        "auth": {
            "version": "1.2.0",
            "depends_on": [{"name": "database", "requires": ">=3.0.0"}],
        },
        "api": {
            "version": "2.2.1",
            "depends_on": [
                {"name": "auth", "requires": ">=1.2.0"},
                {"name": "database", "requires": ">=3.0.0"},
            ],
        },
        "frontend": {
            "version": "1.0.5",
            "depends_on": [{"name": "api", "requires": ">=2.2.0"}],
        },
        "analytics": {
            "version": "1.0.0",
            "depends_on": [{"name": "database", "requires": ">=3.1.0"}],
        },
        "cache": {"version": "2.0.0", "depends_on": []},
    }
}


def run_builder():
    result = subprocess.run(
        ["python3", "-S", str(BUILDER)],
        cwd=str(HOME),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )
    assert result.returncode == 0, (
        f"builder.py failed with exit code {result.returncode}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def reference_order(config):
    services = config["services"]

    def version(value):
        parts = value.split(".")
        assert len(parts) == 3 and all(p.isdigit() for p in parts)
        return tuple(int(p) for p in parts)

    valid = set(services)
    changed = True
    while changed:
        changed = False
        for name in list(valid):
            for dep in services[name]["depends_on"]:
                dep_name = dep["name"]
                required = dep["requires"]
                assert required.startswith(">=")
                if (
                    dep_name not in valid
                    or dep_name not in services
                    or version(services[dep_name]["version"]) < version(required[2:])
                ):
                    valid.remove(name)
                    changed = True
                    break

    indegree = {name: 0 for name in valid}
    outgoing = {name: [] for name in valid}
    for name in valid:
        for dep in services[name]["depends_on"]:
            dep_name = dep["name"]
            if dep_name in valid:
                indegree[name] += 1
                outgoing[dep_name].append(name)

    ready = [name for name, degree in indegree.items() if degree == 0]
    heapq.heapify(ready)
    order = []
    while ready:
        name = heapq.heappop(ready)
        order.append(name)
        for child in outgoing[name]:
            indegree[child] -= 1
            if indegree[child] == 0:
                heapq.heappush(ready, child)
    assert len(order) == len(valid), "Generated test configuration must be a DAG"
    return order


def assert_outputs(config, expected_order):
    assert LOG.is_file(), f"Missing build order log: {LOG}"
    with LOG.open() as f:
        lines = [line.strip() for line in f if line.strip()]
    assert lines == expected_order, f"Expected build order {expected_order}, got {lines}"

    assert MAKEFILE.is_file(), f"Missing Makefile: {MAKEFILE}"
    content = MAKEFILE.read_text()
    make_lines = content.splitlines()
    nonempty = [(i, line.rstrip()) for i, line in enumerate(make_lines) if line.strip()]
    assert nonempty, "Makefile is empty"

    expected_all = "all:" + (" " + " ".join(expected_order) if expected_order else "")
    assert nonempty[0][1] == expected_all, (
        f"The first target must be exactly {expected_all!r}, got {nonempty[0][1]!r}"
    )

    target_pattern = re.compile(r"^([^\s:#][^:]*)\s*:(.*)$")
    targets = []
    for _, line in nonempty:
        if line.startswith((" ", "\t")) or line.lstrip().startswith("#"):
            continue
        match = target_pattern.match(line)
        if match:
            names = match.group(1).split()
            targets.extend(names)

    assert set(targets) == {"all", *expected_order}, (
        f"Makefile targets must be exactly all and the valid services; got {targets}"
    )
    assert len(targets) == len(set(targets)), f"Duplicate Makefile targets found: {targets}"

    for service in expected_order:
        target_line = f"{service}:"
        assert target_line in make_lines, f"Makefile is missing exact target {target_line!r}"
        index = make_lines.index(target_line)
        assert index + 1 < len(make_lines), f"Target {service!r} has no command"
        expected_command = f'\t@echo "Building {service} v{config["services"][service]["version"]}"'
        assert make_lines[index + 1].rstrip() == expected_command, (
            f"Incorrect command for {service!r}: expected {expected_command!r}, "
            f"got {make_lines[index + 1].rstrip()!r}"
        )


def test_01_config_patched_and_builder_present():
    assert CONFIG.is_file(), f"Missing configuration file: {CONFIG}"
    try:
        data = json.loads(CONFIG.read_text())
    except json.JSONDecodeError as exc:
        raise AssertionError(f"File {CONFIG} is not valid JSON: {exc}")
    assert data == EXPECTED_CONFIG, "ci_config.json was not exactly the correctly patched base configuration"

    assert BUILDER.is_file(), f"Missing build orchestrator: {BUILDER}"
    assert not BUILDER.is_symlink(), "builder.py must be an actual submitted script, not a symlink"
    source = BUILDER.read_text()
    assert source.strip(), "builder.py is empty"
    compile(source, str(BUILDER), "exec")


def test_02_builder_handles_generated_graph_semantics():
    used = set()

    def name():
        while True:
            candidate = "svc" + secrets.token_hex(4)
            if candidate not in used:
                used.add(candidate)
                return candidate

    root_numeric, root_equal, middle, join, leaf = [name() for _ in range(5)]
    bad_version, bad_descendant = name(), name()
    missing, missing_descendant, absent = name(), name(), name()

    generated = {
        "services": {
            root_numeric: {"version": "2.10.3", "depends_on": []},
            root_equal: {"version": "7.4.2", "depends_on": []},
            middle: {
                "version": "1.0.0",
                "depends_on": [{"name": root_numeric, "requires": ">=2.9.99"}],
            },
            join: {
                "version": "3.1.4",
                "depends_on": [
                    {"name": root_equal, "requires": ">=7.4.2"},
                    {"name": root_numeric, "requires": ">=2.10.3"},
                ],
            },
            leaf: {
                "version": "5.0.1",
                "depends_on": [
                    {"name": middle, "requires": ">=1.0.0"},
                    {"name": join, "requires": ">=3.1.0"},
                ],
            },
            bad_version: {
                "version": "8.0.0",
                "depends_on": [{"name": root_equal, "requires": ">=7.4.3"}],
            },
            bad_descendant: {
                "version": "1.2.3",
                "depends_on": [{"name": bad_version, "requires": ">=8.0.0"}],
            },
            missing: {
                "version": "4.0.0",
                "depends_on": [{"name": absent, "requires": ">=1.0.0"}],
            },
            missing_descendant: {
                "version": "4.1.0",
                "depends_on": [{"name": missing, "requires": ">=4.0.0"}],
            },
        }
    }

    expected = reference_order(generated)
    try:
        CONFIG.write_text(json.dumps(generated, indent=2) + "\n")
        run_builder()
        assert_outputs(generated, expected)
    finally:
        CONFIG.write_text(json.dumps(EXPECTED_CONFIG, indent=2) + "\n")
        subprocess.run(
            ["python3", "-S", str(BUILDER)],
            cwd=str(HOME),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=10,
        )


def test_03_final_artifacts_from_real_config():
    assert BUILDER.is_file(), f"Missing build orchestrator: {BUILDER}"
    run_builder()

    data = json.loads(CONFIG.read_text())
    assert data == EXPECTED_CONFIG
    assert "services" in data
    assert "api" in data["services"]
    api_version = data["services"]["api"]["version"]
    assert api_version == "2.2.1", f"Expected api version 2.2.1, got {api_version}"

    expected_order = ["cache", "database", "auth", "api", "frontend"]
    assert_outputs(data, expected_order)

    lines = [line.rstrip() for line in MAKEFILE.read_text().splitlines()]
    expected_all_target = "all: cache database auth api frontend"
    assert any(line.startswith(expected_all_target) for line in lines), (
        f"Makefile is missing the correct all target: {expected_all_target}"
    )
    expected_services = {
        "cache": "2.0.0",
        "database": "3.0.1",
        "auth": "1.2.0",
        "api": "2.2.1",
        "frontend": "1.0.5",
    }
    for service, version in expected_services.items():
        target_line = f"{service}:"
        assert target_line in lines, f"Makefile is missing target {target_line!r}"
        index = lines.index(target_line)
        assert index + 1 < len(lines), f"Makefile target {target_line!r} has no command"
        assert lines[index + 1] == f'\t@echo "Building {service} v{version}"'
    assert "analytics:" not in lines, "analytics must be excluded because its dependency is unmet"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
