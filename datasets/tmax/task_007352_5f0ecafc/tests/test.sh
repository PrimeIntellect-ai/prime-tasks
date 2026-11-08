#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import datetime
import math
import os
import re
import secrets
import subprocess
import tempfile
import time


def test_math_utils_fixed():
    path = "/home/user/legacy_project/math_utils.c"
    assert os.path.isfile(path), f"{path} is missing"
    with open(path, "r") as f:
        content = f.read()

    # Preserve the original source-level assertions.
    assert "^" not in content, "math_utils.c still contains the bitwise XOR operator '^'"
    assert "*" in content or "pow" in content, "math_utils.c does not seem to use multiplication or pow() for squaring"

    # Compile and exercise the submitted function on verifier-generated inputs.
    with tempfile.TemporaryDirectory() as td:
        library = os.path.join(td, "libmath_utils.so")
        result = subprocess.run(
            ["gcc", "-shared", "-fPIC", path, "-o", library, "-lm"],
            capture_output=True,
        )
        assert result.returncode == 0, f"math_utils.c failed to compile: {result.stderr.decode()}"

        lib = ctypes.CDLL(library)
        fn = lib.calculate_distance
        fn.argtypes = [ctypes.c_double, ctypes.c_double, ctypes.c_double, ctypes.c_double]
        fn.restype = ctypes.c_double

        cases = [
            (0.0, 0.0, 3.0, 4.0),
            (-2.5, 7.25, 4.75, -1.5),
            (1.125, -3.875, 1.125, -3.875),
            (100000.5, -200000.25, -300000.75, 400000.125),
        ]
        for _ in range(12):
            cases.append(tuple((secrets.randbelow(4000001) - 2000000) / 1000.0 for _ in range(4)))

        for x1, y1, x2, y2 in cases:
            actual = fn(x1, y1, x2, y2)
            expected = math.hypot(x2 - x1, y2 - y1)
            assert math.isfinite(actual), "calculate_distance returned a non-finite result"
            assert math.isclose(actual, expected, rel_tol=1e-12, abs_tol=1e-10), (
                f"calculate_distance({x1}, {y1}, {x2}, {y2}) returned {actual}, expected {expected}"
            )


def test_processor_bottleneck_fixed():
    path = "/home/user/legacy_project/processor.c"
    assert os.path.isfile(path), f"{path} is missing"
    with open(path, "r") as f:
        content = f.read()

    # Preserve the original assertion.
    assert "usleep" not in content, "processor.c still contains the usleep() bottleneck"


