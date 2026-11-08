#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import tempfile
import uuid
import pytest

REPO = "/home/user/service_repo"
MANIFEST = os.path.join(REPO, "Cargo.toml")
RECOVERED = "/home/user/recovered_requests.log"
MINIMAL = "/home/user/minimal_crash.txt"
OUTPUT = "/home/user/processor_output.txt"

EXPECTED_RECOVERED = """REQ A
REQ B
PROCESS_WINDOW
REQ C
REQ D
REQ E
PROCESS_WINDOW
REQ F
REQ G
REQ H
REQ I
PROCESS_WINDOW
"""

VULNERABLE_SOURCE = r'''
use std::env;
use std::fs;

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() < 2 {
        eprintln!("Usage: processor <log_file>");
        std::process::exit(1);
    }

    let content = fs::read_to_string(&args[1]).expect("Failed to read file");
    let mut buffer = Vec::new();
    let mut processed_count = 0;

    for line in content.lines() {
        let line = line.trim();
        if line.is_empty() { continue; }

        if line.starts_with("REQ") {
            buffer.push(line);
        } else if line == "PROCESS_WINDOW" {
            let mut i = 0;
            while i <= buffer.len() {
                let chunk_end = i + 3;
                if chunk_end > buffer.len() {
                    break;
                }
                let _chunk = &buffer[i..=chunk_end];
                processed_count += 3;
                i += 3;
            }
            buffer.clear();
        }
    }
    println!("Processed: {}", processed_count);
}
'''


def run_fixed(path):
    return subprocess.run(
        ["cargo", "run", "--quiet", "--release", "--manifest-path", MANIFEST, "--", path],
        cwd=REPO,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )


@pytest.fixture(scope="session")
def vulnerable_binary(tmp_path_factory):
    directory = tmp_path_factory.mktemp("vulnerable_processor")
    source = directory / "main.rs"
    binary = directory / "processor_vulnerable"
    source.write_text(VULNERABLE_SOURCE)
    result = subprocess.run(
        ["rustc", str(source), "-o", str(binary)],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, result.stderr
    return str(binary)


def run_vulnerable(binary, lines, tmp_path, name):
    path = tmp_path / name
    path.write_text("\n".join(lines) + "\n")
    return subprocess.run(
        [binary, str(path)],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )


def test_recovered_requests_log():
    assert os.path.isfile(RECOVERED), f"File {RECOVERED} does not exist."
    with open(RECOVERED, "r") as f:
        content = f.read()
    assert content.strip() == EXPECTED_RECOVERED.strip(), \
        f"Content of {RECOVERED} does not match the expected recovered logs."


def test_minimal_crash_txt(vulnerable_binary, tmp_path):
    assert os.path.isfile(MINIMAL), f"File {MINIMAL} does not exist."
    with open(MINIMAL, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(lines) == 4, f"{MINIMAL} should contain exactly 4 lines."
    req_count = sum(1 for line in lines if line.startswith("REQ"))
    process_count = sum(1 for line in lines if line == "PROCESS_WINDOW")
    assert req_count == 3, "Minimal crash file should contain exactly 3 REQ lines."
    assert process_count == 1, "Minimal crash file should contain exactly 1 PROCESS_WINDOW line."
    assert lines[-1] == "PROCESS_WINDOW", \
        "The last line of the minimal crash file should be PROCESS_WINDOW."

    recovered_lines = [line.strip() for line in EXPECTED_RECOVERED.splitlines() if line.strip()]
    pos = 0
    for line in lines:
        try:
            pos = recovered_lines.index(line, pos) + 1
        except ValueError:
            pytest.fail("minimal_crash.txt is not a subsequence of recovered_requests.log")

    crashed = run_vulnerable(vulnerable_binary, lines, tmp_path, "minimal.log")
    assert crashed.returncode != 0, "minimal_crash.txt does not crash the vulnerable service"
    assert "panicked" in crashed.stderr.lower(), \
        f"The vulnerable service failed without a Rust panic: {crashed.stderr}"

    for removed in range(len(lines)):
        subset = lines[:removed] + lines[removed + 1:]
        result = run_vulnerable(vulnerable_binary, subset, tmp_path, f"subset_{removed}.log")
        assert result.returncode == 0, \
            f"Removing line {removed + 1} still causes a crash, so the sequence is not minimal"

    recovered_result = run_vulnerable(
        vulnerable_binary, recovered_lines, tmp_path, "recovered_vulnerable.log"
    )
    assert recovered_result.returncode != 0
    assert "panicked" in recovered_result.stderr.lower()


def test_rust_bug_fixed():
    main_rs = os.path.join(REPO, "src/main.rs")
    assert os.path.isfile(main_rs), f"File {main_rs} does not exist."
    with open(main_rs, "r") as f:
        content = f.read()

    assert "&buffer[i..=chunk_end]" not in content, \
        "The off-by-one bug (&buffer[i..=chunk_end]) is still present in src/main.rs."
    assert "&buffer[i..chunk_end]" in content, \
        "The fix (&buffer[i..chunk_end]) was not found in src/main.rs."

    built = subprocess.run(
        ["cargo", "build", "--quiet", "--release", "--manifest-path", MANIFEST],
        cwd=REPO,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=60,
    )
    assert built.returncode == 0, f"The fixed Rust service does not compile:\n{built.stderr}"


def test_processor_output():
    assert os.path.isfile(OUTPUT), f"File {OUTPUT} does not exist."
    with open(OUTPUT, "r") as f:
        content = f.read()

    assert "Processed: 6" in content, \
        f"Expected 'Processed: 6' in {OUTPUT}, but got: {content}"

    result = run_fixed(RECOVERED)
    assert result.returncode == 0, f"Fixed processor crashed on recovered log:\n{result.stderr}"
    assert result.stdout == "Processed: 6\n", \
        f"Fixed processor produced incorrect output: {result.stdout!r}"
    assert content == result.stdout, \
        "processor_output.txt is not the standard output produced by the fixed processor"


def test_fixed_processor_on_derived_inputs(tmp_path):
    nonce = uuid.uuid4().hex
    cases = [
        (["PROCESS_WINDOW"], 0),
        ([f"REQ {nonce}-a", f"REQ {nonce}-b", f"REQ {nonce}-c", "PROCESS_WINDOW"], 3),
        ([f"REQ {nonce}-{i}" for i in range(4)] + ["PROCESS_WINDOW"], 3),
        ([f"REQ {nonce}-{i}" for i in range(9)] + ["PROCESS_WINDOW"], 9),
        ([f"REQ {nonce}-x", f"REQ {nonce}-y", "PROCESS_WINDOW", "IGNORED",
          f"REQ {nonce}-{i}" for i in range(6)] + ["PROCESS_WINDOW"], 6),
    ]

    for index, (lines, expected) in enumerate(cases):
        path = tmp_path / f"case_{index}.log"
        path.write_text("\n".join(lines) + "\n")
        result = run_fixed(str(path))
        assert result.returncode == 0, \
            f"Fixed processor crashed on derived case {index}:\n{result.stderr}"
        assert result.stdout == f"Processed: {expected}\n", \
            f"Incorrect result for derived case {index}: {result.stdout!r}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
