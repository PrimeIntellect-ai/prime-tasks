#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import secrets
import subprocess
from pathlib import Path

import pytest

PROJECT = Path("/home/user/project")


def run_python_script(path):
    assert path.is_file(), f"{path} does not exist or is not a regular file."
    result = subprocess.run(
        ["python3", str(path)],
        cwd=str(PROJECT),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"{path} failed when executed with Python.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def test_automation_scripts_execute_and_transform_inputs():
    fix_script = PROJECT / "fix_deps.py"
    migrate_script = PROJECT / "migrate.py"
    cargo_path = PROJECT / "Cargo.toml"
    policy_path = PROJECT / "policy.json"
    schema_path = PROJECT / "schema_v1.json"
    data_path = PROJECT / "data.json"

    assert fix_script.is_file(), f"{fix_script} does not exist."
    assert migrate_script.is_file(), f"{migrate_script} does not exist."
    assert cargo_path.is_file()
    assert policy_path.is_file()
    assert schema_path.is_file()
    assert data_path.is_file()

    original_cargo = cargo_path.read_bytes()
    original_policy = policy_path.read_bytes()

    versions = {
        "serde": f"9.{secrets.randbelow(80) + 10}.{secrets.randbelow(80) + 10}",
        "tokio": f"8.{secrets.randbelow(80) + 10}.{secrets.randbelow(80) + 10}",
        "reqwest": f"7.{secrets.randbelow(80) + 10}.{secrets.randbelow(80) + 10}",
    }
    temporary_cargo = '''[package]
name = "my_rust_service"
version = "0.1.0"
edition = "2021"

[dependencies]
serde = "0.1.0"
tokio = "0.2.0"
reqwest = "0.3.0"
'''
    temporary_policy = {
        "dependencies": {name: ">=" + version for name, version in versions.items()}
    }

    try:
        cargo_path.write_text(temporary_cargo)
        policy_path.write_text(json.dumps(temporary_policy))
        run_python_script(fix_script)
        updated = cargo_path.read_text()
        for dep, version in versions.items():
            pattern = rf"(?m)^\s*{re.escape(dep)}\s*=\s*(['\"]){re.escape(version)}\1\s*$"
            assert re.search(pattern, updated), (
                f"fix_deps.py did not read policy.json and set {dep} to exactly {version}."
            )
    finally:
        cargo_path.write_bytes(original_cargo)
        policy_path.write_bytes(original_policy)

    # Execute the submitted script against the real project inputs as well.
    run_python_script(fix_script)

    original_schema = schema_path.read_bytes()
    original_data = data_path.read_bytes()
    token = secrets.token_hex(6)
    temporary_schema = [
        {"id": secrets.randbelow(100000) + 100, "first_name": "First" + token, "last_name": "LastA" + token},
        {"id": secrets.randbelow(100000) + 200000, "first_name": "Other" + token, "last_name": "LastB" + token},
    ]
    expected_data = [
        {"id": item["id"], "full_name": item["first_name"] + " " + item["last_name"]}
        for item in temporary_schema
    ]

    try:
        schema_path.write_text(json.dumps(temporary_schema))
        data_path.write_text("[]")
        run_python_script(migrate_script)
        try:
            migrated = json.loads(data_path.read_text())
        except json.JSONDecodeError as exc:
            pytest.fail(f"migrate.py produced invalid JSON: {exc}")
        assert migrated == expected_data, (
            "migrate.py did not derive data.json from the supplied legacy schema."
        )
    finally:
        schema_path.write_bytes(original_schema)
        data_path.write_bytes(original_data)

    # Regenerate the final artifact from the restored real schema.
    run_python_script(migrate_script)


def test_cargo_toml_updated():
    cargo_path = "/home/user/project/Cargo.toml"
    policy_path = "/home/user/project/policy.json"

    assert os.path.isfile(cargo_path), f"{cargo_path} does not exist."
    assert os.path.isfile(policy_path), f"{policy_path} does not exist."

    with open(policy_path, "r") as f:
        policy = json.load(f)

    with open(cargo_path, "r") as f:
        cargo_content = f.read()

    deps = policy.get("dependencies", {})
    for dep, version_policy in deps.items():
        if version_policy.startswith(">="):
            target_version = version_policy[2:]
        else:
            target_version = version_policy

        expected_line_single_quotes = f"{dep} = '{target_version}'"
        expected_line_double_quotes = f'{dep} = "{target_version}"'
        assert (expected_line_double_quotes in cargo_content) or (expected_line_single_quotes in cargo_content) or (f'"{target_version}"' in cargo_content and dep in cargo_content), \
            f"Cargo.toml does not contain the updated version {target_version} for dependency {dep}."


def test_data_json_migrated():
    schema_v1_path = "/home/user/project/schema_v1.json"
    data_path = "/home/user/project/data.json"

    assert os.path.isfile(schema_v1_path), f"{schema_v1_path} does not exist."
    assert os.path.isfile(data_path), f"{data_path} does not exist."

    with open(schema_v1_path, "r") as f:
        schema_v1 = json.load(f)

    expected_data = []
    for item in schema_v1:
        expected_data.append({
            "id": item["id"],
            "full_name": f"{item['first_name']} {item['last_name']}"
        })

    with open(data_path, "r") as f:
        try:
            actual_data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{data_path} is not a valid JSON file.")

    assert actual_data == expected_data, f"The contents of {data_path} do not match the expected migrated schema."


def test_ci_pipeline_sh():
    script_path = "/home/user/project/ci_pipeline.sh"

    assert os.path.isfile(script_path), f"{script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"{script_path} is not executable."

    with open(script_path, "r") as f:
        content = f.read()

    lines = [line.strip() for line in content.strip().split('\n') if line.strip()]
    assert lines[0] == "#!/bin/bash", f"{script_path} must start with #!/bin/bash"

    navigated = any("cd /home/user/project" in line for line in lines)
    assert navigated, f"{script_path} does not navigate to /home/user/project"

    cargo_checked = any("cargo check" in line for line in lines)
    assert cargo_checked, f"{script_path} does not run 'cargo check'"

    cargo_path = PROJECT / "Cargo.toml"
    main_path = PROJECT / "src/main.rs"
    lock_path = PROJECT / "Cargo.lock"
    original_cargo = cargo_path.read_bytes()
    original_main = main_path.read_bytes()
    lock_existed = lock_path.exists()
    original_lock = lock_path.read_bytes() if lock_existed else None

    minimal_manifest = '''[package]
name = "ci_verifier_project"
version = "0.1.0"
edition = "2021"
'''

    try:
        cargo_path.write_text(minimal_manifest)
        if lock_path.exists():
            lock_path.unlink()

        # A successful cargo check must be propagated as success.
        main_path.write_text('fn main() { println!("ok"); }\n')
        expected_success = subprocess.run(
            ["cargo", "check"], cwd=str(PROJECT),
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=60
        ).returncode
        pipeline_success = subprocess.run(
            [script_path], cwd="/tmp",
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=60
        ).returncode
        assert pipeline_success == expected_success, (
            f"ci_pipeline.sh returned {pipeline_success}, but cargo check returned {expected_success}."
        )

        # A failing cargo check must also have its exact status propagated.
        main_path.write_text("fn main( { this is invalid rust }\n")
        expected_failure = subprocess.run(
            ["cargo", "check"], cwd=str(PROJECT),
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=60
        ).returncode
        assert expected_failure != 0, "Verifier's intentionally invalid Rust unexpectedly compiled."
        pipeline_failure = subprocess.run(
            [script_path], cwd="/tmp",
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=60
        ).returncode
        assert pipeline_failure == expected_failure, (
            f"ci_pipeline.sh returned {pipeline_failure}, but cargo check returned {expected_failure}."
        )
    finally:
        cargo_path.write_bytes(original_cargo)
        main_path.write_bytes(original_main)
        if lock_existed:
            lock_path.write_bytes(original_lock)
        elif lock_path.exists():
            lock_path.unlink()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
