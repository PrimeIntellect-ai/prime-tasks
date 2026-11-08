#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import secrets
import struct
import subprocess
import urllib.parse

import pytest


def test_resolve_go_exists():
    assert os.path.exists("/home/user/resolve.go"), "/home/user/resolve.go does not exist."
    assert os.path.isfile("/home/user/resolve.go"), "/home/user/resolve.go is not a file."


def test_linux_binary_exists_and_format():
    binary_path = "/home/user/resolve_linux_amd64"
    assert os.path.exists(binary_path), f"{binary_path} does not exist."
    assert os.path.isfile(binary_path), f"{binary_path} is not a file."

    with open(binary_path, "rb") as f:
        header = f.read(20)
    assert header[:4] == b"\x7fELF", f"{binary_path} is not an ELF executable."
    assert header[4] == 2, f"{binary_path} is not a 64-bit ELF executable."
    assert header[5] == 1, f"{binary_path} is not a little-endian ELF executable."
    assert struct.unpack("<H", header[18:20])[0] == 62, f"{binary_path} is not an amd64 ELF executable."
    assert os.access(binary_path, os.X_OK), f"{binary_path} is not executable."


def test_windows_binary_exists_and_format():
    binary_path = "/home/user/resolve_windows_amd64.exe"
    assert os.path.exists(binary_path), f"{binary_path} does not exist."
    assert os.path.isfile(binary_path), f"{binary_path} is not a file."

    with open(binary_path, "rb") as f:
        data = f.read()
    assert data[:2] == b"MZ", f"{binary_path} is not a PE executable."
    assert len(data) >= 0x40, f"{binary_path} has a truncated DOS header."
    pe_offset = struct.unpack("<I", data[0x3c:0x40])[0]
    assert pe_offset + 6 <= len(data), f"{binary_path} has an invalid PE header offset."
    assert data[pe_offset:pe_offset + 4] == b"PE\x00\x00", f"{binary_path} has no PE signature."
    machine = struct.unpack("<H", data[pe_offset + 4:pe_offset + 6])[0]
    assert machine == 0x8664, f"{binary_path} is not an amd64 PE executable."


def test_migration_sql():
    sql_path = "/home/user/migration.sql"
    assert os.path.exists(sql_path), f"{sql_path} does not exist."

    with open(sql_path, "r") as f:
        content = f.read().lower()

    assert "alter table" in content and "deployments" in content, "Missing ALTER TABLE deployments statement."
    assert "resolved_version" in content, "Missing resolved_version column."
    assert "target_os" in content, "Missing target_os column."
    assert "varchar(50)" in content, "Missing VARCHAR(50) type."

    uncommented = re.sub(r"/\*.*?\*/", " ", content, flags=re.S)
    uncommented = re.sub(r"--[^\n]*", " ", uncommented)
    statements = [s for s in uncommented.split(";") if s.strip()]
    deployment_alters = [
        s for s in statements
        if re.search(r"\balter\s+table\s+deployments\b", s, re.I)
    ]
    assert deployment_alters, "No executable ALTER TABLE deployments statement found."
    joined = " ; ".join(deployment_alters)
    for column in ("resolved_version", "target_os"):
        pattern = rf"\badd\s+(?:column\s+)?{column}\s+varchar\s*\(\s*50\s*\)\b"
        assert re.search(pattern, joined, re.I), f"Missing ADD COLUMN {column} VARCHAR(50)."


def run_and_check(binary_path, url, expected):
    result = subprocess.run([binary_path, url], capture_output=True, text=True, timeout=10)
    assert result.returncode == 0, f"Program exited with code {result.returncode}. Stderr: {result.stderr}"
    output = result.stdout.strip()
    assert output == expected, f"Expected '{expected}', got '{output}'"
    assert result.stderr == "", f"Program wrote unexpected stderr: {result.stderr}"


def test_resolve_logic_worker_v1():
    run_and_check(
        "/home/user/resolve_linux_amd64",
        "http://ci.local/resolve?pkg=worker&min_version=v1.0.0",
        "v1.5.0",
    )


def test_resolve_logic_api_v1():
    run_and_check(
        "/home/user/resolve_linux_amd64",
        "http://ci.local/resolve?pkg=api&min_version=v1.0.1",
        "v1.2.0",
    )


def test_resolve_logic_none():
    run_and_check(
        "/home/user/resolve_linux_amd64",
        "http://ci.local/resolve?pkg=worker&min_version=v3.0.0",
        "none",
    )


