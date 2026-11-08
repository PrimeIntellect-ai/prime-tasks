#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import base64
import urllib.parse
import subprocess
import uuid
from pathlib import Path
import pytest


def fully_url_decode(val: str) -> str:
    decoded = urllib.parse.unquote(val)
    while True:
        new_decoded = urllib.parse.unquote(decoded)
        if new_decoded == decoded:
            break
        decoded = new_decoded
    return decoded


def compute_expected_findings(logs_path: str) -> list:
    with open(logs_path, "r") as f:
        logs = json.load(f)

    findings = []
    for entry in logs:
        flags = []
        url = entry.get("url", "")
        headers = entry.get("headers", {})

        parsed_url = urllib.parse.urlparse(url)
        redirect_val = None
        for param in parsed_url.query.split("&"):
            if param.startswith("redirect="):
                redirect_val = param.split("=", 1)[1]
                break

        if redirect_val is not None:
            decoded = fully_url_decode(redirect_val)

            if decoded.startswith("http://") or decoded.startswith("https://"):
                if not (decoded.startswith("http://example.com") or decoded.startswith("https://example.com")):
                    flags.append("open_redirect")

            lower_decoded = decoded.lower()
            if "<script" in lower_decoded or "javascript:" in lower_decoded:
                flags.append("xss")

        auth = headers.get("Authorization", "")
        if auth.startswith("Basic "):
            b64_payload = auth[6:]
            try:
                decoded_auth = base64.b64decode(b64_payload).decode("utf-8")
                if "role=admin" in decoded_auth:
                    flags.append("privesc")
            except Exception:
                pass

        if flags:
            findings.append({
                "id": entry.get("id"),
                "flags": sorted(flags)
            })

    findings.sort(key=lambda x: x["id"])
    return findings


def assert_report_matches(findings_path: str, expected_findings: list):
    assert os.path.exists(findings_path), f"The file {findings_path} is missing. Did the tool run successfully?"
    assert os.path.isfile(findings_path), f"The path {findings_path} is not a file."

    with open(findings_path, "r") as f:
        try:
            actual_findings = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {findings_path} does not contain valid JSON.")

    assert isinstance(actual_findings, list), f"The content of {findings_path} must be a JSON array."
    assert len(actual_findings) == len(expected_findings), f"Expected {len(expected_findings)} findings, but got {len(actual_findings)}."

    for i, (actual, expected) in enumerate(zip(actual_findings, expected_findings)):
        assert actual.get("id") == expected["id"], f"Finding at index {i} has incorrect 'id'. Expected '{expected['id']}', got '{actual.get('id')}'."

        actual_flags = actual.get("flags", [])
        expected_flags = expected["flags"]

        assert isinstance(actual_flags, list), f"The 'flags' field for id '{actual['id']}' must be an array."
        assert actual_flags == expected_flags, f"Flags for id '{actual['id']}' are incorrect. Expected {expected_flags}, got {actual_flags}."


def test_findings_json_exists_and_correct():
    logs_path = "/home/user/logs.json"
    findings_path = "/home/user/findings.json"

    assert os.path.exists(logs_path), f"The file {logs_path} is missing, cannot compute expected findings."
    assert os.path.exists(findings_path), f"The file {findings_path} is missing. Did the tool run successfully?"
    assert os.path.isfile(findings_path), f"The path {findings_path} is not a file."

    with open(findings_path, "r") as f:
        try:
            actual_findings = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {findings_path} does not contain valid JSON.")

    expected_findings = compute_expected_findings(logs_path)

    assert isinstance(actual_findings, list), f"The content of {findings_path} must be a JSON array."
    assert len(actual_findings) == len(expected_findings), f"Expected {len(expected_findings)} findings, but got {len(actual_findings)}."

    for i, (actual, expected) in enumerate(zip(actual_findings, expected_findings)):
        assert actual.get("id") == expected["id"], f"Finding at index {i} has incorrect 'id'. Expected '{expected['id']}', got '{actual.get('id')}'."

        actual_flags = actual.get("flags", [])
        expected_flags = expected["flags"]

        assert isinstance(actual_flags, list), f"The 'flags' field for id '{actual['id']}' must be an array."
        assert actual_flags == expected_flags, f"Flags for id '{actual['id']}' are incorrect. Expected {expected_flags}, got {actual_flags}."


