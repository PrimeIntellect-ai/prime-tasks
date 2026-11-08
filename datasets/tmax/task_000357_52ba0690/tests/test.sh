#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import hashlib
import itertools
import json
import os
import re
import subprocess
import textwrap

PROJECT = "/home/user/project"
BUILD = os.path.join(PROJECT, "build")
BUILD_SCRIPT = os.path.join(PROJECT, "build.py")


def test_resolution_file():
    """Verify that resolution.txt contains the correct dependency resolution."""
    resolution_path = os.path.join(BUILD, "resolution.txt")
    assert os.path.exists(resolution_path), f"Resolution file missing at {resolution_path}"

    with open(resolution_path, "r") as f:
        content = f.read().strip().splitlines()

    expected_lines = ["core:1.0", "net:2.0", "ui:1.1"]

    for line in expected_lines:
        assert line in content, f"Expected '{line}' in resolution.txt, but it was missing."

    assert len(content) == 3, f"Expected exactly 3 lines in resolution.txt, got {len(content)}."


def test_binaries_exist():
    """Verify that the compiled binaries exist."""
    x86_path = os.path.join(BUILD, "app_x86")
    arm_path = os.path.join(BUILD, "app_arm")

    assert os.path.exists(x86_path), f"Binary missing at {x86_path}"
    assert os.path.exists(arm_path), f"Binary missing at {arm_path}"
    assert os.path.isfile(x86_path), f"{x86_path} is not a file"
    assert os.path.isfile(arm_path), f"{arm_path} is not a file"


def check_manifest():
    manifest_path = os.path.join(BUILD, "manifest.txt")
    x86_path = os.path.join(BUILD, "app_x86")
    arm_path = os.path.join(BUILD, "app_arm")

    assert os.path.exists(manifest_path), f"Manifest file missing at {manifest_path}"

    with open(manifest_path, "r") as f:
        manifest_lines = f.read().strip().splitlines()

    manifest_dict = {}
    for line in manifest_lines:
        if ':' in line:
            k, v = line.split(':', 1)
            manifest_dict[k.strip()] = v.strip()

    assert "app_x86" in manifest_dict, "Manifest missing 'app_x86' entry."
    assert "app_arm" in manifest_dict, "Manifest missing 'app_arm' entry."
    assert "PARITY" in manifest_dict, "Manifest missing 'PARITY' entry."

    with open(x86_path, "rb") as f:
        x86_data = f.read()
    x86_hash = hashlib.sha256(x86_data).hexdigest()
    x86_raw = hashlib.sha256(x86_data).digest()

    with open(arm_path, "rb") as f:
        arm_data = f.read()
    arm_hash = hashlib.sha256(arm_data).hexdigest()
    arm_raw = hashlib.sha256(arm_data).digest()

    parity = 0
    for b in x86_raw + arm_raw:
        parity ^= b
    expected_parity = f"{parity:02x}"

    assert manifest_dict["app_x86"] == x86_hash, f"Expected app_x86 hash {x86_hash}, got {manifest_dict['app_x86']}"
    assert manifest_dict["app_arm"] == arm_hash, f"Expected app_arm hash {arm_hash}, got {manifest_dict['app_arm']}"
    assert manifest_dict["PARITY"].lower() == expected_parity, f"Expected PARITY {expected_parity}, got {manifest_dict['PARITY']}"

    assert len(manifest_lines) == 3, f"Expected exactly 3 manifest lines, got {len(manifest_lines)}"
    assert re.fullmatch(r"app_arm:[0-9a-fA-F]{64}", manifest_lines[0]), "First manifest line must be app_arm and its SHA-256"
    assert re.fullmatch(r"app_x86:[0-9a-fA-F]{64}", manifest_lines[1]), "Second manifest line must be app_x86 and its SHA-256"
    assert re.fullmatch(r"PARITY:[0-9a-fA-F]{2}", manifest_lines[2]), "Third manifest line must be the two-digit parity"


def test_manifest_file():
    """Verify the manifest file contains correct hashes and parity."""
    check_manifest()


