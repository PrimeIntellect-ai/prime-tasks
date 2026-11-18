#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import secrets
import subprocess
import time
import uuid
import pytest

SOURCE = "/home/user/fast_filter.cpp"
PIPELINE = "/home/user/pipeline.sh"
FAST_BIN = "/home/user/fast_filter"
LEGACY = "/app/legacy_filter"
VERIFIED_BIN = f"/tmp/verified_fast_{uuid.uuid4().hex}"


def run(cmd, timeout=90):
    return subprocess.run(cmd, check=True, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, text=True, timeout=timeout)


def test_files_exist():
    assert os.path.isfile(SOURCE), "Missing /home/user/fast_filter.cpp"
    assert os.path.isfile(PIPELINE), "Missing /home/user/pipeline.sh"


def _minute_values(expr):
    values = set()
    for part in expr.split(','):
        if part == '*':
            values.update(range(60))
            continue
        if '/' in part:
            base, step_s = part.split('/', 1)
            step = int(step_s)
            if step <= 0:
                raise ValueError("invalid cron step")
            if base == '*':
                start, end = 0, 59
            elif '-' in base:
                start, end = map(int, base.split('-', 1))
            else:
                start, end = int(base), 59
            values.update(range(start, end + 1, step))
            continue
        if '-' in part:
            start, end = map(int, part.split('-', 1))
            values.update(range(start, end + 1))
        else:
            values.add(int(part))
    return values


def _all_crontabs():
    found = []
    for args in (["crontab", "-l"], ["crontab", "-l", "-u", "user"]):
        proc = subprocess.run(args, text=True, stdout=subprocess.PIPE,
                              stderr=subprocess.DEVNULL)
        if proc.returncode == 0:
            found.append(proc.stdout)
    return "\n".join(found)


def test_cron_job_configured():
    output = _all_crontabs()
    assert output.strip(), "No root or user crontab is configured"

    matching_commands = []
    for raw in output.splitlines():
        line = raw.strip()
        if not line or line.startswith('#') or re.match(r'^[A-Za-z_][A-Za-z0-9_]*=', line):
            continue
        fields = line.split(None, 5)
        if len(fields) != 6:
            continue
        minute, hour, dom, month, dow, command = fields
        try:
            every_five = _minute_values(minute) == set(range(0, 60, 5))
        except Exception:
            every_five = False
        if every_five and hour == '*' and dom == '*' and month == '*' and dow == '*':
            matching_commands.append(command)

    assert matching_commands, "Cron job is not scheduled exactly every five minutes"

    with open(PIPELINE, 'r', errors='replace') as f:
        pipeline_text = f.read()
    assert re.search(r'\bg\+\+\b', pipeline_text), "pipeline.sh does not compile the C++ program"

    valid_pipeline = False
    for command in matching_commands:
        command_l = command.lower()
        evidence = (command + "\n" + pipeline_text).lower()
        invokes_pipeline = "pipeline.sh" in command_l
        direct_processing = all(x in command_l for x in ("fast_filter", "incoming", "processed"))
        has_processing_logic = all(x in evidence for x in ("fast_filter", "incoming", "processed", ".csv"))
        if (invokes_pipeline or direct_processing) and has_processing_logic:
            valid_pipeline = True
            break
    assert valid_pipeline, "Every-five-minutes cron job does not implement the required CSV processing pipeline"


def _compile_verified_binary():
    run(["g++", "-O3", "-std=c++17", SOURCE, "-o", VERIFIED_BIN])
    assert os.path.isfile(VERIFIED_BIN) and os.access(VERIFIED_BIN, os.X_OK)


def _ensure_submitted_binary():
    if not os.path.exists(FAST_BIN):
        subprocess.run(["bash", PIPELINE], check=False, timeout=60)
    assert os.path.exists(FAST_BIN), f"Executable {FAST_BIN} not found. Ensure pipeline.sh compiles it."
    assert os.access(FAST_BIN, os.X_OK), f"{FAST_BIN} is not executable."


