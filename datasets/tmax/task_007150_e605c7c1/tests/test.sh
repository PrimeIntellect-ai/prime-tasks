#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import pwd
import re
import subprocess

PROJECT = "/home/user/min_tool"
RESULT = "/home/user/result.json"
SOURCE = "/home/user/min_tool/src/main.rs"
CARGO_TOML = "/home/user/min_tool/Cargo.toml"


def function_body(source, function_name):
    match = re.search(r"\bfn\s+" + re.escape(function_name) + r"\s*\([^)]*\)\s*(?:->\s*[^\{]+)?\{", source)
    assert match, f"Could not find function {function_name}."
    start = source.find("{", match.start())
    depth = 0
    for index in range(start, len(source)):
        if source[index] == "{":
            depth += 1
        elif source[index] == "}":
            depth -= 1
            if depth == 0:
                return source[start + 1:index]
    assert False, f"Could not parse function {function_name}."


def expected_cpuid_vendor():
    helper_source = "/tmp/cpuid_reference.rs"
    helper_binary = "/tmp/cpuid_reference"
    for path in (helper_source, helper_binary):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    with open(helper_source, "w") as f:
        f.write(r'''
use std::arch::x86_64::__cpuid;

fn main() {
    let value = unsafe { __cpuid(0) };
    let mut bytes = Vec::new();
    bytes.extend_from_slice(&value.ebx.to_le_bytes());
    bytes.extend_from_slice(&value.edx.to_le_bytes());
    bytes.extend_from_slice(&value.ecx.to_le_bytes());
    print!("{}", String::from_utf8(bytes).unwrap());
}
''')

    build = subprocess.run(
        ["rustc", helper_source, "-O", "-o", helper_binary],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=60,
    )
    assert build.returncode == 0, f"Failed to build independent CPUID helper:\n{build.stdout}"
    run = subprocess.run(
        [helper_binary], text=True, stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT, timeout=10,
    )
    assert run.returncode == 0, f"Independent CPUID helper failed:\n{run.stdout}"
    assert len(run.stdout) == 12, f"Independent CPUID helper returned {run.stdout!r}."
    return run.stdout


def demote_to_user():
    account = pwd.getpwnam("user")
    os.initgroups(account.pw_name, account.pw_gid)
    os.setgid(account.pw_gid)
    os.setuid(account.pw_uid)


def test_complete_implementation_and_execution():
    assert os.path.exists(CARGO_TOML), f"{CARGO_TOML} is missing."
    with open(CARGO_TOML, "r") as f:
        cargo_content = f.read()

    # Preserve the original dependency checks and require the requested constraint.
    assert "semver" in cargo_content, "semver dependency is missing from Cargo.toml"
    assert "0.9.0" not in cargo_content, "Cargo.toml still contains the old 0.9.0 semver dependency."
    assert re.search(r'^\s*semver\s*=\s*"1\.0"\s*(?:#.*)?$', cargo_content, re.MULTILINE), \
        'Cargo.toml must contain semver = "1.0".'

    assert os.path.exists(SOURCE), f"{SOURCE} is missing."
    with open(SOURCE, "r") as f:
        source = f.read()
    body = function_body(source, "cpuid_vendor")
    body_without_comments = re.sub(r"/\*.*?\*/|//[^\n]*", "", body, flags=re.DOTALL)
    assert re.search(r'asm!\s*\(\s*(?:r[#]*)?["\'][^"\']*\bcpuid\b', body_without_comments, re.IGNORECASE | re.DOTALL), \
        "cpuid_vendor must invoke the cpuid instruction using Rust inline asm!."
    lowered = body_without_comments.lower()
    for register in ("eax", "ebx", "edx", "ecx"):
        assert register in lowered, f"cpuid_vendor inline assembly does not handle the {register} register."

    expected_vendor = expected_cpuid_vendor()

    try:
        os.remove(RESULT)
    except FileNotFoundError:
        pass

    env = os.environ.copy()
    env["HOME"] = "/home/user"
    run = subprocess.run(
        ["cargo", "run", "--release"],
        cwd=PROJECT,
        env=env,
        preexec_fn=demote_to_user,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=180,
    )
    assert run.returncode == 0, f"cargo run --release failed:\n{run.stdout}"

    # Preserve all original result assertions, now against freshly generated output.
    assert os.path.exists(RESULT), f"Expected output file {RESULT} does not exist after cargo run --release."
    with open(RESULT, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"{RESULT} does not contain valid JSON."

    assert "vendor" in data, "JSON missing 'vendor' field."
    assert "semver_check" in data, "JSON missing 'semver_check' field."
    assert "bench_success" in data, "JSON missing 'bench_success' field."
    assert data["semver_check"] is True, "semver_check is not true. The semver logic failed."
    assert data["bench_success"] is True, "bench_success is not true. Benchmarking failed."

    vendor = data["vendor"]
    assert isinstance(vendor, str), "vendor field is not a string."
    assert len(vendor) == 12, f"vendor string should be exactly 12 characters, got {len(vendor)} ({vendor!r})."
    assert vendor != "\x00" * 12, "vendor string is all null bytes. The cpuid_vendor function was not correctly implemented."
    assert vendor == expected_vendor, \
        f"Incorrect CPU vendor: program reported {vendor!r}, but CPUID leaf 0 returned {expected_vendor!r}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
