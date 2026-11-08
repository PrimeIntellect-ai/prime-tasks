#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import subprocess

WORKSPACE = "/home/user/ci_workspace"


def run_cargo(args):
    return subprocess.run(
        ["cargo", *args],
        cwd=WORKSPACE,
        capture_output=True,
        text=True,
    )


def test_audit_report_content():
    report_path = "/home/user/vulnerable_crates.txt"
    assert os.path.isfile(report_path), f"Audit report not found at {report_path}"

    with open(report_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected = ["api", "auth", "db", "ui"]
    assert lines == expected, f"Audit report content is incorrect. Expected {expected}, got {lines}"


def test_workspace_integrity_and_dependency_graph():
    assert os.path.isdir(WORKSPACE), f"Workspace directory not found at {WORKSPACE}"

    result = run_cargo(["metadata", "--format-version", "1"])
    assert result.returncode == 0, (
        f"cargo metadata failed:\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
    )
    metadata = json.loads(result.stdout)
    packages_by_id = {package["id"]: package for package in metadata["packages"]}
    workspace_packages = [packages_by_id[package_id] for package_id in metadata["workspace_members"]]

    expected_dependencies = {
        "api": {"auth"},
        "auth": {"dummy-vulnerable-crate"},
        "db": {"dummy-vulnerable-crate"},
        "ui": {"api"},
        "utils": set(),
    }
    actual_names = {package["name"] for package in workspace_packages}
    assert actual_names == set(expected_dependencies), (
        f"Workspace membership was changed. Expected {sorted(expected_dependencies)}, "
        f"got {sorted(actual_names)}"
    )

    for package in workspace_packages:
        name = package["name"]
        expected_manifest = os.path.realpath(
            os.path.join(WORKSPACE, "crates", name, "Cargo.toml")
        )
        assert os.path.realpath(package["manifest_path"]) == expected_manifest, (
            f"Workspace crate {name} is not using its original manifest location"
        )
        actual_dependencies = {dependency["name"] for dependency in package["dependencies"]}
        assert actual_dependencies == expected_dependencies[name], (
            f"Dependencies for {name} were changed. Expected "
            f"{sorted(expected_dependencies[name])}, got {sorted(actual_dependencies)}"
        )


def test_ui_render_fix_is_present_and_executed():
    source_path = os.path.join(WORKSPACE, "crates", "ui", "src", "lib.rs")
    assert os.path.isfile(source_path), f"UI source not found at {source_path}"
    with open(source_path, "r") as source_file:
        source = source_file.read()

    source_without_comments = re.sub(r"/\*.*?\*/", "", source, flags=re.S)
    source_without_comments = re.sub(r"//[^\n]*", "", source_without_comments)
    test_match = re.search(
        r"#\s*\[\s*test\s*\]\s*fn\s+test_ui_render\s*\(\s*\)\s*\{(?P<body>.*?)\}",
        source_without_comments,
        flags=re.S,
    )
    assert test_match, "The test_ui_render unit test was removed or disabled"
    assert re.search(
        r"assert_eq!\s*\(\s*2\s*\+\s*2\s*,\s*4\s*\)\s*;",
        test_match.group("body"),
    ), "test_ui_render does not contain the required corrected assertion"

    listed = run_cargo(["test", "-p", "ui", "--lib", "--", "--list"])
    assert listed.returncode == 0, (
        f"Could not enumerate UI tests:\nSTDOUT:\n{listed.stdout}\nSTDERR:\n{listed.stderr}"
    )
    listed_tests = [line.strip() for line in listed.stdout.splitlines() if line.strip().endswith(": test")]
    assert listed_tests.count("tests::test_ui_render: test") == 1, (
        "The active tests::test_ui_render unit test was not found exactly once"
    )

    executed = run_cargo([
        "test", "-p", "ui", "--lib", "tests::test_ui_render", "--", "--exact"
    ])
    assert executed.returncode == 0, (
        f"test_ui_render failed:\nSTDOUT:\n{executed.stdout}\nSTDERR:\n{executed.stderr}"
    )
    assert re.search(r"test result: ok\. 1 passed;", executed.stdout), (
        f"test_ui_render was not actually executed exactly once:\n{executed.stdout}"
    )


def test_cargo_test_passes():
    workspace_dir = "/home/user/ci_workspace"
    assert os.path.isdir(workspace_dir), f"Workspace directory not found at {workspace_dir}"

    result = subprocess.run(
        ["cargo", "test", "--workspace"],
        cwd=workspace_dir,
        capture_output=True,
        text=True
    )

    assert result.returncode == 0, f"cargo test failed:\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