@pytest.fixture(scope="session")
def rebuilt_binaries(tmp_path_factory):
    out_dir = tmp_path_factory.mktemp("rebuilt")
    linux = out_dir / "resolve_linux_amd64"
    windows = out_dir / "resolve_windows_amd64.exe"

    env = os.environ.copy()
    env.update({"GOOS": "linux", "GOARCH": "amd64", "CGO_ENABLED": "0"})
    result = subprocess.run(
        ["go", "build", "-o", str(linux), "/home/user/resolve.go"],
        cwd="/home/user", env=env, capture_output=True, text=True, timeout=120,
    )
    assert result.returncode == 0, f"resolve.go does not build for linux/amd64: {result.stderr}"

    env.update({"GOOS": "windows", "GOARCH": "amd64", "CGO_ENABLED": "0"})
    result = subprocess.run(
        ["go", "build", "-o", str(windows), "/home/user/resolve.go"],
        cwd="/home/user", env=env, capture_output=True, text=True, timeout=120,
    )
    assert result.returncode == 0, f"resolve.go does not build for windows/amd64: {result.stderr}"
    return str(linux), str(windows)


def test_windows_binary_is_cross_compiled_from_submitted_source(rebuilt_binaries):
    _, rebuilt_windows = rebuilt_binaries
    with open("/home/user/resolve_windows_amd64.exe", "rb") as f:
        submitted = f.read()
    with open(rebuilt_windows, "rb") as f:
        rebuilt = f.read()
    assert submitted == rebuilt, "Windows binary is not the cross-compiled submitted resolve.go program."


def parse_simple_semver(version):
    match = re.fullmatch(r"v(\d+)\.(\d+)\.(\d+)", version)
    assert match, f"Invalid verifier-generated version: {version}"
    return tuple(int(x) for x in match.groups())


def expected_resolution(versions, minimum):
    minimum_tuple = parse_simple_semver(minimum)
    eligible = [
        version for version in versions
        if parse_simple_semver(version)[0] == minimum_tuple[0]
        and parse_simple_semver(version) >= minimum_tuple
    ]
    return max(eligible, key=parse_simple_semver) if eligible else "none"


def test_dynamic_catalog_url_parsing_and_resolution(rebuilt_binaries):
    rebuilt_linux, _ = rebuilt_binaries
    submitted_linux = "/home/user/resolve_linux_amd64"
    catalog_path = "/home/user/catalog.json"
    with open(catalog_path, "rb") as f:
        original_catalog = f.read()

    token = secrets.token_hex(8)
    package = f"team worker {token}"
    other_package = f"api-{secrets.token_hex(8)}"
    major = secrets.randbelow(20) + 3
    base_minor = secrets.randbelow(10) + 2
    versions = [
        f"v{major + 1}.99.99",
        f"v{major}.{base_minor}.1",
        f"v{major}.0.9",
        f"v{major}.{base_minor + 4}.2",
        f"v{major - 1}.99.99",
        f"v{major}.{base_minor + 2}.8",
    ]
    minimum = f"v{major}.{base_minor}.5"
    other_versions = ["v2.0.0", "v2.7.3", "v3.9.9", "v2.4.1"]

    try:
        catalog = {package: versions, other_package: other_versions}
        with open(catalog_path, "w") as f:
            json.dump(catalog, f)

        queries = [
            (package, minimum, versions),
            (other_package, "v2.3.0", other_versions),
            (package, f"v{major + 7}.0.0", versions),
        ]
        for pkg, min_version, available in queries:
            params = urllib.parse.urlencode({
                "unused": secrets.token_hex(4),
                "min_version": min_version,
                "pkg": pkg,
            })
            url = f"https://example.invalid/arbitrary/path?{params}"
            expected = expected_resolution(available, min_version)
            for binary in (submitted_linux, rebuilt_linux):
                run_and_check(binary, url, expected)

        new_highest = f"v{major}.{base_minor + 9}.7"
        catalog[package].append(new_highest)
        with open(catalog_path, "w") as f:
            json.dump(catalog, f)
        changed_url = "http://another.invalid/resolve?" + urllib.parse.urlencode({
            "pkg": package,
            "min_version": minimum,
        })
        expected = expected_resolution(catalog[package], minimum)
        assert expected == new_highest
        for binary in (submitted_linux, rebuilt_linux):
            run_and_check(binary, changed_url, expected)
    finally:
        with open(catalog_path, "wb") as f:
            f.write(original_catalog)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
