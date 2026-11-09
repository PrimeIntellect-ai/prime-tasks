#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import shutil
import stat
import subprocess
import tempfile

import pytest

SOURCE = "/home/user/audit.go"
HOME = "/home/user"

CANONICAL = {
    "nodes": [
        {"id": "app-api", "type": "app", "name": "app-api", "version": "1.0.0"},
        {"id": "app-worker", "type": "app", "name": "app-worker", "version": "1.0.0"},
        {"id": "app-legacy", "type": "app", "name": "app-legacy", "version": "1.0.0"},
        {"id": "app-admin", "type": "app", "name": "app-admin", "version": "2.0.0"},
        {"id": "lib-net", "type": "lib", "name": "lib-net", "version": "1.1.0"},
        {"id": "lib-auth", "type": "lib", "name": "lib-auth", "version": "1.2.0"},
        {"id": "lib-data", "type": "lib", "name": "lib-data", "version": "3.0.0"},
        {"id": "lib-utils", "type": "lib", "name": "lib-utils", "version": "1.5.0"},
        {"id": "lib-crypto", "type": "lib", "name": "lib-crypto", "version": "2.1.5"},
        {"id": "lib-db", "type": "lib", "name": "lib-db", "version": "1.0.5"},
        {"id": "lib-old", "type": "lib", "name": "lib-old", "version": "0.9.5"}
    ],
    "edges": [
        {"from": "app-api", "to": "lib-net"},
        {"from": "app-api", "to": "lib-auth"},
        {"from": "app-worker", "to": "lib-data"},
        {"from": "app-legacy", "to": "lib-old"},
        {"from": "app-admin", "to": "lib-utils"},
        {"from": "lib-net", "to": "lib-crypto"},
        {"from": "lib-auth", "to": "lib-crypto"},
        {"from": "lib-data", "to": "lib-db"}
    ]
}

FIXTURES = [
    (CANONICAL,
     ["lib-crypto < 2.2.0", "lib-old < 1.0.0", "lib-utils < 1.6.0", "lib-db < 1.0.0"],
     ["app-legacy", "app-worker"]),
    ({
        "nodes": [
            {"id": "alpha-app", "type": "app", "name": "alpha", "version": "1.0.0"},
            {"id": "baseline-app", "type": "app", "name": "base", "version": "1.0.0"},
            {"id": "zeta-app", "type": "app", "name": "zeta", "version": "1.0.0"},
            {"id": "middle", "type": "lib", "name": "middle", "version": "4.0.0"},
            {"id": "bad", "type": "lib", "name": "bad-lib", "version": "1.2.3"},
            {"id": "numeric-safe", "type": "lib", "name": "number-lib", "version": "1.10.0"}
        ],
        "edges": [
            {"from": "alpha-app", "to": "middle"},
            {"from": "middle", "to": "bad"},
            {"from": "middle", "to": "alpha-app"},
            {"from": "baseline-app", "to": "bad"},
            {"from": "zeta-app", "to": "numeric-safe"}
        ]
     }, ["bad-lib < 1.2.4", "number-lib < 1.9.0"], ["baseline-app"]),
    ({
        "nodes": [
            {"id": "app-c", "type": "app", "name": "c", "version": "3.0.0"},
            {"id": "app-a", "type": "app", "name": "a", "version": "3.0.0"},
            {"id": "app-b", "type": "app", "name": "b", "version": "3.0.0"},
            {"id": "bridge", "type": "lib", "name": "bridge", "version": "9.9.9"},
            {"id": "pkg-old", "type": "lib", "name": "shared", "version": "0.9.9"},
            {"id": "pkg-new", "type": "lib", "name": "shared", "version": "2.0.0"}
        ],
        "edges": [
            {"from": "app-c", "to": "pkg-old"},
            {"from": "app-a", "to": "bridge"},
            {"from": "bridge", "to": "pkg-old"},
            {"from": "app-b", "to": "pkg-new"}
        ]
     }, ["shared < 1.0.0"], [])
]


def parse_version(value):
    return tuple(int(part) for part in value.split("."))


def expected_for(deps, rules, baseline):
    nodes = {node["id"]: node for node in deps.get("nodes", [])}
    graph = {node_id: [] for node_id in nodes}
    for edge in deps.get("edges", []):
        if edge["from"] in graph:
            graph[edge["from"]].append(edge["to"])

    vulnerable = set()
    for rule in rules:
        parts = rule.split("<")
        if len(parts) != 2:
            continue
        name = parts[0].strip()
        limit = parse_version(parts[1].strip())
        for node_id, node in nodes.items():
            if node["name"] == name and parse_version(node["version"]) < limit:
                vulnerable.add(node_id)

    def affected(node_id, visited):
        if node_id in vulnerable:
            return True
        if node_id in visited:
            return False
        visited.add(node_id)
        return any(affected(dep, visited) for dep in graph.get(node_id, []))

    found = {
        node_id for node_id, node in nodes.items()
        if node["type"] == "app" and affected(node_id, set())
    }
    return sorted(found - set(baseline))


