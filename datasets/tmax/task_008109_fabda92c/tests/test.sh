#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess
import textwrap
import uuid

PROJECT = "/home/user/storage-node"
EXPECTED_MAIN = '''mod models;
use models::{DataBlockV1, DataBlockV2};

fn process_legacy_block(v1: DataBlockV1) -> DataBlockV2 {
    // This requires From<DataBlockV1> for DataBlockV2 to be implemented
    DataBlockV2::from(v1)
}

fn main() {
    let v1 = DataBlockV1 {
        id: 101,
        payload: vec![10, 20, 30], // XOR sum: 10 ^ 20 ^ 30 = 00001010 ^ 00010100 = 00011110 (30) ^ 30 = 0
    };

    let v2 = process_legacy_block(v1);

    if v2.is_valid() {
        println!("Migration and validation successful for block {}", v2.id);
    } else {
        println!("Validation failed!");
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_migration_and_checksum() {
        let v1 = DataBlockV1 {
            id: 42,
            payload: vec![1, 2, 3, 4, 5], // 1^2^3^4^5 = 1
        };
        let v2: DataBlockV2 = v1.into();
        assert_eq!(v2.id, 42);
        assert_eq!(v2.checksum, 1);
        assert!(v2.is_valid());
    }

    #[test]
    fn test_invalid_block() {
        let mut v2 = DataBlockV2 {
            id: 43,
            payload: vec![1, 2, 3],
            checksum: 0,
        };
        // 1^2^3 = 0, so initially valid
        assert!(v2.is_valid());
        // Mutate payload to simulate corruption
        v2.payload[0] = 99;
        assert!(!v2.is_valid());
    }
}
'''


def run(command, **kwargs):
    return subprocess.run(command, capture_output=True, text=True, **kwargs)


def test_main_rs_was_not_modified():
    main_path = os.path.join(PROJECT, "src", "main.rs")
    with open(main_path, "r", encoding="utf-8") as f:
        actual = f.read()
    assert actual == EXPECTED_MAIN, "src/main.rs was modified, but the instruction forbids modifying it"


def test_storage_node_builds():
    assert os.path.isdir(PROJECT), f"Project directory {PROJECT} does not exist"
    build_result = run(["cargo", "build"], cwd=PROJECT)
    assert build_result.returncode == 0, f"Cargo build failed:\n{build_result.stderr}"


def test_storage_node_tests_pass():
    test_result = run(["cargo", "test"], cwd=PROJECT)
    assert test_result.returncode == 0, f"Cargo test failed:\n{test_result.stderr}\n{test_result.stdout}"


def test_migration_and_validation_behavior_independently():
    cases = [
        (0, []),
        (7, [255]),
        (42, [1, 2, 3, 4, 5]),
        (101, [10, 20, 30]),
        (4294967295, [0, 17, 17, 128, 3, 250]),
        (9001, list(range(32))),
    ]
    checks = []
    for index, (block_id, payload) in enumerate(cases):
        checksum = 0
        for byte in payload:
            checksum ^= byte
        values = ", ".join(str(byte) for byte in payload)
        checks.append(f'''
        let original_{index}: Vec<u8> = vec![{values}];
        let converted_{index}: DataBlockV2 = DataBlockV1 {{
            id: {block_id}u32,
            payload: original_{index}.clone(),
        }}.into();
        assert_eq!(converted_{index}.id, {block_id}u32);
        assert_eq!(converted_{index}.payload, original_{index});
        assert_eq!(converted_{index}.checksum, {checksum}u8);
        assert!(converted_{index}.is_valid());
        let invalid_{index} = DataBlockV2 {{
            id: converted_{index}.id,
            payload: converted_{index}.payload.clone(),
            checksum: converted_{index}.checksum ^ 0x80,
        }};
        assert!(!invalid_{index}.is_valid());
        ''')

    source = textwrap.dedent('''
        #[path = "../models.rs"]
        mod models;
        use models::{DataBlockV1, DataBlockV2};

        fn main() {
    ''') + "\n".join(checks) + textwrap.dedent('''
        }
    ''')

    bin_dir = os.path.join(PROJECT, "src", "bin")
    os.makedirs(bin_dir, exist_ok=True)
    bin_name = "verifier_probe_" + uuid.uuid4().hex
    probe_path = os.path.join(bin_dir, bin_name + ".rs")
    try:
        with open(probe_path, "w", encoding="utf-8") as f:
            f.write(source)
        result = run(["cargo", "run", "--quiet", "--bin", bin_name], cwd=PROJECT)
        assert result.returncode == 0, (
            "Independent migration/checksum checks failed:\n"
            + result.stdout + "\n" + result.stderr
        )
    finally:
        if os.path.exists(probe_path):
            os.remove(probe_path)
        try:
            os.rmdir(bin_dir)
        except OSError:
            pass