def test_build_script_exists_and_uses_subprocess():
    assert os.path.isfile(BUILD_SCRIPT), f"Build script missing at {BUILD_SCRIPT}"
    with open(BUILD_SCRIPT, "r", encoding="utf-8") as f:
        tree = ast.parse(f.read(), filename=BUILD_SCRIPT)

    imports_subprocess = any(
        (isinstance(node, ast.Import) and any(alias.name == "subprocess" for alias in node.names))
        or (isinstance(node, ast.ImportFrom) and node.module == "subprocess")
        for node in ast.walk(tree)
    )
    assert imports_subprocess, "build.py must use the subprocess module for compilation"


def derive_resolution(data):
    names = sorted(data["components"])
    best = None
    best_cost = -1
    for choices in itertools.product(*(data["components"][name] for name in names)):
        selected = {name: choice["version"] for name, choice in zip(names, choices)}
        cost = sum(choice["cost"] for choice in choices)
        if cost >= 90:
            continue
        conflict = any(all(selected.get(component) == version for component, version in rule.items()) for rule in data["conflicts"])
        if not conflict and cost > best_cost:
            best = selected
            best_cost = cost
    assert best is not None
    return [f"{name}:{best[name]}" for name in names]


def run_build():
    result = subprocess.run(
        ["python3", BUILD_SCRIPT],
        cwd=PROJECT,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=60,
    )
    assert result.returncode == 0, f"build.py failed:\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"


def test_build_script_resolves_compiles_and_regenerates_outputs():
    deps_path = os.path.join(PROJECT, "deps.json")
    source_path = os.path.join(PROJECT, "src", "main.c")
    assert os.path.isfile(deps_path), f"Missing {deps_path}"
    assert os.path.isfile(source_path), f"Missing {source_path}"

    with open(deps_path, "rb") as f:
        original_deps = f.read()
    with open(source_path, "rb") as f:
        original_source = f.read()

    probe = "BUILD_SOURCE_PROBE_7d93a1"
    changed_deps = {
        "components": {
            "core": [{"version": "1.0", "cost": 2}, {"version": "2.0", "cost": 41}],
            "net": [{"version": "1.0", "cost": 7}, {"version": "2.0", "cost": 29}],
            "ui": [{"version": "1.0", "cost": 3}, {"version": "1.1", "cost": 17}]
        },
        "conflicts": [{"core": "2.0", "net": "1.0"}]
    }
    changed_source = textwrap.dedent(f'''\
        #include <stdio.h>
        int main() {{
        #ifdef TARGET_ARM
            printf("Architecture: ARM\\n");
        #else
            printf("Architecture: x86\\n");
        #endif
        #ifdef CORE_V2
            printf("Core: v2\\n");
        #else
            printf("Core: v1\\n");
        #endif
            printf("{probe}\\n");
            return 0;
        }}
    ''')

    try:
        with open(deps_path, "w", encoding="utf-8") as f:
            json.dump(changed_deps, f)
        with open(source_path, "w", encoding="utf-8") as f:
            f.write(changed_source)

        for name in ("resolution.txt", "app_x86", "app_arm", "manifest.txt"):
            path = os.path.join(BUILD, name)
            if os.path.lexists(path):
                os.remove(path)

        run_build()

        with open(os.path.join(BUILD, "resolution.txt"), "r", encoding="utf-8") as f:
            actual_resolution = f.read().strip().splitlines()
        assert actual_resolution == derive_resolution(changed_deps), "build.py did not derive the optimal sorted resolution from deps.json"

        x86_path = os.path.join(BUILD, "app_x86")
        arm_path = os.path.join(BUILD, "app_arm")
        for path in (x86_path, arm_path):
            assert os.path.isfile(path), f"Missing generated binary {path}"
            assert os.access(path, os.X_OK), f"Generated binary is not executable: {path}"
            with open(path, "rb") as f:
                assert f.read(4) == b"\\x7fELF", f"Generated artifact is not an ELF binary: {path}"

        x86_output = subprocess.check_output([x86_path], text=True, timeout=10).splitlines()
        arm_output = subprocess.check_output([arm_path], text=True, timeout=10).splitlines()
        assert x86_output == ["Architecture: x86", "Core: v2", probe], f"Incorrect x86 binary output: {x86_output}"
        assert arm_output == ["Architecture: ARM", "Core: v2", probe], f"Incorrect ARM binary output: {arm_output}"
        check_manifest()
    finally:
        with open(deps_path, "wb") as f:
            f.write(original_deps)
        with open(source_path, "wb") as f:
            f.write(original_source)
        run_build()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
