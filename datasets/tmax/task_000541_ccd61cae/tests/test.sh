#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import secrets
import subprocess
import tempfile
from pathlib import Path

import pytest

BIN_PATH = "/home/user/pipeline-parser/target/release/pipeline_parser"
PROJECT_DIR = "/home/user/pipeline-parser"
VALID_PIPELINE = "/home/user/pipelines/valid.pipeline"
CIRCULAR_PIPELINE = "/home/user/pipelines/circular.pipeline"


def run_binary(path):
    return subprocess.run(
        [BIN_PATH, str(path)], capture_output=True, text=True, timeout=15
    )


def parse_exact_output(result, expected_first, expected_second):
    assert result.returncode == 0, f"Execution failed.\nStdout: {result.stdout}\nStderr: {result.stderr}"
    lines = [line.strip() for line in result.stdout.splitlines() if line.strip()]
    assert len(lines) == 3, f"Expected exactly three non-empty output lines, got: {lines!r}"
    assert lines[0] == expected_first, f"Incorrect result line: {lines[0]!r}"
    assert lines[1] == expected_second, f"Incorrect detail line: {lines[1]!r}"
    match = re.fullmatch(r"PEAK_MEM:\s*(\d+)", lines[2])
    assert match, f"Incorrect PEAK_MEM line: {lines[2]!r}"
    peak = int(match.group(1))
    assert peak > 0, "PEAK_MEM must report actual non-zero heap allocation, not a placeholder"
    return peak


def topo_order(nodes, dependencies):
    remaining = set(nodes)
    completed = []
    completed_set = set()
    while remaining:
        ready = sorted(
            node for node in remaining
            if all(dep in completed_set for dep in dependencies[node])
        )
        assert ready, "Verifier generated an invalid DAG"
        node = ready[0]
        remaining.remove(node)
        completed.append(node)
        completed_set.add(node)
    return completed


def write_pipeline(path, declarations, dependencies):
    with open(path, "w", encoding="utf-8") as handle:
        for node in declarations:
            handle.write(f"job {node}:\n")
            handle.write("  requires: [" + ", ".join(dependencies[node]) + "]\n")


def test_binary_exists():
    assert os.path.isfile(BIN_PATH), f"Executable not found at {BIN_PATH}. Did you compile in release mode?"
    assert os.access(BIN_PATH, os.X_OK), f"File at {BIN_PATH} is not executable."


def test_valid_pipeline_output():
    result = run_binary(VALID_PIPELINE)
    assert result.returncode == 0, f"Execution failed for {VALID_PIPELINE}\nStderr: {result.stderr}"

    stdout = result.stdout
    assert "RESULT: SUCCESS" in stdout, "Missing or incorrect 'RESULT: SUCCESS' in output."
    assert "ORDER: build, lint, test, deploy" in stdout, "Missing or incorrect 'ORDER: build, lint, test, deploy' in output."
    assert re.search(r"PEAK_MEM:\s*\d+", stdout), "Missing or incorrect 'PEAK_MEM: <bytes>' format in output."


def test_circular_pipeline_output():
    result = run_binary(CIRCULAR_PIPELINE)
    assert result.returncode == 0, f"Execution failed for {CIRCULAR_PIPELINE}\nStderr: {result.stderr}"

    stdout = result.stdout
    assert "RESULT: ERROR" in stdout, "Missing or incorrect 'RESULT: ERROR' in output."
    assert "CYCLE: compile -> link -> test -> compile" in stdout, "Missing or incorrect 'CYCLE: compile -> link -> test -> compile' in output."
    assert re.search(r"PEAK_MEM:\s*\d+", stdout), "Missing or incorrect 'PEAK_MEM: <bytes>' format in output."


def test_unseen_dag_parsing_and_alphabetical_tiebreak(tmp_path):
    token = secrets.token_hex(8)
    nodes = [f"j_{token}_{letter}" for letter in "abcde"]
    a, b, c, d, e = nodes
    dependencies = {
        a: [],
        b: [],
        c: [a],
        d: [a, b],
        e: [c, d],
    }
    declarations = list(nodes)
    secrets.SystemRandom().shuffle(declarations)
    pipeline = tmp_path / "unseen_valid.pipeline"
    write_pipeline(pipeline, declarations, dependencies)

    expected = topo_order(nodes, dependencies)
    result = run_binary(pipeline)
    parse_exact_output(result, "RESULT: SUCCESS", "ORDER: " + ", ".join(expected))


