#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import os
import re
import secrets
import shutil
import subprocess
import tempfile
from pathlib import Path

import pytest


def test_build_manifest_exists_and_correct():
    """Check that build_manifest.json exists and contains the expected output."""
    manifest_path = "/home/user/build_manifest.json"
    assert os.path.isfile(manifest_path), f"File {manifest_path} does not exist. Did you run your script?"

    with open(manifest_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{manifest_path} does not contain valid JSON.")

    expected_data = {
        "app.bld": {
            "target": "arm64",
            "emitted_files": ["base_binary", "linux_bindings.so"]
        },
        "tools.bld": {
            "target": "x86_64",
            "emitted_files": ["tool_main", "debug_symbols.pdb"]
        },
        "utils.bld": {
            "target": None,
            "emitted_files": ["wrapper.py"]
        }
    }

    # Preserve the original structure and content assertions.
    for key, expected_val in expected_data.items():
        assert key in data, f"Manifest is missing key: '{key}'"
        actual_val = data[key]

        assert "target" in actual_val, f"Key '{key}' missing 'target' field."
        assert actual_val["target"] == expected_val["target"], \
            f"Expected target {expected_val['target']} for {key}, got {actual_val['target']}."

        assert "emitted_files" in actual_val, f"Key '{key}' missing 'emitted_files' field."
        assert isinstance(actual_val["emitted_files"], list), \
            f"'emitted_files' for {key} should be a list."

        assert sorted(actual_val["emitted_files"]) == sorted(expected_val["emitted_files"]), \
            f"Expected emitted_files {expected_val['emitted_files']} for {key}, got {actual_val['emitted_files']}."


def test_organizer_script_exists():
    """Check that organizer.py exists."""
    script_path = "/home/user/organizer.py"
    assert os.path.isfile(script_path), f"File {script_path} does not exist."


def test_unittest_script_exists_and_passes():
    """Check that test_organizer.py contains and runs a relevant unittest."""
    test_script_path = "/home/user/test_organizer.py"
    assert os.path.isfile(test_script_path), f"File {test_script_path} does not exist."

    result = subprocess.run(
        ["python3", "-m", "unittest", test_script_path],
        capture_output=True,
        text=True,
        timeout=30
    )

    assert result.returncode == 0, \
        f"Unittests failed. Return code: {result.returncode}\nStdout: {result.stdout}\nStderr: {result.stderr}"
    combined = result.stdout + result.stderr
    assert "OK" in combined, "Unittest output did not indicate success ('OK')."
    match = re.search(r"Ran\s+(\d+)\s+tests?", combined)
    assert match and int(match.group(1)) >= 1, "test_organizer.py did not run any unittest test cases."

    source = Path(test_script_path).read_text(encoding="utf-8")
    try:
        tree = ast.parse(source)
    except SyntaxError as exc:
        pytest.fail(f"test_organizer.py is not valid Python: {exc}")

    # The required test must exercise a mock DSL containing a conditional and
    # make an assertion about organizer behavior, rather than being unrelated.
    assert "organizer" in source, "The unittest does not reference the organizer implementation."
    assert "IF " in source and "ENDIF" in source and "EMIT " in source, \
        "The unittest does not include a mock DSL script with an IF block."
    has_assertion = any(
        isinstance(node, ast.Assert) or
        (isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute)
         and node.func.attr.startswith("assert"))
        for node in ast.walk(tree)
    )
    assert has_assertion, "The unittest does not contain an assertion."


def test_organizer_executes_dynamic_dsl_inputs():
    """Execute the submitted artifact against unpredictable DSL programs."""
    organizer = Path("/home/user/organizer.py")
    builds = Path("/home/user/legacy_builds")
    manifest = Path("/home/user/build_manifest.json")

    token = secrets.token_hex(10)
    true_value = "enabled_" + token
    false_value = "disabled_" + token
    arch = "arch_" + token
    first_name = "dynamic_" + token + ".bld"
    second_name = "untargeted_" + token + ".bld"
    ignored_name = "ignored_" + token + ".txt"

    base_emit = "base_" + token
    true_emit = "true_" + token
    false_emit = "false_" + token
    undefined_emit = "undefined_" + token
    plain_emit = "plain_" + token

    expected = {
        first_name: {
            "target": arch,
            "emitted_files": [base_emit, true_emit],
        },
        second_name: {
            "target": None,
            "emitted_files": [plain_emit],
        },
    }

    backup_root = Path(tempfile.mkdtemp(prefix="organizer_verifier_"))
    backup_builds = backup_root / "legacy_builds"
    manifest_existed = manifest.exists()
    manifest_bytes = manifest.read_bytes() if manifest_existed else None

    try:
        shutil.copytree(builds, backup_builds)
        shutil.rmtree(builds)
        builds.mkdir(parents=True)

        (builds / first_name).write_text(
            f"TARGET {arch}\n"
            f"DEFINE MODE {true_value}\n"
            f"EMIT {base_emit}\n"
            f"IF MODE == {true_value}\n"
            f"  EMIT {true_emit}\n"
            f"ENDIF\n"
            f"IF MODE == {false_value}\n"
            f"  EMIT {false_emit}\n"
            f"ENDIF\n",
            encoding="utf-8",
        )
        (builds / second_name).write_text(
            f"EMIT {plain_emit}\n"
            f"IF MISSING == {true_value}\n"
            f"  EMIT {undefined_emit}\n"
            f"ENDIF\n",
            encoding="utf-8",
        )
        (builds / ignored_name).write_text(
            f"TARGET should_not_appear\nEMIT {false_emit}\n",
            encoding="utf-8",
        )

        if manifest.exists():
            manifest.unlink()

        result = subprocess.run(
            ["python3", str(organizer)],
            cwd="/home/user",
            capture_output=True,
            text=True,
            timeout=30,
        )
        assert result.returncode == 0, \
            f"organizer.py failed on dynamic inputs.\nStdout: {result.stdout}\nStderr: {result.stderr}"
        assert manifest.is_file(), "Executing organizer.py did not create build_manifest.json."

        try:
            actual = json.loads(manifest.read_text(encoding="utf-8"))
        except json.JSONDecodeError as exc:
            pytest.fail(f"Dynamic manifest is not valid JSON: {exc}")

        assert actual == expected, \
            f"Organizer did not correctly parse/evaluate dynamic DSL scripts. Expected {expected}, got {actual}."
    finally:
        if builds.exists():
            shutil.rmtree(builds)
        shutil.copytree(backup_builds, builds)
        if manifest_existed:
            manifest.write_bytes(manifest_bytes)
        elif manifest.exists():
            manifest.unlink()
        shutil.rmtree(backup_root, ignore_errors=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
