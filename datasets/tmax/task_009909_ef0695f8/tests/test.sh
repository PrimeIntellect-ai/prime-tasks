#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import random
import re
import subprocess
import time
import uuid

HOME = "/home/user"
CI = os.path.join(HOME, "ci.sh")
SOURCE = os.path.join(HOME, "builder.go")
BUILDER = os.path.join(HOME, "builder")
GRAPH = os.path.join(HOME, "polygraph.txt")
LOG = os.path.join(HOME, "build_log.txt")
MEM = os.path.join(HOME, "mem.prof")


def run(cmd, **kwargs):
    kwargs.setdefault("cwd", HOME)
    kwargs.setdefault("capture_output", True)
    kwargs.setdefault("text", True)
    kwargs.setdefault("timeout", 60)
    return subprocess.run(cmd, **kwargs)


def read_lines():
    assert os.path.exists(LOG), f"{LOG} does not exist"
    with open(LOG, "r", encoding="utf-8") as f:
        return [line.strip() for line in f if line.strip()]


def assert_valid_profile(path, binary):
    assert os.path.isfile(path), f"profile {path} was not created"
    assert os.path.getsize(path) > 32, f"profile {path} is empty or invalid"
    result = run(["go", "tool", "pprof", "-raw", binary, path])
    assert result.returncode == 0, (
        f"go tool pprof could not read {path}: {result.stderr}"
    )
    return result.stdout + result.stderr


