#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import re
import secrets
import subprocess

import pytest

FILTER_SCRIPT = "/home/user/filter.py"
PROJECT_DIR = "/home/user/rust_server"


def test_rust_project_compiles():
    """Check if the Rust project compiles successfully."""
    assert os.path.isdir(PROJECT_DIR), f"Rust project directory missing at {PROJECT_DIR}"

    result = subprocess.run(
        ["cargo", "build"],
        cwd=PROJECT_DIR,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE
    )
    assert result.returncode == 0, f"Rust project failed to compile:\n{result.stderr.decode('utf-8')}"


def test_rust_grpcio_dependency_is_exact_version():
    """Ensure grpcio remains a direct crates.io dependency resolving to 0.13.0."""
    result = subprocess.run(
        ["cargo", "metadata", "--format-version", "1"],
        cwd=PROJECT_DIR,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE
    )
    assert result.returncode == 0, result.stderr.decode("utf-8", errors="replace")
    metadata = json.loads(result.stdout)

    manifest = os.path.realpath(os.path.join(PROJECT_DIR, "Cargo.toml"))
    roots = [
        package for package in metadata["packages"]
        if os.path.realpath(package["manifest_path"]) == manifest
    ]
    assert len(roots) == 1, "Could not identify the rust_server package"
    root = roots[0]

    grpc_deps = [dep for dep in root.get("dependencies", []) if dep.get("name") == "grpcio"]
    assert len(grpc_deps) == 1, "grpcio must remain a direct dependency"
    dep = grpc_deps[0]
    assert dep.get("req") in ("^0.13.0", "=0.13.0"), \
        f"grpcio dependency must be set to 0.13.0, found requirement {dep.get('req')!r}"
    assert str(dep.get("source", "")).startswith("registry+"), \
        "grpcio must be the registry dependency, not a local replacement"

    packages_by_id = {package["id"]: package for package in metadata["packages"]}
    root_node = next(
        (node for node in metadata["resolve"]["nodes"] if node["id"] == root["id"]),
        None
    )
    assert root_node is not None, "rust_server is absent from Cargo's resolved dependency graph"
    resolved_ids = [entry["pkg"] for entry in root_node.get("deps", []) if entry["name"] == "grpcio"]
    assert len(resolved_ids) == 1, "grpcio was not resolved as a direct dependency"
    resolved = packages_by_id[resolved_ids[0]]
    assert resolved["name"] == "grpcio" and resolved["version"] == "0.13.0", \
        f"grpcio resolved to {resolved['name']} {resolved['version']}, not grpcio 0.13.0"
    assert str(resolved.get("source", "")).startswith("registry+"), \
        "Resolved grpcio package must come from the registry"


def test_python_filter_corpus():
    """Check the Python filter against the adversarial corpus."""
    assert os.path.isfile(FILTER_SCRIPT), f"Filter script missing at {FILTER_SCRIPT}"

    evil_dir = "/app/corpus/evil"
    clean_dir = "/app/corpus/clean"

    assert os.path.isdir(evil_dir), f"Evil corpus directory missing at {evil_dir}"
    assert os.path.isdir(clean_dir), f"Clean corpus directory missing at {clean_dir}"

    evil_files = sorted([f for f in os.listdir(evil_dir) if f.endswith(".json")])
    clean_files = sorted([f for f in os.listdir(clean_dir) if f.endswith(".json")])

    evil_bypassed = []
    clean_modified = []

    for f in evil_files:
        path = os.path.join(evil_dir, f)
        with open(path, "r") as file:
            content = file.read()

        result = subprocess.run(
            ["python3", FILTER_SCRIPT, content],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE
        )
        if result.returncode == 0:
            evil_bypassed.append(f)

    for f in clean_files:
        path = os.path.join(clean_dir, f)
        with open(path, "r") as file:
            content = file.read()

        result = subprocess.run(
            ["python3", FILTER_SCRIPT, content],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE
        )
        if result.returncode != 0:
            clean_modified.append(f)

    error_messages = []
    if evil_bypassed:
        error_messages.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_modified:
        error_messages.append(f"{len(clean_modified)} of {len(clean_files)} clean modified: {', '.join(clean_modified)}")

    assert not error_messages, " | ".join(error_messages)