def test_unseen_cycle_and_smallest_cycle_start(tmp_path):
    token = secrets.token_hex(8)
    a = f"cycle_{token}_a"
    b = f"cycle_{token}_b"
    c = f"cycle_{token}_c"
    independent = f"free_{token}"
    blocked = f"later_{token}"
    dependencies = {
        a: [b],
        b: [c],
        c: [a],
        independent: [],
        blocked: [a],
    }
    declarations = list(dependencies)
    secrets.SystemRandom().shuffle(declarations)
    pipeline = tmp_path / "unseen_circular.pipeline"
    write_pipeline(pipeline, declarations, dependencies)

    result = run_binary(pipeline)
    parse_exact_output(
        result,
        "RESULT: ERROR",
        f"CYCLE: {a} -> {b} -> {c} -> {a}",
    )


def test_peak_memory_is_allocator_derived_and_scales(tmp_path):
    small = tmp_path / "small.pipeline"
    small.write_text("job only:\n  requires: []\n", encoding="utf-8")
    small_peak = parse_exact_output(
        run_binary(small), "RESULT: SUCCESS", "ORDER: only"
    )

    count = 1200
    nodes = [f"m{i:04d}" for i in range(count)]
    large = tmp_path / "large.pipeline"
    with large.open("w", encoding="utf-8") as handle:
        for i, node in enumerate(nodes):
            dependency = "" if i == 0 else nodes[i - 1]
            handle.write(f"job {node}:\n  requires: [{dependency}]\n")
    large_peak = parse_exact_output(
        run_binary(large), "RESULT: SUCCESS", "ORDER: " + ", ".join(nodes)
    )
    assert large_peak > small_peak, (
        f"Peak heap usage did not increase for a much larger graph: "
        f"small={small_peak}, large={large_peak}"
    )


def test_custom_global_allocator_is_implemented():
    source_files = list(Path(PROJECT_DIR, "src").rglob("*.rs"))
    assert source_files, "Rust source files are missing"
    source = "\n".join(path.read_text(encoding="utf-8") for path in source_files)

    assert re.search(r"unsafe\s+impl\s+(?:std::alloc::)?GlobalAlloc", source), \
        "No custom GlobalAlloc implementation was found"
    assert re.search(r"#\s*\[\s*global_allocator\s*\]", source), \
        "The custom allocator is not installed with #[global_allocator]"
    assert re.search(r"\bSystem\b", source), "The allocator does not wrap std::alloc::System"
    assert re.search(r"\bAtomicUsize\b", source), "AtomicUsize-based allocation tracking is missing"
    assert re.search(r"fn\s+alloc\s*\(", source), "GlobalAlloc::alloc is not implemented"
    assert re.search(r"fn\s+dealloc\s*\(", source), "GlobalAlloc::dealloc is not implemented"
    assert re.search(r"fetch_add|compare_exchange|fetch_update|fetch_max", source), \
        "No atomic allocation/peak update was found"


def test_cargo_tests_pass():
    assert os.path.isdir(PROJECT_DIR), f"Rust project directory missing at {PROJECT_DIR}"
    result = subprocess.run(
        ["cargo", "test"], cwd=PROJECT_DIR, capture_output=True, text=True, timeout=180
    )
    assert result.returncode == 0, f"'cargo test' failed in {PROJECT_DIR}.\nStdout: {result.stdout}\nStderr: {result.stderr}"


def test_meaningful_integration_tests_exist():
    metadata_result = subprocess.run(
        ["cargo", "metadata", "--no-deps", "--format-version", "1"],
        cwd=PROJECT_DIR, capture_output=True, text=True, timeout=60
    )
    assert metadata_result.returncode == 0, metadata_result.stderr
    metadata = json.loads(metadata_result.stdout)
    integration_targets = []
    for package in metadata.get("packages", []):
        for target in package.get("targets", []):
            if "test" in target.get("kind", []) and "/tests/" in target.get("src_path", ""):
                integration_targets.append(target)
    assert integration_targets, "No Cargo integration-test target under tests/ was found"

    listed_tests = 0
    test_sources = []
    for target in integration_targets:
        test_sources.append(Path(target["src_path"]).read_text(encoding="utf-8"))
        result = subprocess.run(
            ["cargo", "test", "--test", target["name"], "--", "--list"],
            cwd=PROJECT_DIR, capture_output=True, text=True, timeout=180
        )
        assert result.returncode == 0, result.stderr
        listed_tests += sum(1 for line in result.stdout.splitlines() if line.rstrip().endswith(": test"))

    assert listed_tests >= 2, "At least two runnable integration tests are required"
    combined = "\n".join(test_sources).lower()
    assert "requires:" in combined, "Integration tests do not contain pipeline DSL fixtures"
    assert "cycle" in combined or "circular" in combined, "Integration tests do not exercise a circular DAG"
    assert "success" in combined or "order" in combined, "Integration tests do not exercise a valid DAG"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
