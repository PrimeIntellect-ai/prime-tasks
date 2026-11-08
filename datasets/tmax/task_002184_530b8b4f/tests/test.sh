#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import shutil
import subprocess
import tarfile
from pathlib import Path

import pytest


def run(cmd, timeout=180):
    return subprocess.run(cmd, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=timeout)


def test_deploy_sh_executable():
    path = "/home/user/deploy.sh"
    assert os.path.isfile(path), f"Script {path} does not exist."
    assert os.access(path, os.X_OK), f"Script {path} is not executable."


def test_directories_exist():
    assert os.path.isdir("/home/user/backups"), "Directory /home/user/backups does not exist."
    assert os.path.isdir("/home/user/smtp_spool"), "Directory /home/user/smtp_spool does not exist."
    assert os.path.isdir("/home/user/edge_agent"), "Directory /home/user/edge_agent does not exist."


def test_tarball_exists_and_valid():
    tar_path = "/home/user/backups/telemetry_latest.tar.gz"
    assert os.path.isfile(tar_path), f"Backup archive {tar_path} does not exist."

    try:
        with tarfile.open(tar_path, "r:gz") as tar:
            names = tar.getnames()
            has_sensor_1 = any("sensor_1.json" in name for name in names)
            has_sensor_2 = any("sensor_2.json" in name for name in names)
            assert has_sensor_1, "sensor_1.json not found in the backup tarball."
            assert has_sensor_2, "sensor_2.json not found in the backup tarball."
    except tarfile.ReadError:
        pytest.fail(f"{tar_path} is not a valid gzip tarball.")


def test_alert_email_content():
    eml_path = "/home/user/smtp_spool/alert.eml"
    assert os.path.isfile(eml_path), f"Alert email {eml_path} does not exist."

    with open(eml_path, "r") as f:
        content = f.read()

    assert "From: edge-daemon@iot.local" in content, "Missing or incorrect 'From' header in alert.eml."
    assert "To: noc@edge-corp.local" in content, "Missing or incorrect 'To' header in alert.eml."
    assert "Subject: [ALERT] Edge Device Failure" in content, "Missing or incorrect 'Subject' header in alert.eml."
    assert "Hardware watchdog reported a CRITICAL error." in content, "Missing or incorrect body text in alert.eml."

    lines = content.splitlines()
    body_idx = -1
    for i, line in enumerate(lines):
        if "Hardware watchdog reported a CRITICAL error." in line:
            body_idx = i
            break

    assert body_idx > 0, "Body text not found in alert.eml."
    assert lines[body_idx - 1].strip() == "", "There must be exactly one empty line between the headers and the body."


def test_rust_project_release_pipeline_and_runtime_behavior():
    project = Path("/home/user/edge_agent")
    manifest = project / "Cargo.toml"
    source = project / "src/main.rs"
    binary = project / "target/release/edge_agent"
    deploy = "/home/user/deploy.sh"
    archive = Path("/home/user/backups/telemetry_latest.tar.gz")
    alert = Path("/home/user/smtp_spool/alert.eml")

    assert manifest.is_file(), "edge_agent is missing Cargo.toml."
    assert source.is_file(), "edge_agent is missing src/main.rs."

    metadata_result = run([
        "cargo", "metadata", "--no-deps", "--format-version", "1",
        "--manifest-path", str(manifest),
    ])
    assert metadata_result.returncode == 0, metadata_result.stderr
    metadata = json.loads(metadata_result.stdout)
    packages = metadata.get("packages", [])
    assert packages, "Cargo metadata contains no package."
    assert any(
        target.get("kind") == ["bin"] and Path(target.get("src_path", "")) == source
        for package in packages for target in package.get("targets", [])
    ), "edge_agent is not a Cargo binary project using src/main.rs."

    # Replace only main.rs temporarily with a verifier-generated program. A valid
    # deploy script must rebuild it in release mode and execute that exact binary.
    original_source = source.read_bytes()
    nonce = secrets.token_hex(16)
    marker = Path(f"/tmp/edge_agent_executed_{nonce}")
    sentinel_source = (
        "fn main() {\n"
        f"    std::fs::write(\"{marker}\", \"{nonce}\").unwrap();\n"
        "}\n"
    ).encode()
    deploy_result = None
    try:
        source.write_bytes(sentinel_source)
        marker.unlink(missing_ok=True)
        binary.unlink(missing_ok=True)
        deploy_result = run([deploy])
        built_is_elf = binary.is_file() and os.access(binary, os.X_OK) and binary.read_bytes()[:4] == b"\x7fELF"
        marker_value = marker.read_text() if marker.is_file() else None
    finally:
        source.write_bytes(original_source)
        marker.unlink(missing_ok=True)

    assert deploy_result is not None and deploy_result.returncode == 0, (
        (deploy_result.stdout + deploy_result.stderr) if deploy_result else "deploy.sh was not run"
    )
    assert built_is_elf, "deploy.sh did not produce an executable release ELF at target/release/edge_agent."
    assert marker_value == nonce, "deploy.sh did not execute the freshly compiled Rust binary."

    telemetry = Path("/home/user/telemetry_data")
    telemetry.mkdir(parents=True, exist_ok=True)
    random_name_1 = f"probe_{secrets.token_hex(8)}.dat"
    random_name_2 = f"probe_{secrets.token_hex(8)}.json"
    expected_files = {
        random_name_1: secrets.token_bytes(73),
        random_name_2: secrets.token_bytes(91),
    }
    for name, data in expected_files.items():
        (telemetry / name).write_bytes(data)

    # No exact uppercase CRITICAL token: deployment must create the backup but no email.
    Path("/home/user/device_health.log").write_text("INFO: normal\ncritical: lowercase only\nCRITICA\n")
    archive.unlink(missing_ok=True)
    alert.unlink(missing_ok=True)
    result = run([deploy])
    assert result.returncode == 0, result.stdout + result.stderr
    assert binary.is_file() and os.access(binary, os.X_OK), "Release binary is missing after deployment."
    assert binary.read_bytes()[:4] == b"\x7fELF", "Release artifact is not a compiled executable."
    assert archive.is_file(), "Executing deploy.sh did not produce the telemetry archive."
    assert not alert.exists(), "An alert was generated without the exact string CRITICAL."

    try:
        with tarfile.open(archive, "r:gz") as tar:
            members = tar.getmembers()
            for filename, expected in expected_files.items():
                matches = [m for m in members if m.isfile() and (m.name.lstrip("/") == filename or m.name.rstrip("/").endswith("/" + filename))]
                assert matches, f"Fresh telemetry file {filename} is absent from the archive."
                extracted = tar.extractfile(matches[0])
                assert extracted is not None and extracted.read() == expected, f"Archived contents of {filename} are incorrect."
    except tarfile.ReadError:
        pytest.fail("The dynamically generated backup is not a valid gzip tarball.")

    # Exercise the compiled artifact directly with a critical health status.
    Path("/home/user/device_health.log").write_text("INFO: watchdog update\nCRITICAL: verifier probe\n")
    alert.unlink(missing_ok=True)
    result = run([str(binary)])
    assert result.returncode == 0, result.stdout + result.stderr
    assert alert.is_file(), "The compiled edge_agent did not generate an alert for CRITICAL."

    content = alert.read_text()
    expected_email = (
        "From: edge-daemon@iot.local\n"
        "To: noc@edge-corp.local\n"
        "Subject: [ALERT] Edge Device Failure\n"
        "\n"
        "Hardware watchdog reported a CRITICAL error."
    )
    assert content in (expected_email, expected_email + "\n"), "alert.eml does not strictly match the required format."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
