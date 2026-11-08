#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import os
import random
import subprocess
import tempfile
import pytest


def test_libcsv_installed():
    assert os.path.isfile("/home/user/local/include/csv.h"), "libcsv header not installed in /home/user/local/include/"
    has_so = os.path.isfile("/home/user/local/lib/libcsv.so")
    has_a = os.path.isfile("/home/user/local/lib/libcsv.a")
    assert has_so or has_a, "libcsv library not installed in /home/user/local/lib/"


def test_imputer_exists():
    assert os.path.isfile("/home/user/imputer.c"), "/home/user/imputer.c is missing"
    assert os.path.isfile("/home/user/imputer"), "/home/user/imputer binary is missing"
    assert os.access("/home/user/imputer", os.X_OK), "/home/user/imputer is not executable"


def test_pipeline_script():
    assert os.path.isfile("/home/user/pipeline.sh"), "/home/user/pipeline.sh is missing"
    assert os.access("/home/user/pipeline.sh", os.X_OK), "/home/user/pipeline.sh is not executable"


def test_pipeline_cron():
    assert os.path.isfile("/home/user/pipeline.cron"), "/home/user/pipeline.cron is missing"
    with open("/home/user/pipeline.cron", "r") as f:
        content = f.read().strip()
    assert "*/5" in content or "0,5" in content or "5" in content, "Cron schedule must be every 5 minutes"
    assert "/home/user/pipeline.sh" in content, "Cron must execute /home/user/pipeline.sh"


def generate_csv(filename, num_lines, missing_prob, block_prob, block_size_max):
    with open(filename, "w") as f:
        ts = 1600000000
        val = random.uniform(-100.0, 100.0)
        in_block = False
        block_rem = 0

        for _ in range(num_lines):
            ts += random.randint(1, 10)
            val += random.uniform(-1.0, 1.0)

            is_missing = False
            if in_block:
                is_missing = True
                block_rem -= 1
                if block_rem <= 0:
                    in_block = False
            else:
                if random.random() < block_prob:
                    in_block = True
                    block_rem = random.randint(1, block_size_max)
                    is_missing = True
                elif random.random() < missing_prob:
                    is_missing = True

            if is_missing:
                missing_str = "" if random.random() < 0.5 else "NaN"
                f.write(f"{ts},{missing_str}\n")
            else:
                f.write(f"{ts},{val:.6f}\n")


def reference_output(filename):
    rows = []
    with open(filename, "r") as f:
        for line in f:
            if "," not in line:
                continue
            ts_text, value_text = line.split(",", 1)
            ts = int(ts_text)
            value_text = value_text.lstrip(" \t")
            missing = (not value_text or value_text[0] in "\n\r" or value_text.startswith("NaN"))
            rows.append([ts, 0.0 if missing else float(value_text), missing])

    for i, row in enumerate(rows):
        if not row[2]:
            continue
        prev_idx = next((j for j in range(i - 1, -1, -1) if not rows[j][2]), -1)
        next_idx = next((j for j in range(i + 1, len(rows)) if not rows[j][2]), -1)
        if prev_idx != -1 and next_idx != -1:
            t = float(row[0] - rows[prev_idx][0]) / float(rows[next_idx][0] - rows[prev_idx][0])
            row[1] = rows[prev_idx][1] + t * (rows[next_idx][1] - rows[prev_idx][1])
        elif prev_idx != -1:
            row[1] = rows[prev_idx][1]
        elif next_idx != -1:
            row[1] = rows[next_idx][1]
        else:
            row[1] = 0.0

    libc = ctypes.CDLL(None)
    output = []
    for ts, value, _ in rows:
        buf = ctypes.create_string_buffer(128)
        libc.snprintf(buf, len(buf), b"%lld,%.6f\n", ctypes.c_longlong(ts), ctypes.c_double(value))
        output.append(buf.value.decode("ascii"))
    return "".join(output)


def test_fuzz_equivalence():
    agent = "/home/user/imputer"
    assert os.path.isfile(agent), f"Agent program {agent} is missing"

    random.seed(42)
    with tempfile.TemporaryDirectory() as tmpdir:
        for i in range(100):
            csv_path = os.path.join(tmpdir, f"test_{i}.csv")
            num_lines = random.randint(10, 5000)
            missing_prob = random.uniform(0.05, 0.40)
            block_prob = random.uniform(0.0, 0.05)

            if random.random() < 0.05:
                num_lines = random.randint(1, 5)

            generate_csv(csv_path, num_lines, missing_prob, block_prob, min(1000, num_lines))

            if random.random() < 0.1:
                with open(csv_path, "r") as f:
                    lines = f.readlines()
                if lines:
                    parts = lines[0].split(",")
                    lines[0] = f"{parts[0]},\n"
                with open(csv_path, "w") as f:
                    f.writelines(lines)

            expected = reference_output(csv_path)
            proc_agent = subprocess.run([agent, csv_path], capture_output=True, text=True)
            assert proc_agent.returncode == 0, f"Agent failed (exit code {proc_agent.returncode}) on {csv_path}\nStderr: {proc_agent.stderr}"

            if expected != proc_agent.stdout:
                expected_lines = expected.splitlines()
                agent_lines = proc_agent.stdout.splitlines()
                mismatch_idx = -1
                for j, (want, got) in enumerate(zip(expected_lines, agent_lines)):
                    if want != got:
                        mismatch_idx = j
                        break
                if mismatch_idx == -1 and len(expected_lines) != len(agent_lines):
                    mismatch_idx = min(len(expected_lines), len(agent_lines))

                expected_val = expected_lines[mismatch_idx] if mismatch_idx < len(expected_lines) else "EOF"
                agent_val = agent_lines[mismatch_idx] if mismatch_idx < len(agent_lines) else "EOF"
                pytest.fail(
                    f"Mismatch on dynamically generated input {csv_path} at line {mismatch_idx + 1}.\n"
                    f"Expected output: {expected_val}\n"
                    f"Agent output:    {agent_val}"
                )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