def test_processor_compiles_and_runs_fast():
    project = "/home/user/legacy_project"
    compile_cmd = ["gcc", "-o", "processor", "processor.c", "math_utils.c", "-lm"]
    result = subprocess.run(compile_cmd, cwd=project, capture_output=True)
    assert result.returncode == 0, f"Compilation failed: {result.stderr.decode()}"

    start_time = time.time()
    result = subprocess.run(["./processor"], cwd=project, capture_output=True)
    end_time = time.time()
    assert result.returncode == 0, "Processor execution failed"

    elapsed = end_time - start_time
    assert elapsed < 0.5, f"Processor is still too slow, took {elapsed:.2f} seconds (expected < 0.1s)"

    # Exercise the processor with 100 hidden records and validate every result.
    with tempfile.TemporaryDirectory() as td:
        executable = os.path.join(td, "processor")
        result = subprocess.run(
            ["gcc", "-o", executable,
             os.path.join(project, "processor.c"),
             os.path.join(project, "math_utils.c"), "-lm"],
            capture_output=True,
        )
        assert result.returncode == 0, f"Hidden-input compilation failed: {result.stderr.decode()}"

        os.mkdir(os.path.join(td, "logs"))
        points = []
        with open(os.path.join(td, "test_data.txt"), "w") as f:
            for _ in range(100):
                x = (secrets.randbelow(2000001) - 1000000) / 100.0
                y = (secrets.randbelow(2000001) - 1000000) / 100.0
                points.append((x, y))
                f.write(f"{x:.2f} {y:.2f}\n")

        start = time.perf_counter()
        run = subprocess.run([executable], cwd=td, capture_output=True, timeout=3)
        duration = time.perf_counter() - start
        assert run.returncode == 0, f"Processor failed on hidden input: {run.stderr.decode()}"
        assert duration < 0.1, f"Processor took {duration:.3f}s for 100 records; expected under 0.1s"

        output_path = os.path.join(td, "output.txt")
        assert os.path.isfile(output_path), "Processor did not generate output.txt"
        with open(output_path) as f:
            output_lines = [line.strip() for line in f if line.strip()]
        assert len(output_lines) == len(points), "Processor did not emit one distance for every input point"

        previous = (0.0, 0.0)
        for index, (line, point) in enumerate(zip(output_lines, points)):
            match = re.fullmatch(r"Dist:\s*([-+0-9.eE]+)", line)
            assert match, f"Malformed processor output on record {index + 1}: {line}"
            actual = float(match.group(1))
            expected = math.hypot(point[0] - previous[0], point[1] - previous[1])
            assert math.isclose(actual, expected, rel_tol=1e-7, abs_tol=2e-5), (
                f"Wrong distance on record {index + 1}: got {actual}, expected {expected}"
            )
            previous = point

        # Verify that synchronization was removed from the per-record path and
        # that no sleep syscall remains under another spelling.
        trace_path = os.path.join(td, "processor.trace")
        traced = subprocess.run(
            ["strace", "-f", "-qq", "-e",
             "trace=fsync,fdatasync,nanosleep,clock_nanosleep",
             "-o", trace_path, executable],
            cwd=td,
            capture_output=True,
            timeout=3,
        )
        assert traced.returncode == 0, "Processor failed while being system-call traced"
        with open(trace_path) as f:
            trace = f.read()
        sync_calls = len(re.findall(r"\b(?:fsync|fdatasync)\(", trace))
        sleep_calls = len(re.findall(r"\b(?:nanosleep|clock_nanosleep)\(", trace))
        assert sync_calls <= 1, "Processor still synchronizes its log once per record"
        assert sleep_calls == 0, "Processor still performs sleep system calls while processing records"


def test_mre_bottleneck_exists():
    path = "/home/user/mre_bottleneck.c"
    assert os.path.isfile(path), f"{path} is missing"
    with open(path, "r") as f:
        content = f.read()

    # Preserve the original assertions.
    assert "fsync" in content, "mre_bottleneck.c does not contain fsync()"
    assert "usleep" in content, "mre_bottleneck.c does not contain usleep()"
    assert "while" in content or "for" in content, "mre_bottleneck.c should contain a loop demonstrating the bottleneck"

    # The MRE must independently compile and actually reproduce repeated sync
    # and sleep calls rather than merely mentioning their names.
    with tempfile.TemporaryDirectory() as td:
        executable = os.path.join(td, "mre_bottleneck")
        result = subprocess.run(["gcc", path, "-o", executable], capture_output=True)
        assert result.returncode == 0, f"mre_bottleneck.c failed to compile: {result.stderr.decode()}"

        trace_path = os.path.join(td, "mre.trace")
        start = time.perf_counter()
        result = subprocess.run(
            ["strace", "-f", "-qq", "-e",
             "trace=fsync,fdatasync,nanosleep,clock_nanosleep",
             "-o", trace_path, executable],
            cwd=td,
            capture_output=True,
            timeout=12,
        )
        elapsed = time.perf_counter() - start
        assert result.returncode == 0, f"Compiled MRE failed to run: {result.stderr.decode()}"
        with open(trace_path) as f:
            trace = f.read()
        sync_calls = len(re.findall(r"\b(?:fsync|fdatasync)\(", trace))
        sleep_calls = len(re.findall(r"\b(?:nanosleep|clock_nanosleep)\(", trace))
        assert sync_calls >= 2, "MRE did not execute repeated fsync/fdatasync calls"
        assert sleep_calls >= 2, "MRE did not execute repeated sleep calls"
        assert elapsed >= 0.05, "MRE does not measurably reproduce the latency bottleneck"


def _assert_timeline_format_and_order(timeline_path):
    assert os.path.isfile(timeline_path), f"{timeline_path} was not generated"
    with open(timeline_path, "r") as f:
        lines = f.readlines()
    assert len(lines) > 0, "timeline.log is empty"

    parsed = []
    previous_time = 0.0
    for line in lines:
        line = line.strip()
        if not line:
            continue
        match = re.match(r'^\[(\d+(?:\.\d+)?)\]\s+(GEN|PROC|AGG)\s+:\s+(.*)$', line)
        assert match is not None, f"Line format is incorrect: {line}"
        current_time = float(match.group(1))
        assert current_time >= previous_time, "timeline.log is not chronologically sorted"
        previous_time = current_time
        parsed.append((current_time, match.group(2), match.group(3)))
    return parsed


