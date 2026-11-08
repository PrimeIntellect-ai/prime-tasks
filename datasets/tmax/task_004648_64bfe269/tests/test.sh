#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess


def test_verifier_c_exists():
    file_path = "/home/user/verifier.c"
    assert os.path.exists(file_path), f"Source file {file_path} is missing."
    assert os.path.isfile(file_path), f"{file_path} is not a file."


def test_verifier_executable_exists():
    file_path = "/home/user/verifier"
    assert os.path.exists(file_path), f"Executable file {file_path} is missing."
    assert os.path.isfile(file_path), f"{file_path} is not a file."
    assert os.access(file_path, os.X_OK), f"{file_path} is not executable."
    with open(file_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{file_path} is not a compiled executable."


def test_verification_out_exists():
    file_path = "/home/user/verification_out.txt"
    assert os.path.exists(file_path), f"Output file {file_path} is missing."
    assert os.path.isfile(file_path), f"{file_path} is not a file."


def test_verification_out_content():
    file_path = "/home/user/verification_out.txt"
    expected_results = [
        "Job1: 4",
        "Job2: RATE_LIMIT",
        "Job3: 15",
        "Job4: ERROR",
        "Job5: 11",
        "Job6: ERROR",
        "Job7: 1"
    ]

    with open(file_path, "r") as f:
        actual_lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(actual_lines) == len(expected_results), f"Expected {len(expected_results)} lines in {file_path}, but got {len(actual_lines)}."
    for i, (actual, expected) in enumerate(zip(actual_lines, expected_results)):
        actual_normalized = actual.replace(" ", "")
        expected_normalized = expected.replace(" ", "")
        assert actual_normalized == expected_normalized, f"Mismatch on line {i+1}. Expected '{expected}', got '{actual}'."


def integer_sqrt(value):
    lo, hi = 0, value
    answer = 0
    while lo <= hi:
        mid = (lo + hi) // 2
        square = mid * mid
        if square <= value:
            answer = mid
            lo = mid + 1
        else:
            hi = mid - 1
    return answer


def emulate(code):
    stack = []
    pc = 0
    checks = 0
    while pc < len(code):
        opcode = code[pc]
        pc += 1

        if opcode == 0x01:
            if pc >= len(code) or len(stack) >= 16:
                return "ERROR"
            value = code[pc]
            pc += 1
            stack.append(value - 256 if value >= 128 else value)
        elif opcode in (0x02, 0x03, 0x04):
            if len(stack) < 2:
                return "ERROR"
            a = stack.pop()
            b = stack.pop()
            if opcode == 0x02:
                stack.append(b + a)
            elif opcode == 0x03:
                stack.append(b - a)
            else:
                stack.append(b * a)
        elif opcode == 0x05:
            if not stack:
                return "ERROR"
            value = stack.pop()
            if value < 0:
                return "ERROR"
            stack.append(integer_sqrt(value))
        elif opcode == 0x06:
            if checks >= 3:
                return "RATE_LIMIT"
            if not stack:
                return "ERROR"
            checks += 1
            value = stack.pop()
            stack.append(1 if value > 0 else 0)
        elif opcode == 0xFF:
            return str(stack[-1] if stack else 0)
        else:
            return "ERROR"
    return "ERROR"


def push(value):
    return [0x01, value & 0xFF]


def make_dynamic_jobs():
    rng = secrets.SystemRandom()
    programs = []

    programs.extend([
        [0xFF],
        [0x02, 0xFF],
        push(-1) + [0x05, 0xFF],
        push(7) + [0xFF, 0x02, 0x02],
        sum((push(i) for i in range(17)), []) + [0xFF],
        sum((push(i) for i in range(16)), []) + [0x02, 0xFF],
        push(1) + [0x06] + push(2) + [0x06] + push(3) + [0x06] + push(4) + [0x06, 0xFF],
        push(1) + [0x06] + push(0) + [0x06] + push(-1) + [0x06, 0xFF],
    ])

    unknowns = [x for x in range(256) if x not in (0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0xFF)]
    for _ in range(72):
        kind = rng.randrange(9)
        a = rng.randint(-120, 120)
        b = rng.randint(-120, 120)
        c = rng.randint(-20, 20)

        if kind == 0:
            program = push(a) + push(b) + [rng.choice([0x02, 0x03, 0x04]), 0xFF]
        elif kind == 1:
            program = push(a) + push(b) + [0x02] + push(c) + [0x04, 0xFF]
        elif kind == 2:
            n = rng.randint(0, 127)
            program = push(n) + [0x05, 0xFF]
        elif kind == 3:
            n = rng.randint(-120, 120)
            program = push(n) + push(n) + [0x04, 0x05, 0xFF]
        elif kind == 4:
            program = push(a) + [0x06, 0xFF]
        elif kind == 5:
            program = push(a) + push(b) + [0x03, 0x06, 0xFF]
        elif kind == 6:
            program = push(a) + [rng.choice(unknowns), 0xFF]
        elif kind == 7:
            program = [rng.choice([0x02, 0x03, 0x04, 0x05, 0x06]), 0xFF]
        else:
            values = [rng.randint(-30, 30) for _ in range(4)]
            program = push(values[0]) + push(values[1]) + [0x02] + push(values[2]) + [0x03] + push(values[3]) + [0x04, 0xFF]
        programs.append(program)

    jobs = []
    for index, program in enumerate(programs):
        job_id = f"Dynamic{index:03d}{rng.randrange(0x10000):04X}"
        jobs.append((job_id, bytes(program)))
    return jobs


def run_and_check(executable, jobs):
    input_path = "/home/user/pipeline_jobs.txt"
    output_path = "/home/user/verification_out.txt"
    with open(input_path, "w") as f:
        for job_id, code in jobs:
            f.write(f"{job_id}:{code.hex().upper()}\n")

    if os.path.exists(output_path):
        os.remove(output_path)

    completed = subprocess.run([executable], cwd="/home/user", stdout=subprocess.PIPE,
                               stderr=subprocess.PIPE, text=True, timeout=10)
    assert completed.returncode == 0, f"{executable} exited with {completed.returncode}: {completed.stderr}"
    assert os.path.isfile(output_path), f"{executable} did not create {output_path}."

    with open(output_path, "r") as f:
        actual = [line.strip().replace(" ", "") for line in f if line.strip()]
    expected = [f"{job_id}:{emulate(code)}" for job_id, code in jobs]
    assert actual == expected, f"Incorrect VM results from {executable}. Expected {expected}, got {actual}."


def test_dynamic_vm_execution():
    compiled_path = "/tmp/submission_verifier"
    compilation = subprocess.run(
        ["gcc", "/home/user/verifier.c", "-o", compiled_path],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=15
    )
    assert compilation.returncode == 0, f"verifier.c does not compile: {compilation.stderr}"

    jobs = make_dynamic_jobs()
    run_and_check("/home/user/verifier", jobs)
    run_and_check(compiled_path, jobs)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