def test_complete_orchestrator():
    # Preserve the original existence and executable checks.
    assert os.path.exists(CI), f"{CI} does not exist"
    assert os.access(CI, os.X_OK), f"{CI} is not executable"
    assert os.path.isfile(SOURCE), f"{SOURCE} does not exist"

    # Restore and exercise the original fixture rather than trusting artifacts
    # that may have been left by the submission.
    with open(GRAPH, "w", encoding="utf-8") as f:
        f.write(
            "init : : 2 * 3 + 4\n"
            "build_db : init : 10 - 2 * 3\n"
            "build_web : init : 15 / 3 + 1\n"
            "link_all : build_db,build_web : 8 + 2 * 2\n"
        )

    for path in [BUILDER, MEM, LOG]:
        try:
            os.remove(path)
        except FileNotFoundError:
            pass
    for path in glob.glob(os.path.join(HOME, "*.prof")):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    result = run([CI])
    assert result.returncode == 0, (
        f"ci.sh failed with return code {result.returncode} and error: {result.stderr}"
    )

    # Preserve the original artifact assertions and ensure builder really is a
    # compiled executable rather than a script or placeholder.
    assert os.path.exists(BUILDER), "/home/user/builder executable not created"
    assert os.access(BUILDER, os.X_OK), "/home/user/builder is not executable"
    with open(BUILDER, "rb") as f:
        assert f.read(4) == b"\x7fELF", "/home/user/builder is not a compiled executable"
    assert os.path.exists(MEM), "/home/user/mem.prof not created"
    assert os.path.exists(LOG), "/home/user/build_log.txt not created"

    lines = read_lines()
    assert len(lines) == 8, f"Expected exactly 8 lines in build_log.txt, got {len(lines)}"
    assert lines[0] == "START init 10", f"First line must be 'START init 10', got '{lines[0]}'"
    assert lines[1] == "DONE init", f"Second line must be 'DONE init', got '{lines[1]}'"
    assert "START build_db 4" in lines, "Missing 'START build_db 4'"
    assert "DONE build_db" in lines, "Missing 'DONE build_db'"
    assert "START build_web 6" in lines, "Missing 'START build_web 6'"
    assert "DONE build_web" in lines, "Missing 'DONE build_web'"
    assert lines.index("DONE build_db") > lines.index("START build_db 4")
    assert lines.index("DONE build_web") > lines.index("START build_web 6")
    assert lines.index("START build_db 4") > lines.index("DONE init")
    assert lines.index("START build_web 6") > lines.index("DONE init")
    assert lines[-2] == "START link_all 12", (
        f"Second to last line must be 'START link_all 12', got '{lines[-2]}'"
    )
    assert lines[-1] == "DONE link_all", f"Last line must be 'DONE link_all', got '{lines[-1]}'"
    assert lines.index("START link_all 12") > lines.index("DONE build_db")
    assert lines.index("START link_all 12") > lines.index("DONE build_web")

    mem_output = assert_valid_profile(MEM, BUILDER)
    assert re.search(r"alloc|heap|inuse", mem_output, re.IGNORECASE), (
        "mem.prof is readable but does not appear to be a memory profile"
    )

    cpu_found = False
    for candidate in glob.glob(os.path.join(HOME, "*.prof")):
        if os.path.abspath(candidate) == os.path.abspath(MEM):
            continue
        try:
            output = assert_valid_profile(candidate, BUILDER)
        except AssertionError:
            continue
        if re.search(r"cpu", output, re.IGNORECASE):
            cpu_found = True
            break
    assert cpu_found, "CI execution did not generate a valid CPU profile"

    # Compile the submitted Go source independently, preventing ci.sh from
    # substituting a canned executable or log generator.
    verified_builder = "/tmp/verified_builder"
    compile_result = run(["go", "build", "-o", verified_builder, SOURCE])
    assert compile_result.returncode == 0, (
        f"builder.go does not compile: {compile_result.stderr}"
    )

    # Use unpredictable names and expressions, and derive all expected values.
    token = uuid.uuid4().hex[:10]
    root = "root_" + token
    left = "left_" + token
    right = "right_" + token
    final = "final_" + token
    p = random.SystemRandom().randint(1, 9)
    q = random.SystemRandom().randint(1, 9)
    root_w = 9 + p
    left_w = 500 + p * 7
    right_w = 1200 // 2 - q * 5
    final_w = 18 // 3 + q - p

    with open(GRAPH, "w", encoding="utf-8") as f:
        f.write(f"{root}:   : 9 + {p}\n")
        f.write(f"{left} : {root}: 500 + {p} * 7\n")
        f.write(f"{right}  :  {root} : 1200 / 2 - {q} * 5\n")
        f.write(f"{final}: {left} , {right} : 18 / 3 + {q} - {p}\n")

    try:
        os.remove(LOG)
    except FileNotFoundError:
        pass

    started = time.monotonic()
    dynamic_result = run([verified_builder], timeout=15)
    elapsed = time.monotonic() - started
    assert dynamic_result.returncode == 0, (
        f"builder failed on generated graph: {dynamic_result.stderr}"
    )

    lines = read_lines()
    expected = {
        f"START {root} {root_w}", f"DONE {root}",
        f"START {left} {left_w}", f"DONE {left}",
        f"START {right} {right_w}", f"DONE {right}",
        f"START {final} {final_w}", f"DONE {final}",
    }
    assert len(lines) == 8, f"generated graph should produce 8 lines, got {lines}"
    assert set(lines) == expected, f"incorrect generated-graph log: {lines}"
    assert len(set(lines)) == 8, "tasks were logged more than once"

    idx = {line: lines.index(line) for line in expected}
    assert idx[f"START {root} {root_w}"] < idx[f"DONE {root}"]
    assert idx[f"DONE {root}"] < idx[f"START {left} {left_w}"]
    assert idx[f"DONE {root}"] < idx[f"START {right} {right_w}"]
    assert idx[f"START {left} {left_w}"] < idx[f"DONE {left}"]
    assert idx[f"START {right} {right_w}"] < idx[f"DONE {right}"]
    assert idx[f"START {final} {final_w}"] > idx[f"DONE {left}"]
    assert idx[f"START {final} {final_w}"] > idx[f"DONE {right}"]
    assert idx[f"START {final} {final_w}"] < idx[f"DONE {final}"]

    # Both ready tasks must have started before either completes. Combined with
    # elapsed-time bounds, this checks goroutine concurrency and actual sleeps.
    first_branch_done = min(idx[f"DONE {left}"], idx[f"DONE {right}"])
    assert idx[f"START {left} {left_w}"] < first_branch_done
    assert idx[f"START {right} {right_w}"] < first_branch_done
    critical_ms = root_w + max(left_w, right_w) + final_w
    serial_ms = root_w + left_w + right_w + final_w
    assert elapsed >= max(0.20, critical_ms / 1000.0 * 0.70), (
        f"execution finished too quickly to have slept for task weights: {elapsed:.3f}s"
    )
    assert elapsed < serial_ms / 1000.0 - 0.15, (
        f"independent tasks appear to have run serially: {elapsed:.3f}s"
    )

    # A missing dependency must cause failure instead of hanging or succeeding.
    missing = "missing_" + uuid.uuid4().hex[:10]
    with open(GRAPH, "w", encoding="utf-8") as f:
        f.write(f"bad_{token} : {missing} : 1\n")
    bad_result = run([verified_builder], timeout=5)
    assert bad_result.returncode != 0, "builder accepted a nonexistent dependency"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
