#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import re
import string
import subprocess
from pathlib import Path

import pytest

PROJECT = Path("/home/user/release-diff")
CURRENT = Path("/home/user/current_release.json")
TARGET = Path("/home/user/target_release.json")
OUTPUT = Path("/home/user/deployment_plan.json")

ORIGINAL_CURRENT = {
    "services": [
        {"name": "auth-api", "version": "2.1.0"},
        {"name": "payment-gateway", "version": "1.0.5"},
        {"name": "user-db", "version": "3.0.0-beta.2"},
        {"name": "notification-svc", "version": "1.1.0"},
    ]
}
ORIGINAL_TARGET = {
    "services": [
        {"name": "auth-api", "version": "2.2.0"},
        {"name": "payment-gateway", "version": "1.0.5"},
        {"name": "user-db", "version": "3.0.0-beta.1"},
        {"name": "search-indexer", "version": "0.9.0"},
    ]
}

SEMVER_RE = re.compile(
    r"^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)"
    r"(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?"
    r"(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?$"
)


def parse_semver(value):
    match = SEMVER_RE.fullmatch(value)
    assert match, f"Invalid verifier-generated SemVer: {value}"
    prerelease = [] if match.group(4) is None else match.group(4).split(".")
    return (int(match.group(1)), int(match.group(2)), int(match.group(3))), prerelease


def semver_cmp(left, right):
    left_core, left_pre = parse_semver(left)
    right_core, right_pre = parse_semver(right)
    if left_core != right_core:
        return 1 if left_core > right_core else -1
    if not left_pre and not right_pre:
        return 0
    if not left_pre:
        return 1
    if not right_pre:
        return -1
    for a, b in zip(left_pre, right_pre):
        if a == b:
            continue
        a_numeric = a.isdigit()
        b_numeric = b.isdigit()
        if a_numeric and b_numeric:
            return 1 if int(a) > int(b) else -1
        if a_numeric != b_numeric:
            return -1 if a_numeric else 1
        return 1 if a > b else -1
    if len(left_pre) == len(right_pre):
        return 0
    return 1 if len(left_pre) > len(right_pre) else -1


def derive_plan(current, target):
    current_by_name = {service["name"]: service["version"] for service in current["services"]}
    target_by_name = {service["name"]: service["version"] for service in target["services"]}
    actions = []
    for name in sorted(set(current_by_name) | set(target_by_name)):
        old = current_by_name.get(name)
        new = target_by_name.get(name)
        if old is None:
            action = "INSTALL"
        elif new is None:
            action = "REMOVE"
        else:
            comparison = semver_cmp(new, old)
            action = "UPGRADE" if comparison > 0 else "ROLLBACK" if comparison < 0 else "KEEP"
        actions.append({
            "action": action,
            "name": name,
            "from_version": old,
            "to_version": new,
        })
    return {"actions": actions}


def write_inputs(current, target):
    CURRENT.write_text(json.dumps(current), encoding="utf-8")
    TARGET.write_text(json.dumps(target), encoding="utf-8")


def run_program(current, target):
    write_inputs(current, target)
    if OUTPUT.exists():
        OUTPUT.unlink()
    command = [
        "runuser", "-u", "user", "--", "env",
        "HOME=/home/user", "CARGO_NET_OFFLINE=true",
        "cargo", "run", "--offline", "--quiet",
        "--manifest-path", str(PROJECT / "Cargo.toml"),
    ]
    result = subprocess.run(command, cwd=PROJECT, text=True, capture_output=True, timeout=120)
    assert result.returncode == 0, f"Rust program failed to build or run.\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    assert OUTPUT.is_file(), f"Missing file: {OUTPUT}. The Rust program must generate this file."
    try:
        return json.loads(OUTPUT.read_text(encoding="utf-8"))
    except json.JSONDecodeError as error:
        pytest.fail(f"File {OUTPUT} is not valid JSON. Error: {error}")