def find_compiled_candidates():
    candidates = []
    for root, dirs, files in os.walk(HOME):
        dirs[:] = [d for d in dirs if d not in {".cache", "go"}]
        for name in files:
            path = os.path.join(root, name)
            try:
                mode = os.stat(path).st_mode
                if not stat.S_ISREG(mode) or not (mode & 0o111):
                    continue
                with open(path, "rb") as f:
                    if f.read(4) == b"\x7fELF":
                        candidates.append(path)
            except OSError:
                pass
    return candidates


def run_in_scratch(binary, deps, rules, baseline):
    expected = expected_for(deps, rules, baseline)
    with tempfile.TemporaryDirectory(prefix="audit-root-") as root:
        user_dir = os.path.join(root, "home", "user")
        os.makedirs(user_dir)
        target = os.path.join(root, "audit")
        shutil.copy2(binary, target)
        os.chmod(target, 0o755)

        with open(os.path.join(user_dir, "deps.json"), "w") as f:
            json.dump(deps, f)
        with open(os.path.join(user_dir, "rules.txt"), "w") as f:
            f.write("\n".join(rules) + "\n")
        with open(os.path.join(user_dir, "baseline.txt"), "w") as f:
            f.write("\n".join(baseline) + ("\n" if baseline else ""))

        result = subprocess.run(
            ["chroot", root, "/audit"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=10,
            env={"PATH": ""},
        )
        assert result.returncode == 0, (
            f"compiled program failed in a scratch-like environment: {result.stderr}"
        )
        output = os.path.join(user_dir, "new_vuln_apps.txt")
        assert os.path.isfile(output), "compiled program did not create new_vuln_apps.txt"
        with open(output) as f:
            actual = [line.strip() for line in f if line.strip()]
        assert actual == expected, f"Expected {expected}, got {actual}"
        return output, actual


def test_audit_go_exists():
    assert os.path.isfile(SOURCE), "/home/user/audit.go does not exist. You must write your Go code here."


def test_compiled_standalone_implementation_and_output():
    candidates = find_compiled_candidates()
    assert candidates, "No compiled executable produced from the Go program was found under /home/user."

    build_dir = tempfile.mkdtemp(prefix="audit-build-")
    built = os.path.join(build_dir, "audit")
    cache = os.path.join(build_dir, "cache")
    os.makedirs(cache)
    env = os.environ.copy()
    env.update({"CGO_ENABLED": "0", "GO111MODULE": "off", "GOCACHE": cache})
    result = subprocess.run(
        ["go", "build", "-o", built, SOURCE],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=60,
        env=env,
    )
    assert result.returncode == 0, f"audit.go does not compile: {result.stderr}"

    # Execute a fresh build of the submitted source against independently supplied fixtures.
    canonical_actual = None
    for index, fixture in enumerate(FIXTURES):
        _, actual = run_in_scratch(built, *fixture)
        if index == 0:
            canonical_actual = actual

    # Also require an agent-produced compiled artifact to work as a standalone binary.
    candidate_errors = []
    working_candidate = False
    for candidate in candidates:
        try:
            for fixture in FIXTURES:
                run_in_scratch(candidate, *fixture)
            working_candidate = True
            break
        except Exception as exc:
            candidate_errors.append(f"{candidate}: {exc}")
    assert working_candidate, "No submitted compiled binary passed the tests. " + " | ".join(candidate_errors)

    # Restore the original fixture and preserve the original output-file correctness assertion.
    with open(os.path.join(HOME, "deps.json"), "w") as f:
        json.dump(CANONICAL, f)
    with open(os.path.join(HOME, "rules.txt"), "w") as f:
        f.write("lib-crypto < 2.2.0\nlib-old < 1.0.0\nlib-utils < 1.6.0\nlib-db < 1.0.0\n")
    with open(os.path.join(HOME, "baseline.txt"), "w") as f:
        f.write("app-legacy\napp-worker\n")
    output_path = os.path.join(HOME, "new_vuln_apps.txt")
    with open(output_path, "w") as f:
        for app_id in canonical_actual:
            f.write(app_id + "\n")

    assert os.path.isfile(output_path), f"The output file {output_path} was not created."
    with open(output_path) as f:
        actual_output = [line.strip() for line in f if line.strip()]
    expected_output = expected_for(CANONICAL, FIXTURES[0][1], FIXTURES[0][2])
    assert actual_output == expected_output, (
        f"The contents of {output_path} do not match the expected newly vulnerable applications. "
        f"Expected: {expected_output}; Actual: {actual_output}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
