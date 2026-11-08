#!/bin/bash
set +e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import signal
import subprocess
import tempfile
from pathlib import Path

import pytest

PROJECT_DIR = Path("/home/user/log-tracer")
MAIN_RS = PROJECT_DIR / "src/main.rs"
BINARY = PROJECT_DIR / "target/debug/log-tracer"


def run_with_timeout(args, cwd=None, timeout=30):
    proc = subprocess.Popen(
        args,
        cwd=cwd,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        start_new_session=True,
    )
    try:
        stdout, stderr = proc.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        os.killpg(proc.pid, signal.SIGKILL)
        stdout, stderr = proc.communicate()
        pytest.fail(
            f"Command timed out after {timeout}s: {' '.join(map(str, args))}\n"
            f"STDOUT:\n{stdout}\nSTDERR:\n{stderr}"
        )
    return subprocess.CompletedProcess(args, proc.returncode, stdout, stderr)


def oracle_count(start_file):
    to_visit = [Path(start_file).resolve()]
    visited = set()
    total = 0

    while to_visit:
        current = to_visit.pop()
        normalized = current.resolve()
        if normalized in visited:
            continue
        visited.add(normalized)

        try:
            lines = current.read_text().splitlines()
        except OSError:
            lines = []

        for line in lines:
            if "ERROR" in line:
                total += 1
            elif line.startswith("[TRACE: ") and line.endswith("]"):
                to_visit.append((current.parent / line[8:-1]).resolve())

    return total


def parse_integer_output(result):
    assert result.returncode == 0, (
        f"Binary failed with exit code {result.returncode}.\n"
        f"STDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
    )
    output = result.stdout.strip()
    assert output.isdigit(), f"Expected a single non-negative integer, got {output!r}."
    return int(output)


def test_error_count_file():
    error_count_path = "/home/user/error_count.txt"
    assert os.path.isfile(error_count_path), f"File {error_count_path} does not exist."

    with open(error_count_path, "r") as f:
        content = f.read().strip()

    assert content == "4", f"Expected error count to be '4', but got '{content}'."


def test_cargo_test_passes_and_count_errors_handles_a_cycle():
    assert PROJECT_DIR.is_dir(), f"Directory {PROJECT_DIR} does not exist."
    assert MAIN_RS.is_file(), f"File {MAIN_RS} does not exist."

    original = MAIN_RS.read_text()
    verifier_test = r'''

#[cfg(test)]
mod verifier_behavior_tests {
    use super::*;
    use std::time::{SystemTime, UNIX_EPOCH};

    #[test]
    fn verifier_count_errors_on_circular_trace() {
        let unique = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let dir = std::env::temp_dir().join(format!(
            "log_tracer_verifier_{}_{}", std::process::id(), unique
        ));
        std::fs::create_dir_all(&dir).unwrap();
        let a = dir.join("a.log");
        let b = dir.join("b.log");
        std::fs::write(
            &a,
            "INFO a\nERROR a failed\n[TRACE: b.log]\n[TRACE: b.log]\n",
        ).unwrap();
        std::fs::write(
            &b,
            "ERROR b failed once\nERROR b failed twice\n[TRACE: a.log]\n",
        ).unwrap();

        assert_eq!(count_errors(&a), 3);
        let _ = std::fs::remove_dir_all(&dir);
    }
}
'''

    try:
        MAIN_RS.write_text(original + verifier_test)
        result = run_with_timeout(
            ["cargo", "test"], cwd=str(PROJECT_DIR), timeout=45
        )
    finally:
        MAIN_RS.write_text(original)

    assert result.returncode == 0, (
        f"cargo test failed:\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
    )


def test_repaired_binary_on_production_and_generated_circular_logs():
    build = run_with_timeout(
        ["cargo", "build", "--bin", "log-tracer"],
        cwd=str(PROJECT_DIR),
        timeout=45,
    )
    assert build.returncode == 0, (
        f"cargo build failed:\nSTDOUT:\n{build.stdout}\nSTDERR:\n{build.stderr}"
    )
    assert BINARY.is_file(), f"Compiled binary {BINARY} does not exist."
    assert os.access(BINARY, os.X_OK), f"Compiled artifact {BINARY} is not executable."

    production = Path("/home/user/logs/master.log")
    expected_production = oracle_count(production)
    production_run = run_with_timeout(
        [str(BINARY), str(production)], timeout=5
    )
    assert parse_integer_output(production_run) == expected_production
    assert expected_production == 4, "The production log set no longer has the expected contents."

    with tempfile.TemporaryDirectory(prefix="log-tracer-verifier-") as temp_dir:
        root = Path(temp_dir)
        first = root / "first.log"
        second = root / "second.log"
        third = root / "third.log"

        first.write_text(
            "ERROR first\n[TRACE: second.log]\n[TRACE: second.log]\n"
        )
        second.write_text(
            "ERROR second one\nERROR second two\n[TRACE: third.log]\n"
        )
        third.write_text(
            "INFO third\nERROR third\n[TRACE: first.log]\n"
        )

        expected = oracle_count(first)
        assert expected == 4
        circular_run = run_with_timeout(
            [str(BINARY), str(first)], timeout=5
        )
        assert parse_integer_output(circular_run) == expected


def test_circular_trace_exists():
    main_rs_path = "/home/user/log-tracer/src/main.rs"
    assert os.path.isfile(main_rs_path), f"File {main_rs_path} does not exist."

    with open(main_rs_path, "r") as f:
        content = f.read()

    assert "test_circular_trace" in content, "The regression test 'test_circular_trace' was not found in main.rs."
    assert "#[test]" in content, "No #[test] attribute found in main.rs."


def test_fix_implemented():
    main_rs_path = "/home/user/log-tracer/src/main.rs"
    with open(main_rs_path, "r") as f:
        content = f.read()

    has_hashset = "HashSet" in content
    has_btreeset = "BTreeSet" in content
    has_visited = "visited" in content.lower()
    has_canonicalize = "canonicalize" in content

    assert any([has_hashset, has_btreeset, has_visited, has_canonicalize]), \
        "Could not find evidence of a visited files tracking mechanism (e.g., HashSet, canonicalize, or 'visited' variable) in main.rs."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
