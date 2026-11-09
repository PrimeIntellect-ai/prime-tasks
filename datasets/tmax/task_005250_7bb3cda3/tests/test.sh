#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import hmac
import json
import os
import stat
import subprocess
from pathlib import Path

import pytest


def test_key_permissions():
    """Test that the master_secret.key file has exactly 0400 permissions."""
    key_path = "/app/master_secret.key"
    assert os.path.exists(key_path), f"File {key_path} does not exist."
    st = os.stat(key_path)
    perms = stat.S_IMODE(st.st_mode)
    assert perms == 0o400, f"Permissions for {key_path} are {oct(perms)}, expected 0o400."


def test_metric_f1_accuracy():
    """Test that the generated rotated credentials achieve an F1 score >= 0.85."""
    output_path = "/home/user/rotated_credentials.json"
    key_path = "/app/master_secret.key"

    assert os.path.exists(output_path), f"Output file {output_path} does not exist."
    assert os.path.exists(key_path), f"Key file {key_path} does not exist."

    with open(key_path, "rb") as f:
        secret = f.read()

    try:
        with open(output_path, "r") as f:
            generated = json.load(f)
    except Exception as e:
        pytest.fail(f"Failed to parse {output_path} as JSON: {e}")

    ground_truth_uids = {"admin_992", "user_103", "service_db_44", "sys_ops_01"}

    correct_matches = 0
    for uid in ground_truth_uids:
        if uid in generated:
            expected_sig = hmac.new(secret, uid.encode('utf-8'), hashlib.sha256).hexdigest()
            expected_token = f"{uid}.{expected_sig}"
            if generated[uid] == expected_token:
                correct_matches += 1

    precision = correct_matches / max(len(generated), 1)
    recall = correct_matches / len(ground_truth_uids)

    if precision + recall == 0:
        f1 = 0.0
    else:
        f1 = 2 * (precision * recall) / (precision + recall)

    assert f1 >= 0.85, f"F1 accuracy {f1:.3f} is below the threshold of 0.85. Correct matches: {correct_matches}, Generated count: {len(generated)}"


def test_rust_project_and_runtime_key_check():
    """Build and execute the submitted Rust binary, including its key-mode failure path."""
    project = Path("/home/user/rotator")
    manifest = project / "Cargo.toml"
    output = Path("/home/user/rotated_credentials.json")
    key_path = Path("/app/master_secret.key")

    assert project.is_dir(), f"Rust project directory {project} does not exist."
    assert manifest.is_file(), f"Cargo manifest {manifest} does not exist."

    metadata_result = subprocess.run(
        ["cargo", "metadata", "--format-version", "1", "--no-deps"],
        cwd=project,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=60,
    )
    assert metadata_result.returncode == 0, f"Invalid Cargo project: {metadata_result.stderr}"
    metadata = json.loads(metadata_result.stdout)

    manifest_resolved = manifest.resolve()
    packages = [
        package for package in metadata.get("packages", [])
        if Path(package["manifest_path"]).resolve() == manifest_resolved
    ]
    assert packages, "Cargo metadata does not contain the submitted rotator package."
    package = packages[0]
    bins = [target for target in package.get("targets", []) if "bin" in target.get("kind", [])]
    assert bins, "The rotator Cargo project has no Rust binary target."

    default_run = package.get("default_run")
    if default_run:
        selected = [target for target in bins if target["name"] == default_run]
        assert selected, f"Cargo default-run target {default_run!r} is not a binary."
        target = selected[0]
    elif len(bins) == 1:
        target = bins[0]
    else:
        selected = [target for target in bins if target["name"] == package["name"]]
        assert len(selected) == 1, "Multiple binaries exist and no unambiguous default binary is configured."
        target = selected[0]

    source = Path(target["src_path"])
    assert source.is_file() and source.suffix == ".rs", f"Binary source {source} is not a Rust source file."
    assert source.stat().st_size > 0, f"Rust source file {source} is empty."

    build_env = os.environ.copy()
    build_env["CARGO_TARGET_DIR"] = "/tmp/verifier-rotator-target"
    build_result = subprocess.run(
        ["cargo", "build", "--bin", target["name"], "--message-format=json-render-diagnostics"],
        cwd=project,
        env=build_env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=180,
    )
    assert build_result.returncode == 0, f"Rust project failed to build:\n{build_result.stderr}"

    executables = []
    for line in build_result.stdout.splitlines():
        try:
            message = json.loads(line)
        except json.JSONDecodeError:
            continue
        if (message.get("reason") == "compiler-artifact"
                and message.get("target", {}).get("name") == target["name"]
                and message.get("executable")):
            executables.append(Path(message["executable"]))
    assert executables, "Cargo did not produce an executable for the rotator binary."
    executable = executables[-1]
    assert executable.is_file(), f"Built executable {executable} does not exist."
    with executable.open("rb") as f:
        assert f.read(4) == b"\x7fELF", "The built rotator artifact is not a native executable."

    # A non-0400 key must cause the Rust program to panic before producing output.
    if output.exists():
        output.unlink()
    os.chmod(key_path, 0o600)
    try:
        bad_run = subprocess.run(
            [str(executable)],
            cwd=project,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
        )
    finally:
        os.chmod(key_path, 0o400)

    assert bad_run.returncode != 0, "Rotator succeeded even though the key mode was not 0400."
    assert "panic" in bad_run.stderr.lower(), f"Rotator did not panic for an invalid key mode. stderr: {bad_run.stderr!r}"
    assert not output.exists(), "Rotator produced credentials before rejecting an insecure key mode."

    # Execute the same compiled Rust artifact with the correct mode and require it
    # to recreate the requested output; validate its independently derived answers.
    good_run = subprocess.run(
        [str(executable)],
        cwd=project,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert good_run.returncode == 0, f"Rotator failed with a 0400 key:\n{good_run.stderr}"
    assert output.is_file(), "The Rust rotator did not generate rotated_credentials.json."

    with key_path.open("rb") as f:
        secret = f.read()
    try:
        with output.open("r") as f:
            generated = json.load(f)
    except Exception as e:
        pytest.fail(f"Rust-generated output is not valid JSON: {e}")

    ground_truth_uids = {"admin_992", "user_103", "service_db_44", "sys_ops_01"}
    correct_matches = 0
    for uid in ground_truth_uids:
        expected_sig = hmac.new(secret, uid.encode("utf-8"), hashlib.sha256).hexdigest()
        if generated.get(uid) == f"{uid}.{expected_sig}":
            correct_matches += 1
    precision = correct_matches / max(len(generated), 1)
    recall = correct_matches / len(ground_truth_uids)
    f1 = 0.0 if precision + recall == 0 else 2 * precision * recall / (precision + recall)
    assert f1 >= 0.85, f"Rust-generated credentials have F1 accuracy {f1:.3f}, below 0.85."


TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
