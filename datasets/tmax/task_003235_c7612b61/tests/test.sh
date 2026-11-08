#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import re
import shutil
import stat
import subprocess
import tempfile
from collections import Counter

import pytest

HOME = "/home/user"
STRICT = f"{HOME}/rate_filter_strict"
STANDARD = f"{HOME}/rate_filter_standard"


def run_filter(path, lines):
    data = "".join(lines)
    proc = subprocess.run(
        [path], input=data, text=True, capture_output=True, timeout=15
    )
    assert proc.returncode == 0, f"{path} returned {proc.returncode}: {proc.stderr}"
    return proc.stdout


def expected_output(lines, limit):
    counts = Counter()
    output = []
    for line in lines:
        timestamp, ip, _message = line.rstrip("\n").split(" ", 2)
        key = (timestamp, ip)
        counts[key] += 1
        if counts[key] <= limit:
            output.append(line)
    return "".join(output)


def test_files_exist():
    """Verify that all required files and binaries exist and have correct permissions."""
    expected_files = [
        "/home/user/rate_filter.c",
        "/home/user/build.sh",
        "/home/user/prop_test.py",
        "/home/user/rate_filter_strict",
        "/home/user/rate_filter_standard",
        "/home/user/test_results.log"
    ]
    for filepath in expected_files:
        assert os.path.isfile(filepath), f"Expected file {filepath} does not exist."

    assert os.access("/home/user/build.sh", os.X_OK), "build.sh is not executable."
    assert os.access("/home/user/rate_filter_strict", os.X_OK), "rate_filter_strict is not executable."
    assert os.access("/home/user/rate_filter_standard", os.X_OK), "rate_filter_standard is not executable."


def test_source_and_build_script_requirements():
    source = open(f"{HOME}/rate_filter.c", encoding="utf-8").read()
    assert re.search(r"#\s*ifndef\s+MAX_REQ\b", source), "rate_filter.c lacks #ifndef MAX_REQ."
    assert re.search(r"#\s*define\s+MAX_REQ\s+3\b", source), "The default MAX_REQ must be 3."
    assert len(re.findall(r"\bMAX_REQ\b", source)) >= 3, "MAX_REQ is not used by the filter logic."
    assert re.search(r"\bstruct\b", source), "A custom tracking structure was not found."
    assert re.search(r"\b(hash|bucket|buckets|next|linked)\b", source, re.I), \
        "No custom hash-map or linked-list implementation was found."
    assert not re.search(r"glib|g_hash_table", source, re.I), "External GLib data structures are forbidden."

    trace_dir = tempfile.mkdtemp(prefix="compiler-trace-")
    trace_file = os.path.join(trace_dir, "calls.jsonl")
    gcc_wrapper = os.path.join(trace_dir, "gcc")
    with open(gcc_wrapper, "w", encoding="utf-8") as f:
        f.write("#!/usr/bin/python3\n")
        f.write("import json, os, sys\n")
        f.write(f"p = {trace_file!r}\n")
        f.write("with open(p, 'a') as out: out.write(json.dumps(sys.argv[1:]) + '\\n')\n")
        f.write("os.execv('/usr/bin/gcc', ['gcc'] + sys.argv[1:])\n")
    os.chmod(gcc_wrapper, 0o755)

    for path in (STRICT, STANDARD):
        if os.path.exists(path):
            os.remove(path)
    env = os.environ.copy()
    env["PATH"] = trace_dir + os.pathsep + env.get("PATH", "")
    proc = subprocess.run(
        [f"{HOME}/build.sh"], cwd=HOME, env=env,
        text=True, capture_output=True, timeout=60
    )
    assert proc.returncode == 0, f"build.sh failed:\n{proc.stdout}\n{proc.stderr}"
    assert os.path.isfile(STRICT) and os.access(STRICT, os.X_OK)
    assert os.path.isfile(STANDARD) and os.access(STANDARD, os.X_OK)
    assert os.path.exists(trace_file), "build.sh did not invoke gcc from PATH."

    with open(trace_file, encoding="utf-8") as f:
        calls = [json.loads(line) for line in f if line.strip()]

    def matching_call(limit, output):
        for args in calls:
            has_opt = "-O2" in args
            has_macro = f"-DMAX_REQ={limit}" in args
            has_source = any(os.path.basename(arg) == "rate_filter.c" for arg in args)
            out_ok = False
            if "-o" in args and args.index("-o") + 1 < len(args):
                out_arg = args[args.index("-o") + 1]
                out_ok = os.path.abspath(os.path.join(HOME, out_arg)) == output
            if has_opt and has_macro and has_source and out_ok:
                return True
        return False

    assert matching_call(2, STRICT), "build.sh must use gcc -O2 -DMAX_REQ=2 for rate_filter_strict."
    assert matching_call(5, STANDARD), "build.sh must use gcc -O2 -DMAX_REQ=5 for rate_filter_standard."


def test_rate_filter_strict():
    """Verify the original fixed logic fixture for MAX_REQ=2."""
    input_data = (
        "1000 1.1.1.1 A\n"
        "1000 1.1.1.1 B\n"
        "1000 1.1.1.1 C\n"
        "1000 1.1.1.1 D\n"
        "1000 1.1.1.2 E\n"
        "1000 1.1.1.2 F\n"
        "1000 1.1.1.2 G\n"
        "1001 1.1.1.1 H\n"
        "1001 1.1.1.1 I\n"
        "1001 1.1.1.1 J\n"
    )
    expected = (
        "1000 1.1.1.1 A\n"
        "1000 1.1.1.1 B\n"
        "1000 1.1.1.2 E\n"
        "1000 1.1.1.2 F\n"
        "1001 1.1.1.1 H\n"
        "1001 1.1.1.1 I\n"
    )
    proc = subprocess.run([STRICT], input=input_data, text=True, capture_output=True)
    assert proc.returncode == 0
    assert proc.stdout == expected