SEMVER_RE = re.compile(
    r"^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)"
    r"(?:-((?:0|[1-9][0-9]*|[0-9A-Za-z-]*[A-Za-z-][0-9A-Za-z-]*)"
    r"(?:\.(?:0|[1-9][0-9]*|[0-9A-Za-z-]*[A-Za-z-][0-9A-Za-z-]*))*))?"
    r"(?:\+([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?$"
)


def semver_is_accepted(version):
    match = SEMVER_RE.fullmatch(version)
    assert match is not None
    core = tuple(int(match.group(i)) for i in (1, 2, 3))
    if core != (1, 4, 0):
        return core > (1, 4, 0)
    return match.group(4) is None


def run_filter(payload):
    return subprocess.run(
        ["python3", FILTER_SCRIPT, payload],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=5
    ).returncode


def random_valid_semver(rng):
    major = rng.randrange(0, 8)
    minor = rng.randrange(0, 20)
    patch = rng.randrange(0, 30)
    version = f"{major}.{minor}.{patch}"

    if rng.randrange(3) == 0:
        identifiers = []
        for _ in range(rng.randrange(1, 4)):
            if rng.randrange(2):
                identifiers.append(str(rng.randrange(0, 10000)))
            else:
                identifiers.append("r" + secrets.token_hex(rng.randrange(1, 5)))
        version += "-" + ".".join(identifiers)

    if rng.randrange(3) == 0:
        version += "+b" + secrets.token_hex(rng.randrange(1, 6))
    return version


def test_python_filter_generated_semver_cases():
    """Exercise unpredictable valid versions and derive each expected result."""
    assert os.path.isfile(FILTER_SCRIPT), f"Filter script missing at {FILTER_SCRIPT}"
    rng = random.Random(int.from_bytes(os.urandom(16), "big"))

    versions = [
        "1.4.0",
        "1.4.0-0",
        "1.4.0-rc.1",
        "1.4.0+" + secrets.token_hex(8),
        "1.4.1-0",
        "2.0.0-alpha",
    ]
    versions.extend(random_valid_semver(rng) for _ in range(80))

    for version in versions:
        payload = json.dumps({
            "client_version": version,
            "nonce": secrets.token_hex(16),
            "data": {"random": rng.randrange(1 << 30)}
        })
        expected = 0 if semver_is_accepted(version) else 1
        actual = run_filter(payload)
        assert actual == expected, \
            f"client_version {version!r}: expected exit {expected}, got {actual}"


def test_python_filter_rejects_generated_malformed_payloads():
    """Malformed JSON, fields, and non-SemVer strings must exit exactly 1."""
    token = secrets.token_hex(10)
    malformed_payloads = [
        "{not-json-" + token,
        json.dumps({"other": token}),
        json.dumps({"client_version": None}),
        json.dumps({"client_version": 1.5}),
        json.dumps({"client_version": ["1.5.0"]}),
        json.dumps({"client_version": ""}),
        json.dumps({"client_version": "01.4.0"}),
        json.dumps({"client_version": "1.04.0"}),
        json.dumps({"client_version": "1.4.00"}),
        json.dumps({"client_version": "1.4"}),
        json.dumps({"client_version": "1.4.0.0"}),
        json.dumps({"client_version": "v1.4.0"}),
        json.dumps({"client_version": " 1.4.0"}),
        json.dumps({"client_version": "1.4.0 "}),
        json.dumps({"client_version": "1.4.0-"}),
        json.dumps({"client_version": "1.4.0+"}),
        json.dumps({"client_version": "1.4.0-01"}),
        json.dumps({"client_version": "1.4.0-alpha..1"}),
        json.dumps({"client_version": "1.4.0-alpha_" + token}),
    ]

    for payload in malformed_payloads:
        actual = run_filter(payload)
        assert actual == 1, f"Malformed payload should exit 1, got {actual}: {payload!r}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