def test_ci_workflow_exists_and_valid():
    ci_path = os.path.join(PROJECT, ".github", "workflows", "ci.yml")
    assert os.path.isfile(ci_path), f"CI workflow file not found at {ci_path}"
    with open(ci_path, "r", encoding="utf-8") as f:
        ci_content = f.read()

    # Preserve the original checks.
    assert "cargo build" in ci_content, "CI workflow is missing 'cargo build' command"
    assert "cargo test" in ci_content, "CI workflow is missing 'cargo test' command"
    assert "ubuntu-latest" in ci_content, "CI workflow is missing 'ubuntu-latest' specification"

    uncommented = "\n".join(line.split("#", 1)[0] for line in ci_content.splitlines())
    assert re.search(r"(?m)^\s*runs-on\s*:\s*ubuntu-latest\s*$", uncommented), \
        "CI workflow must configure a job with runs-on: ubuntu-latest"
    assert re.search(r"(?m)^\s*-?\s*run\s*:\s*(?:[^\n]*&&\s*)?cargo\s+build(?:\s|$)", uncommented), \
        "CI workflow must contain a step that runs cargo build"
    assert re.search(r"(?m)^\s*-?\s*run\s*:\s*(?:[^\n]*&&\s*)?cargo\s+test(?:\s|$)", uncommented), \
        "CI workflow must contain a step that runs cargo test"

    lines = [(len(line) - len(line.lstrip()), line.strip())
             for line in uncommented.splitlines() if line.strip()]
    trigger_ok = False

    # Accept the normal block form: on -> push -> branches -> main.
    for i, (on_indent, text) in enumerate(lines):
        if not re.fullmatch(r"(?:on|'on'|\"on\")\s*:\s*", text):
            continue
        end = next((j for j in range(i + 1, len(lines)) if lines[j][0] <= on_indent), len(lines))
        for j in range(i + 1, end):
            push_indent, push_text = lines[j]
            if re.fullmatch(r"(?:push|'push'|\"push\")\s*:\s*", push_text):
                push_end = next((k for k in range(j + 1, end) if lines[k][0] <= push_indent), end)
                for k in range(j + 1, push_end):
                    branch_indent, branch_text = lines[k]
                    match = re.fullmatch(r"branches\s*:\s*(.*)", branch_text)
                    if not match:
                        continue
                    value = match.group(1).strip()
                    if value and re.search(r"(?:^|[\[,'\"\s])main(?:$|[\],'\"\s])", value):
                        trigger_ok = True
                    branch_end = next((n for n in range(k + 1, push_end)
                                       if lines[n][0] <= branch_indent), push_end)
                    if any(re.fullmatch(r"-\s*['\"]?main['\"]?", lines[n][1])
                           for n in range(k + 1, branch_end)):
                        trigger_ok = True

    # Also accept a valid compact flow-style trigger.
    compact = re.sub(r"\s+", "", uncommented).replace("'", "").replace('"', '')
    if re.search(r"on:\{[^}]*push:\{[^}]*branches:\[[^]]*(?:^|,)main(?:,|\])", compact):
        trigger_ok = True

    assert trigger_ok, "CI workflow must trigger on push to the main branch"


def test_success_log_output_matches_executed_binary():
    log_path = "/home/user/success.log"
    assert os.path.isfile(log_path), f"Log file not found at {log_path}"
    with open(log_path, "r", encoding="utf-8") as f:
        log_content = f.read()

    expected_string = "Migration and validation successful for block 101"
    assert expected_string in log_content, f"Expected '{expected_string}' in {log_path}, but got:\n{log_content}"

    run_result = run(["cargo", "run", "--quiet", "--bin", "storage-node"], cwd=PROJECT)
    assert run_result.returncode == 0, f"Project binary failed:\n{run_result.stderr}"
    assert run_result.stdout == log_content, \
        "success.log does not exactly match the standard output of the project binary"
    assert run_result.stdout.strip() == expected_string, \
        f"Unexpected project output: {run_result.stdout!r}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
