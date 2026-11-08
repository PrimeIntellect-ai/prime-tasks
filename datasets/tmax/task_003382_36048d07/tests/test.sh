#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import subprocess

PROJECT = "/home/user/req_validator"


def run(cmd, **kwargs):
    return subprocess.run(cmd, capture_output=True, timeout=180, **kwargs)


def cargo_metadata():
    result = run(["cargo", "metadata", "--format-version", "1", "--no-deps"], cwd=PROJECT, text=True)
    assert result.returncode == 0, f"cargo metadata failed:\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
    metadata = json.loads(result.stdout)
    manifest = os.path.realpath(os.path.join(PROJECT, "Cargo.toml"))
    packages = [p for p in metadata["packages"] if os.path.realpath(p["manifest_path"]) == manifest]
    assert len(packages) == 1, "Could not identify the req_validator Cargo package."
    return packages[0]


def build_binary(features=None, no_default_features=False):
    cmd = ["cargo", "build", "--message-format=json"]
    if no_default_features:
        cmd.append("--no-default-features")
    if features:
        cmd += ["--features", features]
    result = run(cmd, cwd=PROJECT, text=True)
    assert result.returncode == 0, f"cargo build failed:\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
    executables = []
    for line in result.stdout.splitlines():
        try:
            message = json.loads(line)
        except json.JSONDecodeError:
            continue
        if message.get("reason") == "compiler-artifact" and message.get("executable"):
            if "bin" in message.get("target", {}).get("kind", []):
                executables.append(message["executable"])
    assert executables, "Cargo did not build a binary target."
    return executables[-1]


def expected_checksum(payload):
    value = 0
    for byte in payload:
        if byte != 0:
            value ^= byte
    return value


def parse_program_output(output, bench):
    text = output.decode("utf-8")
    lines = text.splitlines()
    expected_count = 2 if bench else 1
    assert len(lines) == expected_count, f"Unexpected program output: {text!r}"
    bench_lines = [line for line in lines if line == "Bench mode active"]
    assert len(bench_lines) == (1 if bench else 0), f"Incorrect bench-mode output: {text!r}"
    checksum_lines = [line for line in lines if re.fullmatch(r"Checksum: 0x[0-9a-fA-F]{2}", line)]
    assert len(checksum_lines) == 1, f"Incorrect checksum formatting: {text!r}"
    return int(checksum_lines[0][-2:], 16)


def test_project_directory_exists():
    assert os.path.isdir(PROJECT), "Project directory /home/user/req_validator does not exist."
    assert os.path.isfile(os.path.join(PROJECT, "Cargo.toml")), "Cargo.toml is missing."
    assert os.path.isfile(os.path.join(PROJECT, "src/lib.rs")), "src/lib.rs is missing."
    assert os.path.isfile(os.path.join(PROJECT, "src/main.rs")), "src/main.rs is missing."


def test_cargo_toml_contents():
    with open(os.path.join(PROJECT, "Cargo.toml"), "r") as f:
        content = f.read()
    assert "proptest" in content, "proptest is not in Cargo.toml."
    assert "bench_mode" in content, "bench_mode feature is not in Cargo.toml."

    package = cargo_metadata()
    assert "bench_mode" in package.get("features", {}), "bench_mode is not a declared Cargo feature."
    assert any(dep.get("name") == "proptest" and dep.get("kind") == "dev" for dep in package.get("dependencies", [])), \
        "proptest is not an actual dev-dependency."


def test_lib_rs_contents():
    with open(os.path.join(PROJECT, "src/lib.rs"), "r") as f:
        content = f.read()
    assert "proptest_checksum_property" in content, "proptest_checksum_property test is not defined in src/lib.rs."
    assert re.search(r"proptest\s*!", content), "src/lib.rs does not use the proptest! macro."