def test_reconstruct_logs_script():
    script_path = "/home/user/reconstruct_logs.sh"
    assert os.path.isfile(script_path), f"{script_path} is missing"

    result = subprocess.run(["bash", script_path], capture_output=True)
    assert result.returncode == 0, f"reconstruct_logs.sh failed to execute: {result.stderr.decode()}"
    _assert_timeline_format_and_order("/home/user/timeline.log")


def _derive_expected_records(log_dir):
    utc = datetime.timezone.utc
    records = []

    with open(os.path.join(log_dir, "gen.log")) as f:
        for raw in f:
            raw = raw.rstrip("\n")
            match = re.fullmatch(r"(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d+Z)\s+(.*)", raw)
            assert match, f"Invalid GEN test fixture: {raw}"
            dt = datetime.datetime.strptime(match.group(1), "%Y-%m-%dT%H:%M:%S.%fZ").replace(tzinfo=utc)
            records.append((dt.timestamp(), "GEN", match.group(2)))

    with open(os.path.join(log_dir, "proc.log")) as f:
        for raw in f:
            raw = raw.rstrip("\n")
            match = re.fullmatch(r"PROC\|(\d{8}-\d{6}\.\d+)\|(.*)", raw)
            assert match, f"Invalid PROC test fixture: {raw}"
            dt = datetime.datetime.strptime(match.group(1), "%Y%m%d-%H%M%S.%f").replace(tzinfo=utc)
            records.append((dt.timestamp(), "PROC", match.group(2)))

    with open(os.path.join(log_dir, "agg.log")) as f:
        for raw in f:
            raw = raw.rstrip("\n")
            match = re.fullmatch(r"(\d{2}/\d{2}/\d{4} \d{2}:\d{2}:\d{2}\.\d+ [AP]M)\s+(.*)", raw)
            assert match, f"Invalid AGG test fixture: {raw}"
            dt = datetime.datetime.strptime(match.group(1), "%m/%d/%Y %I:%M:%S.%f %p").replace(tzinfo=utc)
            records.append((dt.timestamp(), "AGG", match.group(2)))

    return sorted(records)


def test_reconstruct_logs_decodes_every_source_record():
    script_path = "/home/user/reconstruct_logs.sh"
    log_dir = "/home/user/legacy_project/logs"
    paths = {name: os.path.join(log_dir, name) for name in ("gen.log", "proc.log", "agg.log")}
    originals = {name: open(path, "rb").read() for name, path in paths.items()}
    token = secrets.token_hex(12)

    fixtures = {
        "gen.log": (
            f"2023-10-25T10:30:00.900Z generated-late-{token}\n"
            f"2023-10-25T10:29:59.010Z generated-early-{token}\n"
        ),
        "proc.log": (
            f"PROC|20231025-103002.005|processed-latest-{token}\n"
            f"PROC|20231025-103000.123|processed-middle-{token}\n"
        ),
        "agg.log": (
            f"10/25/2023 10:30:01.000 AM aggregated-middle-{token}\n"
            f"10/25/2023 10:29:59.500 AM aggregated-early-{token}\n"
        ),
    }

    try:
        for name, text in fixtures.items():
            with open(paths[name], "w") as f:
                f.write(text)

        expected = _derive_expected_records(log_dir)
        result = subprocess.run(["bash", script_path], capture_output=True)
        assert result.returncode == 0, f"reconstruct_logs.sh failed on hidden logs: {result.stderr.decode()}"
        actual = _assert_timeline_format_and_order("/home/user/timeline.log")

        assert len(actual) == len(expected), (
            f"timeline.log contains {len(actual)} records, but all three source logs contain {len(expected)}"
        )
        for index, (got, want) in enumerate(zip(actual, expected), 1):
            assert got[1:] == want[1:], f"Timeline record {index} has wrong component or message: {got}"
            assert math.isclose(got[0], want[0], rel_tol=0.0, abs_tol=0.0004), (
                f"Timeline record {index} has epoch {got[0]}, expected {want[0]}"
            )
    finally:
        for name, data in originals.items():
            with open(paths[name], "wb") as f:
                f.write(data)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