def assert_original_fixture(data):
    assert "actions" in data, f"The JSON in {OUTPUT} must contain an 'actions' key at the top level."
    actions = data["actions"]
    assert isinstance(actions, list), f"The 'actions' key must be a list, found {type(actions)}."
    assert len(actions) == 5, f"Expected exactly 5 actions, found {len(actions)}."

    expected_actions = [
        {"action": "UPGRADE", "name": "auth-api", "from_version": "2.1.0", "to_version": "2.2.0"},
        {"action": "REMOVE", "name": "notification-svc", "from_version": "1.1.0", "to_version": None},
        {"action": "KEEP", "name": "payment-gateway", "from_version": "1.0.5", "to_version": "1.0.5"},
        {"action": "INSTALL", "name": "search-indexer", "from_version": None, "to_version": "0.9.0"},
        {"action": "ROLLBACK", "name": "user-db", "from_version": "3.0.0-beta.2", "to_version": "3.0.0-beta.1"},
    ]

    actual_names = [action.get("name") for action in actions]
    expected_names = [action["name"] for action in expected_actions]
    assert actual_names == expected_names, f"Actions are not sorted alphabetically by name or missing names. Expected {expected_names}, got {actual_names}."

    for actual, expected in zip(actions, expected_actions):
        name = expected["name"]
        assert actual.get("action") == expected["action"], f"For service '{name}', expected action '{expected['action']}', got '{actual.get('action')}'."
        assert actual.get("from_version") == expected["from_version"], f"For service '{name}', expected from_version '{expected['from_version']}', got '{actual.get('from_version')}'."
        assert actual.get("to_version") == expected["to_version"], f"For service '{name}', expected to_version '{expected['to_version']}', got '{actual.get('to_version')}'."


def test_rust_project_and_general_semver_diff():
    assert PROJECT.is_dir(), f"Missing Cargo project directory: {PROJECT}"
    assert (PROJECT / "Cargo.toml").is_file(), f"Missing Cargo manifest: {PROJECT / 'Cargo.toml'}"
    rust_sources = [path for path in PROJECT.rglob("*.rs") if path.is_file() and "target" not in path.parts]
    assert rust_sources, "The Cargo project must contain Rust source code."

    try:
        original_data = run_program(ORIGINAL_CURRENT, ORIGINAL_TARGET)
        assert_original_fixture(original_data)

        rng = random.SystemRandom()
        token = "".join(rng.choice(string.ascii_lowercase) for _ in range(12))
        n = rng.randint(20, 80)
        current = {
            "services": [
                {"name": f"z-remove-{token}", "version": f"{n}.4.1"},
                {"name": f"core-major-{token}", "version": f"{n}.9.9"},
                {"name": f"numeric-pre-{token}", "version": f"3.0.0-beta.{n}"},
                {"name": f"prefix-pre-{token}", "version": "4.0.0-alpha"},
                {"name": f"release-to-pre-{token}", "version": "5.0.0"},
                {"name": f"lexical-pre-{token}", "version": "6.0.0-zeta"},
                {"name": f"keep-{token}", "version": f"7.{n}.2-rc.1+build9"},
                {"name": f"patch-down-{token}", "version": f"8.2.{n}"},
            ]
        }
        target = {
            "services": [
                {"name": f"a-install-{token}", "version": "0.1.0-alpha.1"},
                {"name": f"core-major-{token}", "version": f"{n + 1}.0.0"},
                {"name": f"numeric-pre-{token}", "version": f"3.0.0-beta.{n + 7}"},
                {"name": f"prefix-pre-{token}", "version": "4.0.0-alpha.1"},
                {"name": f"release-to-pre-{token}", "version": "5.0.0-rc.9"},
                {"name": f"lexical-pre-{token}", "version": "6.0.0-alpha"},
                {"name": f"keep-{token}", "version": f"7.{n}.2-rc.1+build9"},
                {"name": f"patch-down-{token}", "version": f"8.2.{n - 1}"},
            ]
        }
        actual = run_program(current, target)
        expected = derive_plan(current, target)
        assert actual == expected, f"Deployment plan for generated SemVer fixture was incorrect.\nExpected: {expected}\nActual: {actual}"
    finally:
        write_inputs(ORIGINAL_CURRENT, ORIGINAL_TARGET)
        try:
            run_program(ORIGINAL_CURRENT, ORIGINAL_TARGET)
        except Exception:
            pass
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
