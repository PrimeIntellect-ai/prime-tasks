#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import hmac
import json
import os
import re
import subprocess


def test_suid_bin_evidence():
    evidence_file = "/home/user/evidence/suid_bin.txt"
    assert os.path.isfile(evidence_file), f"Evidence file {evidence_file} is missing."

    with open(evidence_file, "r") as f:
        content = f.read().strip()

    expected_bin = "/home/user/bin/backup_util"
    assert content == expected_bin, f"Expected {expected_bin} in {evidence_file}, but got {content}."


def test_attacker_ip_evidence():
    evidence_file = "/home/user/evidence/attacker_ip.txt"
    assert os.path.isfile(evidence_file), f"Evidence file {evidence_file} is missing."

    with open(evidence_file, "r") as f:
        content = f.read().strip()

    expected_ip = "172.16.0.4"
    assert content == expected_ip, f"Expected IP {expected_ip} in {evidence_file}, but got {content}."


def test_rust_project_and_execution():
    project_dir = "/home/user/token_forge"
    manifest = os.path.join(project_dir, "Cargo.toml")
    evidence_file = "/home/user/evidence/forged_token.txt"

    assert os.path.isdir(project_dir), f"Rust project directory {project_dir} is missing."
    assert os.path.isfile(manifest), f"Cargo manifest {manifest} is missing."

    metadata_result = subprocess.run(
        ["cargo", "metadata", "--format-version", "1", "--no-deps", "--manifest-path", manifest],
        cwd=project_dir,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=60,
    )
    assert metadata_result.returncode == 0, f"Cargo.toml is invalid:\n{metadata_result.stderr}"
    metadata = json.loads(metadata_result.stdout)
    manifest_real = os.path.realpath(manifest)
    packages = [p for p in metadata["packages"] if os.path.realpath(p["manifest_path"]) == manifest_real]
    assert packages, "Cargo.toml must define the token_forge Rust package."

    package = packages[0]
    dependency_names = {dep["name"] for dep in package.get("dependencies", [])}
    assert "hmac" in dependency_names, "Cargo.toml must include the hmac crate as a dependency."
    assert "sha2" in dependency_names, "Cargo.toml must include the sha2 crate as a dependency."

    binary_targets = [target for target in package.get("targets", []) if "bin" in target.get("kind", [])]
    assert binary_targets, "The Rust project must contain a binary target."
    source_path = os.path.realpath(binary_targets[0]["src_path"])
    assert os.path.isfile(source_path), f"Rust binary source {source_path} is missing."
    assert os.path.commonpath([os.path.realpath(project_dir), source_path]) == os.path.realpath(project_dir), \
        "The Rust binary source must be inside /home/user/token_forge."

    with open(source_path, "r", encoding="utf-8") as f:
        source = f.read()
    code = re.sub(r"/\*.*?\*/", "", source, flags=re.DOTALL)
    code = re.sub(r"//.*", "", code)
    assert re.search(r"\bhmac\s*::", code), "Rust source must use the hmac crate."
    assert re.search(r"\bsha2\s*::", code), "Rust source must use the sha2 crate."
    assert re.search(r"\.\s*update\s*\(", code), "Rust source must update an HMAC with the payload."
    assert re.search(r"\.\s*finalize\s*\(", code), "Rust source must finalize the HMAC computation."

    if os.path.exists(evidence_file):
        os.remove(evidence_file)

    env = os.environ.copy()
    env["HOME"] = "/home/user"
    if os.path.isdir("/home/user/.cargo"):
        env["CARGO_HOME"] = "/home/user/.cargo"
    run_result = subprocess.run(
        ["cargo", "run", "--quiet", "--manifest-path", manifest],
        cwd=project_dir,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=120,
    )
    assert run_result.returncode == 0, f"Rust token generator failed:\n{run_result.stderr}"
    assert os.path.isfile(evidence_file), "Running the Rust program did not create forged_token.txt."


def test_forged_token_evidence():
    evidence_file = "/home/user/evidence/forged_token.txt"
    assert os.path.isfile(evidence_file), f"Evidence file {evidence_file} is missing."

    with open(evidence_file, "r") as f:
        content = f.read().strip()

    ip = "172.16.0.4"
    exp = "1900000000"
    key = b"F0r3ns1csK3y!"
    payload = f"IP:{ip}:EXP:{exp}".encode("utf-8")

    signature = hmac.new(key, payload, hashlib.sha256).hexdigest()
    expected_token = f"IP:{ip}:EXP:{exp}.{signature}"

    assert content == expected_token, f"Expected token {expected_token} in {evidence_file}, but got {content}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
