#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import stat
import subprocess


def get_expected_max_error():
    max_err = 0.0
    for n in range(101):
        t = n * 0.1
        y_num = 1.0 * (0.95 ** n)
        y_exact = math.exp(-0.5 * t)
        err = abs(y_num - y_exact)
        if err > max_err:
            max_err = err
    return f"{max_err:.6f}"


def test_rust_project_exists():
    """Check that the Rust project directory and Cargo.toml exist."""
    project_dir = "/home/user/ode_validator"
    cargo_toml = os.path.join(project_dir, "Cargo.toml")

    assert os.path.isdir(project_dir), f"Rust project directory {project_dir} does not exist."
    assert os.path.isfile(cargo_toml), f"Cargo.toml not found at {cargo_toml}."


def test_rust_program_builds_and_generates_output():
    """Build the submitted Rust binary and execute the resulting native artifact."""
    project_dir = "/home/user/ode_validator"
    manifest = os.path.join(project_dir, "Cargo.toml")
    output_file = "/home/user/max_error.txt"

    metadata_result = subprocess.run(
        ["cargo", "metadata", "--no-deps", "--format-version", "1", "--manifest-path", manifest],
        cwd=project_dir,
        text=True,
        capture_output=True,
        timeout=60,
    )
    assert metadata_result.returncode == 0, metadata_result.stderr
    metadata = json.loads(metadata_result.stdout)

    manifest_real = os.path.realpath(manifest)
    packages = [
        package for package in metadata["packages"]
        if os.path.realpath(package["manifest_path"]) == manifest_real
    ]
    assert len(packages) == 1, "Cargo.toml must define the submitted Rust package."
    package = packages[0]
    assert package["dependencies"] == [], "Only the Rust standard library may be used."

    binary_targets = [target for target in package["targets"] if "bin" in target["kind"]]
    assert binary_targets, "The Cargo project has no Rust binary target."
    for target in binary_targets:
        source_path = target["src_path"]
        assert os.path.isfile(source_path), f"Rust source file not found: {source_path}"
        assert stat.S_ISREG(os.stat(source_path).st_mode), f"Rust source is not a regular file: {source_path}"
        with open(source_path, "r", encoding="utf-8") as source_file:
            assert source_file.read().strip(), f"Rust source file is empty: {source_path}"

    build_result = subprocess.run(
        [
            "cargo", "build", "--release", "--bins", "--message-format=json",
            "--manifest-path", manifest,
        ],
        cwd=project_dir,
        text=True,
        capture_output=True,
        timeout=180,
    )
    assert build_result.returncode == 0, build_result.stderr

    executables = []
    for line in build_result.stdout.splitlines():
        try:
            message = json.loads(line)
        except json.JSONDecodeError:
            continue
        if (
            message.get("reason") == "compiler-artifact"
            and message.get("package_id") == package["id"]
            and "bin" in message.get("target", {}).get("kind", [])
            and message.get("executable")
        ):
            executables.append(message["executable"])

    assert executables, "Cargo did not produce a binary executable."
    expected = get_expected_max_error()
    generated_correct_output = False

    for executable in executables:
        assert os.path.isfile(executable), f"Built executable not found: {executable}"
        with open(executable, "rb") as binary_file:
            assert binary_file.read(4) == b"\x7fELF", "Cargo output is not a native Linux executable."

        if os.path.exists(output_file):
            os.remove(output_file)
        run_result = subprocess.run(
            [executable],
            cwd=project_dir,
            text=True,
            capture_output=True,
            timeout=30,
        )
        if run_result.returncode != 0 or not os.path.isfile(output_file):
            continue
        with open(output_file, "r", encoding="utf-8") as output:
            if output.read().strip() == expected:
                generated_correct_output = True
                break

    assert generated_correct_output, "Running the built Rust program did not generate the correct output file."


def test_max_error_file_content():
    """Check that the output file exists and contains the correct maximum absolute error."""
    output_file = "/home/user/max_error.txt"
    assert os.path.isfile(output_file), f"Output file {output_file} does not exist."

    with open(output_file, "r") as f:
        content = f.read().strip()

    expected = get_expected_max_error()
    assert content == expected, f"Incorrect max error. Expected '{expected}', got '{content}'."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