def build_scanner() -> str:
    project = Path("/home/user/scanner")
    manifest = project / "Cargo.toml"
    assert project.is_dir(), "/home/user/scanner must be a Rust project directory."
    assert manifest.is_file(), "/home/user/scanner/Cargo.toml is missing."
    assert any(path.is_file() for path in project.rglob("*.rs")), "The scanner project contains no Rust source files."

    result = subprocess.run(
        ["cargo", "build", "--manifest-path", str(manifest), "--bins", "--message-format=json"],
        cwd=str(project), text=True, capture_output=True, timeout=120
    )
    assert result.returncode == 0, f"The Rust scanner did not compile successfully:\n{result.stderr}\n{result.stdout}"

    executables = []
    for line in result.stdout.splitlines():
        try:
            message = json.loads(line)
        except json.JSONDecodeError:
            continue
        target = message.get("target", {})
        executable = message.get("executable")
        if message.get("reason") == "compiler-artifact" and executable and "bin" in target.get("kind", []):
            executables.append((target.get("name"), executable))

    assert executables, "The Cargo project does not build a Rust CLI binary."

    metadata_result = subprocess.run(
        ["cargo", "metadata", "--manifest-path", str(manifest), "--no-deps", "--format-version=1"],
        cwd=str(project), text=True, capture_output=True, timeout=30
    )
    assert metadata_result.returncode == 0, f"Unable to inspect the Cargo project:\n{metadata_result.stderr}"
    metadata = json.loads(metadata_result.stdout)
    manifest_real = manifest.resolve()
    package = next((p for p in metadata.get("packages", []) if Path(p["manifest_path"]).resolve() == manifest_real), None)
    assert package is not None, "Cargo metadata does not contain the scanner package."

    preferred = package.get("default_run") or package.get("name")
    matches = [exe for name, exe in executables if name == preferred]
    if matches:
        return matches[0]
    assert len(executables) == 1, "The scanner project has multiple binaries but no unambiguous default CLI."
    return executables[0][1]


def test_rust_cli_processes_unseen_logs():
    logs_path = Path("/home/user/logs.json")
    findings_path = Path("/home/user/findings.json")
    original_logs = logs_path.read_bytes()
    original_findings = findings_path.read_bytes() if findings_path.is_file() else None
    token = uuid.uuid4().hex

    def twice(value: str) -> str:
        return urllib.parse.quote(urllib.parse.quote(value, safe=""), safe="")

    def basic(value: str) -> str:
        return "Basic " + base64.b64encode(value.encode("utf-8")).decode("ascii")

    dynamic_logs = [
        {
            "id": f"z-{token}",
            "url": "/login?redirect=" + twice(f"https://{token}.invalid/auth"),
            "headers": {"Authorization": basic("user:password")}
        },
        {
            "id": f"a-{token}",
            "url": "/login?redirect=" + twice("https://example.com/path?<ScRiPt>alert(1)</sCrIpT>"),
            "headers": {"Authorization": basic(f"user:{token}:role=admin")}
        },
        {
            "id": f"b-{token}",
            "url": "/login?foo=1&redirect=" + twice(f"https://{token}.invalid/?next=JaVaScRiPt:alert(1)"),
            "headers": {"Authorization": basic(f"account:{token}:role=admin")}
        },
        {
            "id": f"m-{token}",
            "url": "/login?redirect=" + twice("javascript:alert(document.cookie)"),
            "headers": {"Authorization": "Basic !!!not-base64!!!"}
        },
        {
            "id": f"n-{token}",
            "url": "/login?redirect=" + twice("https://example.com/safe"),
            "headers": {"Authorization": basic("role=Admin")}
        }
    ]

    try:
        logs_path.write_text(json.dumps(dynamic_logs), encoding="utf-8")
        expected = compute_expected_findings(str(logs_path))
        executable = build_scanner()

        if findings_path.exists():
            findings_path.unlink()

        run = subprocess.run(
            [executable], cwd="/home/user/scanner", text=True,
            capture_output=True, timeout=30
        )
        assert run.returncode == 0, f"The compiled scanner exited unsuccessfully:\n{run.stderr}\n{run.stdout}"
        assert_report_matches(str(findings_path), expected)
    finally:
        logs_path.write_bytes(original_logs)
        if original_findings is None:
            if findings_path.exists():
                findings_path.unlink()
        else:
            findings_path.write_bytes(original_findings)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