def test_rate_filter_standard():
    """Verify the original fixed logic fixture for MAX_REQ=5."""
    input_data = (
        "1000 1.1.1.1 A\n"
        "1000 1.1.1.1 B\n"
        "1000 1.1.1.1 C\n"
        "1000 1.1.1.1 D\n"
        "1000 1.1.1.2 E\n"
        "1000 1.1.1.2 F\n"
        "1000 1.1.1.2 G\n"
        "1001 1.1.1.1 H\n"
        "1001 1.1.1.1 I\n"
        "1001 1.1.1.1 J\n"
    )
    expected = input_data
    proc = subprocess.run([STANDARD], input=input_data, text=True, capture_output=True)
    assert proc.returncode == 0
    assert proc.stdout == expected


def test_randomized_filter_behavior():
    rng = random.Random(int.from_bytes(os.urandom(16), "big"))
    ips = [f"10.{i // 256}.{i % 256}.{(i * 37) % 253 + 1}" for i in range(73)]
    lines = []
    sequence = 0
    base = rng.randint(200000, 900000)
    for second in range(45):
        timestamp = base + second
        for _ in range(rng.randint(65, 125)):
            ip = rng.choice(ips)
            message = f"event {sequence} token {rng.getrandbits(64):016x} with spaces"
            lines.append(f"{timestamp} {ip} {message}\n")
            sequence += 1
    assert run_filter(STRICT, lines) == expected_output(lines, 2)
    assert run_filter(STANDARD, lines) == expected_output(lines, 5)


def write_filter_wrapper(path, body):
    with open(path, "w", encoding="utf-8") as f:
        f.write("#!/usr/bin/python3\n" + body)
    os.chmod(path, 0o755)


def run_property_script():
    return subprocess.run(
        ["python3", f"{HOME}/prop_test.py"], cwd=HOME,
        text=True, capture_output=True, timeout=60
    )


def assert_fail_result(proc):
    assert proc.returncode != 0, "prop_test.py accepted a deliberately incorrect filter."
    assert os.path.isfile(f"{HOME}/test_results.log")
    assert open(f"{HOME}/test_results.log", encoding="utf-8").read().strip() == "FAIL"


def test_property_test_executes_and_checks_both_properties():
    prop_source = open(f"{HOME}/prop_test.py", encoding="utf-8").read()
    assert re.search(r"(^|\n)\s*(import\s+random|from\s+random\s+import)", prop_source)
    assert "rate_filter_standard" in prop_source

    real_filter = f"/tmp/rate_filter_standard.real.{os.getpid()}"
    capture = f"/tmp/property-input.{os.getpid()}"
    os.replace(STANDARD, real_filter)
    try:
        # A filter dropping everything satisfies the upper bound but violates preservation.
        write_filter_wrapper(STANDARD, "import sys\nsys.stdin.read()\n")
        if os.path.exists(f"{HOME}/test_results.log"):
            os.remove(f"{HOME}/test_results.log")
        assert_fail_result(run_property_script())

        # Repeating every input six times necessarily violates the upper bound.
        write_filter_wrapper(
            STANDARD,
            "import sys\nlines = sys.stdin.readlines()\n"
            "for line in lines:\n"
            "    sys.stdout.write(line * 6)\n"
        )
        os.remove(f"{HOME}/test_results.log")
        assert_fail_result(run_property_script())

        # Run against the real executable while capturing exactly what the test generated.
        wrapper = (
            "import subprocess, sys\n"
            "data = sys.stdin.buffer.read()\n"
            f"open({capture!r}, 'wb').write(data)\n"
            f"p = subprocess.run([{real_filter!r}], input=data, stdout=subprocess.PIPE, stderr=subprocess.PIPE)\n"
            "sys.stdout.buffer.write(p.stdout)\n"
            "sys.stderr.buffer.write(p.stderr)\n"
            "raise SystemExit(p.returncode)\n"
        )
        write_filter_wrapper(STANDARD, wrapper)
        os.remove(f"{HOME}/test_results.log")
        proc = run_property_script()
        assert proc.returncode == 0, f"prop_test.py failed on the real filter: {proc.stdout} {proc.stderr}"
        assert open(f"{HOME}/test_results.log", encoding="utf-8").read().strip() == "PASS"

        generated = open(capture, encoding="utf-8").read().splitlines()
        assert len(generated) == 10000, "prop_test.py must generate exactly 10,000 lines."
        parsed = [line.split(" ", 2) for line in generated]
        assert all(len(parts) == 3 for parts in parsed)
        timestamps = [int(parts[0]) for parts in parsed]
        ips = [parts[1] for parts in parsed]
        assert all(ts > 0 for ts in timestamps)
        assert timestamps == sorted(timestamps), "Generated timestamps are not chronological."
        assert max(timestamps) - min(timestamps) <= 100
        assert max(timestamps) - min(timestamps) >= 90, "Input does not span a 100-second window."
        assert len(set(ips)) == 50, "Generated input must use a pool of 50 IP addresses."
    finally:
        if os.path.exists(STANDARD):
            os.remove(STANDARD)
        if os.path.exists(real_filter):
            os.replace(real_filter, STANDARD)
        if os.path.exists(capture):
            os.remove(capture)


def test_test_results_log():
    """Verify that the freshly generated test_results.log contains exactly PASS."""
    log_path = "/home/user/test_results.log"
    with open(log_path, "r") as f:
        content = f.read().strip()
    assert content == "PASS", f"Expected test_results.log to contain 'PASS', but got '{content}'"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
