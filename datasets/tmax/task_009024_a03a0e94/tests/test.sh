#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import shutil
import subprocess
import tempfile

PROJECT = "/home/user/repro_eval"
OUTPUT = os.path.join(PROJECT, "final_output.txt")
MAIN_RS = os.path.join(PROJECT, "src/main.rs")
EXPECTED = "-0.932909477028741"
FLOAT_LINE = re.compile(r"^[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?$")


def run(cmd, **kwargs):
    return subprocess.run(cmd, text=True, capture_output=True, timeout=120, **kwargs)


def build_and_get_binary(project, target_dir):
    result = run([
        "cargo", "build", "--quiet",
        "--manifest-path", os.path.join(project, "Cargo.toml"),
        "--target-dir", target_dir,
    ])
    assert result.returncode == 0, f"cargo build failed:\n{result.stdout}\n{result.stderr}"
    binary = os.path.join(target_dir, "debug", "repro_eval")
    assert os.path.isfile(binary), f"Compiled binary {binary} was not created"
    return binary


def execute(binary):
    result = run([binary])
    assert result.returncode == 0, f"Program failed:\n{result.stdout}\n{result.stderr}"
    output = result.stdout.strip()
    assert FLOAT_LINE.fullmatch(output), f"Program stdout is not a single floating-point number: {result.stdout!r}"
    return output


def test_final_output_exists():
    assert os.path.isfile(OUTPUT), f"Output file {OUTPUT} does not exist."


def test_final_output_content():
    with open(OUTPUT, "r") as f:
        content = f.read().strip()
    assert content == EXPECTED, f"Expected output {EXPECTED}, but got {content}. Floating point reduction order is likely still incorrect or non-deterministic."


def test_main_rs_modified_for_determinism():
    assert os.path.isfile(MAIN_RS), f"{MAIN_RS} does not exist."
    with open(MAIN_RS, "r") as f:
        content = f.read()

    # Preserve the original assertion.
    has_btree = "BTreeMap" in content
    has_sort = "sort" in content
    assert has_btree or has_sort, "src/main.rs does not appear to use BTreeMap or sorting, which is required to fix the non-deterministic reduction order."

    # The indicator must occur in Rust code rather than only in a comment.
    code = re.sub(r"/\*.*?\*/|//[^\n]*", "", content, flags=re.S)
    effective_btree = re.search(r"\bBTreeMap\b", code) is not None
    effective_sort = re.search(r"\.\s*sort[A-Za-z0-9_]*\s*\(", code) is not None
    assert effective_btree or effective_sort, "BTreeMap/sorting appears only in comments rather than executable Rust code."


def test_compiled_program_matches_file_and_is_reproducible():
    target = tempfile.mkdtemp(prefix="repro_target_")
    try:
        binary = build_and_get_binary(PROJECT, target)
        outputs = [execute(binary) for _ in range(25)]
        assert len(set(outputs)) == 1, f"Compiled program is nondeterministic: {sorted(set(outputs))}"
        assert outputs[0] == EXPECTED, f"Compiled program produced {outputs[0]}, expected {EXPECTED}"
        with open(OUTPUT, "r") as f:
            recorded = f.read().strip()
        assert recorded == outputs[0], "final_output.txt does not contain the compiled program's output"
    finally:
        shutil.rmtree(target, ignore_errors=True)


def test_program_computes_from_the_data_instead_of_printing_a_constant():
    work = tempfile.mkdtemp(prefix="repro_mutation_")
    target = tempfile.mkdtemp(prefix="repro_mutation_target_")
    try:
        shutil.copy2(os.path.join(PROJECT, "Cargo.toml"), os.path.join(work, "Cargo.toml"))
        shutil.copytree(os.path.join(PROJECT, "src"), os.path.join(work, "src"))
        mutant_main = os.path.join(work, "src", "main.rs")
        with open(mutant_main, "r") as f:
            source = f.read()

        pattern = re.compile(r'\(\s*"seq1"\s*,\s*[0-9][0-9_]*(?:\.[0-9_]*)?(?:[eE][+-]?[0-9_]+)?\s*\)')
        source, count = pattern.subn('("seq1", 1.234567890123450)', source, count=1)
        assert count == 1, "Could not locate the unchanged seq1 input needed to exercise the computation"
        with open(mutant_main, "w") as f:
            f.write(source)

        oracle_rs = os.path.join(work, "oracle.rs")
        oracle_bin = os.path.join(work, "oracle")
        with open(oracle_rs, "w") as f:
            f.write(r'''
fn main() {
    // Values in lexicographically sorted key order: seq1, seq10, seq2, ..., seq9.
    let sum: f64 = [
        1.234567890123450_f64,
        0.888888888888888_f64,
        0.987654321098765_f64,
        0.555555555555555_f64,
        0.111111111111111_f64,
        0.222222222222222_f64,
        0.333333333333333_f64,
        0.444444444444444_f64,
        0.666666666666666_f64,
        0.777777777777777_f64,
    ].iter().copied().sum();
    println!("{:.15}", sum.powf(2.5).sin());
}
''')
        compiled_oracle = run(["rustc", oracle_rs, "-O", "-o", oracle_bin])
        assert compiled_oracle.returncode == 0, compiled_oracle.stderr
        expected_mutant = execute(oracle_bin)

        binary = build_and_get_binary(work, target)
        outputs = [execute(binary) for _ in range(10)]
        assert len(set(outputs)) == 1, f"Mutated-input executions are nondeterministic: {sorted(set(outputs))}"
        assert outputs[0] == expected_mutant, (
            "Program does not recompute the result from its data in deterministic key order; "
            f"expected {expected_mutant}, got {outputs[0]}"
        )
        assert outputs[0] != EXPECTED, "Program appears to print the original answer as a constant"
    finally:
        shutil.rmtree(work, ignore_errors=True)
        shutil.rmtree(target, ignore_errors=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
