#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import shutil
import subprocess
import tempfile

SYS_DIR = "/home/user/sysmon"


def run_cargo(args, timeout=180):
    return subprocess.run(
        ["cargo"] + args,
        cwd=SYS_DIR,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=timeout,
    )


def test_extracted_payloads():
    path = "/home/user/extracted_payloads.txt"
    assert os.path.isfile(path), f"File {path} does not exist"

    with open(path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert "ff0a0b" in lines, "Payload 'ff0a0b' is missing from extracted_payloads.txt"
    assert "ff112233" in lines, "Payload 'ff112233' is missing from extracted_payloads.txt"
    assert len(lines) == 2, f"Expected exactly 2 payloads, found {len(lines)}"

    with open("/home/user/crash.log", "r") as f:
        expected = re.findall(r"Panic triggered by input:\s*([0-9A-Fa-f]+)", f.read())
    assert lines == expected, f"Extracted payloads do not exactly match crash.log: {lines!r} != {expected!r}"


def test_regression_test_exists_and_valid():
    path = "/home/user/sysmon/tests/regression.rs"
    assert os.path.isfile(path), f"Regression test file {path} does not exist"

    with open(path, "r") as f:
        content = f.read()

    assert "test_fuzzer_crashes" in content, "Function 'test_fuzzer_crashes' not found in regression.rs"
    assert "sysmon::process_input" in content or "process_input" in content, "Call to process_input not found in regression.rs"


def test_lib_rs_panic_removed():
    path = "/home/user/sysmon/src/lib.rs"
    assert os.path.isfile(path), f"File {path} does not exist"

    with open(path, "r") as f:
        content = f.read()

    assert "panic!" not in content, "panic! macro is still present in src/lib.rs"
    assert "Err(" in content, "Expected an Err return variant in src/lib.rs"


def test_build_rs_fixed():
    path = "/home/user/sysmon/build.rs"
    assert os.path.isfile(path), f"File {path} does not exist"

    with open(path, "r") as f:
        content = f.read()

    assert "cargo:rustc-link-search" in content, "build.rs is missing the cargo:rustc-link-search directive"

    clean = run_cargo(["clean"])
    assert clean.returncode == 0, f"cargo clean failed:\n{clean.stdout}\n{clean.stderr}"
    build = run_cargo(["build", "-vv"])
    output = build.stdout + "\n" + build.stderr
    assert build.returncode == 0, f"cargo build failed:\n{output}"
    assert re.search(r"cargo:rustc-link-search=native=(?:/home/user/sysmon/)?lib(?:\s|$)", output), \
        "build.rs did not emit an active native library search path for the project's lib directory"


def test_cargo_test_passes():
    assert os.path.isdir(SYS_DIR), f"Directory {SYS_DIR} does not exist"
    result = run_cargo(["test"])
    assert result.returncode == 0, f"cargo test failed:\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"


def test_process_input_behavior():
    test_path = os.path.join(SYS_DIR, "tests", "verifier_behavior.rs")
    previous = None
    if os.path.exists(test_path):
        with open(test_path, "rb") as f:
            previous = f.read()

    source = r'''
use sysmon::process_input;

#[test]
fn verifier_checks_parser_behavior() {
    assert_eq!(process_input(&[0xff, 0x0a, 0x0b]), Err("Invalid header"));
    assert_eq!(process_input(&[0xff, 0x11, 0x22, 0x33]), Err("Invalid header"));
    assert_eq!(process_input(&[]), Ok(0));
    assert_eq!(process_input(&[0x01, 0x02, 0x03]), Ok(3));
}
'''
    try:
        with open(test_path, "w") as f:
            f.write(source)
        result = run_cargo(["test", "--test", "verifier_behavior"])
        assert result.returncode == 0, \
            f"process_input does not have the required behavior:\n{result.stdout}\n{result.stderr}"
    finally:
        if previous is None:
            if os.path.exists(test_path):
                os.remove(test_path)
        else:
            with open(test_path, "wb") as f:
                f.write(previous)


def _spy_source(error_text):
    return f'''
use std::fmt::Write as FmtWrite;
use std::io::Write as IoWrite;

pub fn process_input(data: &[u8]) -> Result<i32, &'static str> {{
    let mut encoded = String::new();
    for byte in data {{
        write!(&mut encoded, "{{:02x}}", byte).unwrap();
    }}
    let mut file = std::fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open("/tmp/sysmon_regression_calls.txt")
        .unwrap();
    writeln!(&mut file, "{{}}", encoded).unwrap();

    if data == [0xffu8, 0x0a, 0x0b].as_slice()
        || data == [0xffu8, 0x11, 0x22, 0x33].as_slice()
    {{
        Err("{error_text}")
    }} else {{
        Ok(data.len() as i32)
    }}
}}
'''


def test_regression_test_exercises_payloads_and_error():
    lib_path = os.path.join(SYS_DIR, "src", "lib.rs")
    calls_path = "/tmp/sysmon_regression_calls.txt"
    with open(lib_path, "rb") as f:
        original = f.read()

    try:
        listed = run_cargo(["test", "--test", "regression", "--", "--list"])
        assert listed.returncode == 0, f"Regression test target does not compile:\n{listed.stdout}\n{listed.stderr}"
        assert re.search(r"^test_fuzzer_crashes:\s+test$", listed.stdout, re.MULTILINE), \
            "regression.rs does not define an executable #[test] named test_fuzzer_crashes"

        if os.path.exists(calls_path):
            os.remove(calls_path)
        with open(lib_path, "w") as f:
            f.write(_spy_source("Invalid header"))
        valid = run_cargo(["test", "--test", "regression", "test_fuzzer_crashes", "--", "--exact"])
        assert valid.returncode == 0, \
            f"Regression test fails when process_input has the required behavior:\n{valid.stdout}\n{valid.stderr}"
        assert os.path.isfile(calls_path), "Regression test did not call sysmon::process_input"
        with open(calls_path, "r") as f:
            calls = [line.strip() for line in f if line.strip()]
        assert "ff0a0b" in calls, "Regression test did not pass decoded payload ff0a0b to process_input"
        assert "ff112233" in calls, "Regression test did not pass decoded payload ff112233 to process_input"

        with open(lib_path, "w") as f:
            f.write(_spy_source("WRONG ERROR"))
        wrong = run_cargo(["test", "--test", "regression", "test_fuzzer_crashes", "--", "--exact"])
        assert wrong.returncode != 0, \
            "Regression test passed when process_input returned the wrong error; it must assert Err(\"Invalid header\")"
    finally:
        with open(lib_path, "wb") as f:
            f.write(original)
        if os.path.exists(calls_path):
            os.remove(calls_path)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
