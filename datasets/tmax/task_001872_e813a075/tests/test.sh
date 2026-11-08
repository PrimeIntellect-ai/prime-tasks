#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import subprocess
import pytest


def generate_fuzz_inputs(n=5000, seed=42):
    random.seed(seed)
    inputs = []
    ops = ["\\u002B", "\\u002D", "\\u002A"]
    for _ in range(n):
        id_val = random.randint(1, 1000)
        value = random.randint(1, 10000)
        op = random.choice(ops)
        ip = f"{random.randint(1, 255)}.{random.randint(0, 255)}.{random.randint(0, 255)}.{random.randint(0, 255)}"
        inputs.append(f"ID={id_val} VALUE={value} OP={op} IP={ip}")
    return "\n".join(inputs) + "\n"


def proc_info():
    result = {}
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        try:
            with open(f"/proc/{entry}/cmdline", "rb") as f:
                argv = [x.decode(errors="replace") for x in f.read().split(b"\0") if x]
            with open(f"/proc/{entry}/stat", "r") as f:
                stat = f.read()
            tail = stat[stat.rfind(")") + 2:].split()
            ppid = int(tail[1])
            result[int(entry)] = (ppid, argv)
        except (FileNotFoundError, ProcessLookupError, PermissionError, ValueError):
            pass
    return result


def descendants(root, processes):
    found = set()
    changed = True
    while changed:
        changed = False
        for pid, (ppid, _) in processes.items():
            if pid not in found and (ppid == root or ppid in found):
                found.add(pid)
                changed = True
    return found


def test_mapper_exists_and_executable():
    student_script = "/home/user/mapper.sh"
    assert os.path.exists(student_script), f"Student script {student_script} does not exist."
    assert os.path.isfile(student_script), f"{student_script} is not a file."
    assert os.access(student_script, os.X_OK), f"{student_script} is not executable."


def test_fuzz_equivalence():
    oracle_script = "/tests/oracle_mapper.sh"
    student_script = "/home/user/mapper.sh"

    assert os.path.exists(oracle_script), f"Oracle script {oracle_script} missing."

    input_data = generate_fuzz_inputs(5000, 42)

    oracle_proc = subprocess.run(
        ["/bin/bash", oracle_script],
        input=input_data,
        text=True,
        capture_output=True,
        check=True
    )
    oracle_output = oracle_proc.stdout

    student_proc = subprocess.run(
        ["/bin/bash", student_script],
        input=input_data,
        text=True,
        capture_output=True
    )

    if student_proc.returncode != 0:
        pytest.fail(f"Student script failed with return code {student_proc.returncode}\nStderr: {student_proc.stderr}")

    student_output = student_proc.stdout
    oracle_lines = oracle_output.strip().split("\n")
    student_lines = student_output.strip().split("\n")
    input_lines = input_data.strip().split("\n")

    assert len(student_lines) == len(oracle_lines), f"Output line count mismatch. Expected {len(oracle_lines)}, got {len(student_lines)}"

    for i, (o_line, s_line) in enumerate(zip(oracle_lines, student_lines)):
        if o_line != s_line:
            pytest.fail(
                f"Mismatch at line {i+1}:\n"
                f"Input:  {input_lines[i]}\n"
                f"Oracle: {o_line}\n"
                f"Agent:  {s_line}"
            )


def test_required_background_pipeline_is_running():
    expected = "nc 127.0.0.1 9001 | /home/user/mapper.sh | nc 127.0.0.1 9002"
    processes = proc_info()
    roots = [
        pid for pid, (_, argv) in processes.items()
        if len(argv) >= 3
        and os.path.basename(argv[0]) == "bash"
        and argv[1] == "-c"
        and argv[2].strip() == expected
    ]
    assert roots, "The required background pipeline is not running."

    valid = False
    for root in roots:
        family = descendants(root, processes)
        argvs = [processes[pid][1] for pid in family]
        has_source = any(argv and os.path.basename(argv[0]) in ("nc", "nc.openbsd") and argv[1:] == ["127.0.0.1", "9001"] for argv in argvs)
        has_mapper = any("/home/user/mapper.sh" in argv for argv in argvs)
        has_sink = any(argv and os.path.basename(argv[0]) in ("nc", "nc.openbsd") and argv[1:] == ["127.0.0.1", "9002"] for argv in argvs)
        if has_source and has_mapper and has_sink:
            valid = True
            break

    assert valid, "The background command does not contain the live 9001 -> mapper.sh -> 9002 pipeline."
    assert os.path.isfile("/home/user/pipeline.log"), "/home/user/pipeline.log was not created."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