def test_compute_checksum_directly():
    package = cargo_metadata()
    lib_targets = [t for t in package.get("targets", []) if "lib" in t.get("kind", [])]
    assert lib_targets, "The package has no library target."
    crate_name = lib_targets[0]["name"].replace("-", "_")
    assert re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", crate_name), "Invalid library crate name."

    tests_dir = os.path.join(PROJECT, "tests")
    os.makedirs(tests_dir, exist_ok=True)
    test_path = os.path.join(tests_dir, "__verifier_checksum.rs")
    source = f'''use {crate_name}::compute_checksum;

#[test]
fn verifier_checksum_cases() {{
    let mut cases: Vec<Vec<u8>> = vec![
        vec![], vec![0], vec![0, 0, 0], vec![1], vec![0, 1, 0],
        b"HelloRust".to_vec(), vec![0xff, 0x80, 0, 0x7f, 0x80],
    ];
    for b in 0u8..=255 {{ cases.push(vec![b]); }}
    let mut state: u32 = 0x91c4a72d;
    for len in 0..129usize {{
        let mut payload = Vec::new();
        for i in 0..len {{
            state = state.wrapping_mul(1664525).wrapping_add(1013904223);
            let byte = if i % 7 == 0 {{ 0 }} else {{ (state >> 24) as u8 }};
            payload.push(byte);
        }}
        cases.push(payload);
    }}
    for payload in cases {{
        let expected = payload.iter().filter(|&&b| b != 0).fold(0u8, |acc, &b| acc ^ b);
        let actual = compute_checksum(&payload);
        assert_eq!(actual, expected, "wrong checksum for {{payload:?}}");
        let mut combined = payload.clone();
        combined.push(actual);
        assert_eq!(compute_checksum(&combined), 0, "checksum property failed for {{payload:?}}");
    }}
}}
'''
    try:
        with open(test_path, "w") as f:
            f.write(source)
        result = run(["cargo", "test", "--test", "__verifier_checksum"], cwd=PROJECT, text=True)
        assert result.returncode == 0, f"Independent checksum tests failed:\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
    finally:
        if os.path.exists(test_path):
            os.remove(test_path)


def test_declared_property_test_executes():
    result = run(["cargo", "test", "proptest_checksum_property", "--", "--nocapture"], cwd=PROJECT, text=True)
    output = result.stdout + "\n" + result.stderr
    assert result.returncode == 0, f"Property test failed:\n{output}"
    assert re.search(r"test\s+.*proptest_checksum_property.*\.\.\.\s+ok", output), \
        "No runnable passing test named proptest_checksum_property was found."


def test_binary_behavior_and_bench_output():
    bench_binary = build_binary(features="bench_mode")
    payloads = [b"HelloRust", b"", b"A\x00B", b"qa-Validation-927", b"\x00\x00Rust\x00"]
    hello_output = None
    for payload in payloads:
        result = run([bench_binary], input=payload)
        assert result.returncode == 0, f"bench_mode binary failed: {result.stderr.decode(errors='replace')}"
        assert parse_program_output(result.stdout, True) == expected_checksum(payload)
        if payload == b"HelloRust":
            hello_output = result.stdout

    output_path = "/home/user/bench_output.txt"
    assert os.path.isfile(output_path), "/home/user/bench_output.txt is missing."
    with open(output_path, "rb") as f:
        saved = f.read()
    assert b"Bench mode active" in saved, "'Bench mode active' not found in bench_output.txt."
    assert re.search(rb"Checksum:\s*0x62", saved, re.IGNORECASE), "'Checksum: 0x62' not found in bench_output.txt."
    assert saved == hello_output, "bench_output.txt is not the actual bench_mode output for the exact input HelloRust."

    normal_binary = build_binary(no_default_features=True)
    for payload in [b"HelloRust", b"different input", b"N\x00UL"]:
        result = run([normal_binary], input=payload)
        assert result.returncode == 0, f"normal binary failed: {result.stderr.decode(errors='replace')}"
        assert parse_program_output(result.stdout, False) == expected_checksum(payload)


def test_cargo_test_passes():
    result = run(["cargo", "test"], cwd=PROJECT, text=True)
    assert result.returncode == 0, f"cargo test failed:\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
