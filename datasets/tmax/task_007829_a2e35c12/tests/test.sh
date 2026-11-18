#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import subprocess
import tempfile


def apply_patch(original_content, patch_path):
    with tempfile.TemporaryDirectory() as temp_dir:
        cargo_path = os.path.join(temp_dir, "Cargo.toml")
        with open(cargo_path, "w") as f:
            f.write(original_content)

        try:
            subprocess.run(
                ["patch", "Cargo.toml", patch_path],
                cwd=temp_dir,
                capture_output=True,
                text=True,
                check=True,
            )
        except subprocess.CalledProcessError as e:
            assert False, (
                "Failed to apply patch to Cargo.toml. "
                f"Error: {e.stderr}\nOutput: {e.stdout}"
            )

        with open(cargo_path) as f:
            return f.read()


def test_cargo_patch_exists_and_applies_correctly():
    patch_path = "/home/user/cargo.patch"
    assert os.path.isfile(patch_path), f"Patch file not found: {patch_path}"

    original_cargo_toml = """[package]
name = "legacy_rust_app"
version = "0.1.0"
edition = "2021"

[dependencies]
serde = "1.0.0"
tokio = "1.8.0"
reqwest = "0.11.0"
"""

    expected_cargo_toml = """[package]
name = "legacy_rust_app"
version = "0.1.0"
edition = "2021"

[dependencies]
serde = "1.1.0"
tokio = "1.14.2"
reqwest = "0.11.0"
"""

    patched_content = apply_patch(original_cargo_toml, patch_path)
    assert patched_content == expected_cargo_toml, (
        "The patched Cargo.toml does not match the expected content.\n"
        f"Expected:\n{expected_cargo_toml}\n"
        f"Got:\n{patched_content}"
    )


def test_fix_deps_script_exists():
    script_path = "/home/user/fix_deps.py"
    assert os.path.isfile(script_path), f"Python script not found: {script_path}"


def parse_version(version):
    return tuple(int(part) for part in version.split("."))


def select_version(versions, operator, constraint):
    target = parse_version(constraint)
    candidates = []
    for version in versions:
        parsed = parse_version(version)
        if parsed[0] != target[0]:
            continue
        if operator == ">" and parsed > target:
            candidates.append((parsed, version))
        elif operator == ">=" and parsed >= target:
            candidates.append((parsed, version))
    assert candidates, "Verifier generated a constraint without a solution"
    return max(candidates)[1]


def test_script_executes_and_generates_patch_from_runtime_inputs():
    script_path = "/home/user/fix_deps.py"
    paths = [
        "/home/user/Cargo.toml",
        "/home/user/build_errors.log",
        "/home/user/registry.json",
        "/home/user/cargo.patch",
    ]
    backups = {}
    for path in paths:
        with open(path, "rb") as f:
            backups[path] = f.read()

    suffix = secrets.token_hex(6)
    package_gt = f"alpha_{suffix}"
    package_gte = f"beta_{suffix}"
    decoy = f"decoy_{suffix}"
    untouched = f"stable_{suffix}"
    major_gt = 3 + secrets.randbelow(20)
    major_gte = major_gt + 2

    target_gt = f"{major_gt}.2.9"
    target_gte = f"{major_gte}.10.0"
    registry = {
        package_gt: [
            f"{major_gt}.2.9",
            f"{major_gt}.2.10",
            f"{major_gt}.9.20",
            f"{major_gt}.10.0",
            f"{major_gt + 1}.99.0",
        ],
        package_gte: [
            f"{major_gte}.9.99",
            f"{major_gte}.10.0",
            f"{major_gte}.10.7",
            f"{major_gte}.11.0",
            f"{major_gte + 1}.0.0",
        ],
        decoy: [f"{major_gt}.0.0", f"{major_gt}.99.0"],
        untouched: ["0.4.0", "0.9.0"],
    }

    selected_gt = select_version(registry[package_gt], ">", target_gt)
    selected_gte = select_version(registry[package_gte], ">=", target_gte)

    original = f'''[package]
name = "runtime_{suffix}"
version = "0.1.0"
edition = "2021"

[dependencies]
{package_gt} = "{major_gt}.0.1"
{package_gte} = "{major_gte}.1.0"
{decoy} = "{major_gt}.0.0"
{untouched} = "0.4.0"
'''
    expected = f'''[package]
name = "runtime_{suffix}"
version = "0.1.0"
edition = "2021"

[dependencies]
{package_gt} = "{selected_gt}"
{package_gte} = "{selected_gte}"
{decoy} = "{major_gt}.0.0"
{untouched} = "0.4.0"
'''
    log = f'''irrelevant prefix
Package: {decoy}
Constraint: >={major_gt}.0.0

-- BEGIN CONFLICT --
Package: {package_gt}
Constraint: >{target_gt}
-- END CONFLICT --

unrelated text between conflict blocks

-- BEGIN CONFLICT --
Package: {package_gte}
Constraint: >={target_gte}
-- END CONFLICT --

irrelevant suffix
'''

    try:
        with open("/home/user/Cargo.toml", "w") as f:
            f.write(original)
        with open("/home/user/build_errors.log", "w") as f:
            f.write(log)
        with open("/home/user/registry.json", "w") as f:
            json.dump(registry, f)
        os.unlink("/home/user/cargo.patch")

        result = subprocess.run(
            ["python3", script_path],
            cwd="/home/user",
            capture_output=True,
            text=True,
            timeout=15,
        )
        assert result.returncode == 0, (
            f"fix_deps.py failed on runtime inputs.\nstdout:\n{result.stdout}"
            f"\nstderr:\n{result.stderr}"
        )
        assert os.path.isfile("/home/user/cargo.patch"), (
            "fix_deps.py did not create /home/user/cargo.patch"
        )

        patched = apply_patch(original, "/home/user/cargo.patch")
        assert patched == expected, (
            "The script-generated patch was incorrect for runtime inputs.\n"
            f"Expected:\n{expected}\nGot:\n{patched}"
        )
    finally:
        for path, data in backups.items():
            with open(path, "wb") as f:
                f.write(data)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