def _compare_case(lines):
    token = uuid.uuid4().hex
    inp = f"/tmp/input_{token}.csv"
    expected = f"/tmp/legacy_{token}.csv"
    with open(inp, 'w') as f:
        f.write("id,category,v1,v2,v3\n")
        f.writelines(lines)

    run([LEGACY, inp, expected])
    with open(expected, 'rb') as f:
        wanted = f.read()

    for binary, name in ((FAST_BIN, "installed fast_filter"),
                         (VERIFIED_BIN, "fast_filter.cpp build")):
        actual = f"/tmp/actual_{name.replace(' ', '_')}_{token}.csv"
        run([binary, inp, actual])
        with open(actual, 'rb') as f:
            got = f.read()
        assert got == wanted, f"{name} output differs from legacy_filter on a held-out input"


def test_general_filtering_and_stratification():
    _ensure_submitted_binary()
    _compile_verified_binary()

    rng = random.Random(secrets.randbits(128))

    # Valid records begin late in the file, and every category has more than five
    # valid records. This tests both full-file processing and the per-category cap.
    lines = []
    for i in range(5200):
        cat = f"late_{i % 83}"
        v1 = rng.uniform(-30, 30)
        v2 = rng.uniform(-30, 30)
        square_sum = v1 * v1 + v2 * v2
        if i < 3600:
            v3 = square_sum - rng.uniform(1, 200)
        else:
            v3 = square_sum + rng.uniform(1, 200)
        lines.append(f"{i},{cat},{v1:.7f},{v2:.7f},{v3:.7f}\n")
    _compare_case(lines)

    # Mostly unique categories ensure matching cannot be obtained by asking the
    # oracle to process only a prefix. Include malformed values and both signs.
    lines = []
    for i in range(2600):
        if i % 211 == 0:
            lines.append(f"u{i},unique_{i},not-a-number,2,10\n")
            continue
        v1 = rng.uniform(-100, 100)
        v2 = rng.uniform(-100, 100)
        delta = rng.uniform(0.01, 500)
        v3 = v1 * v1 + v2 * v2 + (delta if rng.getrandbits(1) else -delta)
        lines.append(f"u{i},unique_{i},{v1:.9f},{v2:.9f},{v3:.9f}\n")
    _compare_case(lines)


def test_fast_filter_performance_and_accuracy():
    _ensure_submitted_binary()
    if not os.path.exists(VERIFIED_BIN):
        _compile_verified_binary()

    token = uuid.uuid4().hex
    input_file = f"/tmp/test_data_{token}.csv"
    legacy_out = f"/tmp/legacy_out_{token}.csv"
    rng = random.Random(secrets.randbits(128))

    # Use many categories, each appearing only five times, so qualifying output
    # remains distributed across the entire dataset rather than being complete
    # after a small prefix.
    num_rows = 100000
    with open(input_file, 'w') as f:
        f.write("id,category,v1,v2,v3\n")
        for i in range(num_rows):
            cat = f"cat{i % 20000}"
            v1 = rng.uniform(0, 10)
            v2 = rng.uniform(0, 10)
            v3 = (v1 * v1 + v2 * v2) + rng.uniform(-50, 50)
            f.write(f"{i},{cat},{v1:.4f},{v2:.4f},{v3:.4f}\n")

    t0 = time.monotonic()
    run([LEGACY, input_file, legacy_out], timeout=120)
    legacy_time = time.monotonic() - t0
    with open(legacy_out, 'rb') as f:
        wanted = f.read()

    for binary, label in ((FAST_BIN, "installed fast_filter"),
                          (VERIFIED_BIN, "fast_filter.cpp build")):
        output = f"/tmp/fast_out_{label.replace(' ', '_')}_{token}.csv"
        t0 = time.monotonic()
        run([binary, input_file, output], timeout=120)
        fast_time = time.monotonic() - t0
        with open(output, 'rb') as f:
            got = f.read()
        assert got == wanted, f"Outputs do not match exactly for {label}"
        speedup = legacy_time / max(fast_time, 1e-6)
        assert speedup >= 4.0, (f"{label} speedup {speedup:.2f}x is less than 4.0x "
                                f"(Legacy: {legacy_time:.3f}s, Fast: {fast_time:.3f}s)")
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
