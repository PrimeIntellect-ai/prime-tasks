#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import stat
import subprocess
import tempfile
import uuid

ROOT = "/home/user/uptime_monitor"


def test_minimal_crash_txt():
    filepath = os.path.join(ROOT, "minimal_crash.txt")
    assert os.path.isfile(filepath), f"{filepath} does not exist."

    with open(filepath, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 3, f"minimal_crash.txt should contain exactly 3 lines, found {len(lines)}."

    content = " ".join(lines)
    assert "AuthService DBService" in content or "DBService AuthService" in content, "Missing AuthService/DBService link."
    assert "DBService CacheService" in content or "CacheService DBService" in content, "Missing DBService/CacheService link."
    assert "CacheService AuthService" in content or "AuthService CacheService" in content, "Missing CacheService/AuthService link."

    expected = {
        "AuthService DBService",
        "DBService CacheService",
        "CacheService AuthService",
    }
    assert set(lines) == expected, (
        "minimal_crash.txt must contain exactly the three directed dependency "
        f"lines forming the cycle; found: {lines!r}"
    )


def run_monitor(binary, config_path):
    try:
        return subprocess.run(
            [binary, config_path],
            cwd=ROOT,
            capture_output=True,
            text=True,
            timeout=5,
        )
    except subprocess.TimeoutExpired as exc:
        raise AssertionError(f"Monitor hung on {config_path}") from exc


def exercise_monitor(binary, workdir):
    token = "T" + uuid.uuid4().hex

    # A diamond-shaped DAG catches implementations that mistake any globally
    # visited node for a node on the active recursion path.
    p, q, r, s, t = [f"{token}_{x}" for x in ("P", "Q", "R", "S", "T")]
    acyclic_path = os.path.join(workdir, "acyclic.txt")
    with open(acyclic_path, "w") as f:
        f.write(f"{p} {q}\n")
        f.write(f"{p} {r}\n")
        f.write(f"{q} {s}\n")
        f.write(f"{r} {s}\n")
        f.write(f"{s} {t}\n")

    result = run_monitor(binary, acyclic_path)
    assert result.returncode == 0, (
        f"Monitor failed on an acyclic graph with exit code {result.returncode}. "
        f"stderr: {result.stderr}"
    )
    assert "CYCLE DETECTED" not in result.stdout, (
        "Monitor falsely reported a cycle in an acyclic dependency graph."
    )

    # Two independent cycles plus acyclic branches verify that recursion stops
    # on a cycle and processing continues to the remaining graph.
    a, b, c, d, e, x, y, z = [
        f"{token}_{name}" for name in ("A", "B", "C", "D", "E", "X", "Y", "Z")
    ]
    cyclic_path = os.path.join(workdir, "cycles.txt")
    with open(cyclic_path, "w") as f:
        f.write(f"{a} {b}\n")
        f.write(f"{b} {c}\n")
        f.write(f"{c} {a}\n")
        f.write(f"{a} {x}\n")
        f.write(f"{x} {y}\n")
        f.write(f"{d} {e}\n")
        f.write(f"{e} {d}\n")
        f.write(f"{d} {z}\n")

    result = run_monitor(binary, cyclic_path)
    assert result.returncode == 0, (
        f"Monitor did not exit 0 after detecting cycles; exit code "
        f"{result.returncode}, stderr: {result.stderr}"
    )

    reported = re.findall(r"^CYCLE DETECTED:\s*(\S+)\s*$", result.stdout, re.MULTILINE)
    assert reported, f"Monitor did not emit the required cycle message. stdout: {result.stdout!r}"

    first_cycle = {a, b, c}
    second_cycle = {d, e}
    actual_cycle_nodes = first_cycle | second_cycle
    assert first_cycle.intersection(reported), (
        f"Monitor failed to report the first independently generated cycle. stdout: {result.stdout!r}"
    )
    assert second_cycle.intersection(reported), (
        "Monitor stopped before processing the remaining independent cycle. "
        f"stdout: {result.stdout!r}"
    )
    assert set(reported).issubset(actual_cycle_nodes), (
        f"Monitor reported non-cyclic nodes as cycles: {set(reported) - actual_cycle_nodes}"
    )


def test_regression_script_and_execution():
    script_path = os.path.join(ROOT, "regression_test.sh")
    assert os.path.isfile(script_path), f"{script_path} does not exist."

    st = os.stat(script_path)
    assert st.st_mode & stat.S_IXUSR, f"{script_path} is not executable."

    monitor_path = os.path.join(ROOT, "monitor")
    log_path = os.path.join(ROOT, "test_result.log")
    for path in (monitor_path, log_path):
        if os.path.lexists(path):
            os.unlink(path)

    try:
        result = subprocess.run(
            [script_path], cwd=ROOT, capture_output=True, text=True, timeout=30
        )
    except subprocess.TimeoutExpired as exc:
        raise AssertionError("regression_test.sh timed out") from exc

    assert result.returncode == 0, (
        f"regression_test.sh failed with exit code {result.returncode}. stderr: {result.stderr}"
    )

    assert os.path.isfile(log_path), f"{log_path} was not created."
    with open(log_path, "r") as f:
        log_content = f.read()
    assert "CYCLE DETECTED" in log_content, (
        "test_result.log does not contain 'CYCLE DETECTED'."
    )

    assert os.path.isfile(monitor_path), (
        "regression_test.sh did not create the required monitor executable."
    )
    assert os.access(monitor_path, os.X_OK), (
        "The monitor produced by regression_test.sh is not executable."
    )
    with open(monitor_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", (
            "regression_test.sh did not produce a compiled executable named monitor."
        )

    source_path = os.path.join(ROOT, "monitor.cpp")
    assert os.path.isfile(source_path), f"{source_path} does not exist."

    with tempfile.TemporaryDirectory() as workdir:
        # Exercise the artifact produced by the submitted regression script.
        exercise_monitor(monitor_path, workdir)

        # Independently compile monitor.cpp so a script-generated fake log or
        # unrelated binary cannot conceal an unfixed source file.
        independent_binary = os.path.join(workdir, "monitor_from_source")
        compile_result = subprocess.run(
            ["g++", "-O2", source_path, "-o", independent_binary],
            cwd=ROOT,
            capture_output=True,
            text=True,
            timeout=30,
        )
        assert compile_result.returncode == 0, (
            "monitor.cpp failed independent compilation. "
            f"stderr: {compile_result.stderr}"
        )
        exercise_monitor(independent_binary, workdir)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
