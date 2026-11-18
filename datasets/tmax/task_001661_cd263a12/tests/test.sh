#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import re
import subprocess
import glob
import random
import secrets
import tempfile
import cv2
import pytest


def find_validator():
    # Try common names/extensions
    for ext in ['.py', '.sh', '.js', '']:
        path = f"/home/user/validator{ext}"
        if os.path.isfile(path):
            return path
    # Fallback to glob
    matches = glob.glob("/home/user/validator*")
    if matches:
        return matches[0]
    return None


def validator_command(script_path, target_file):
    if script_path.endswith('.py'):
        return ["python3", script_path, target_file]
    elif script_path.endswith('.js'):
        return ["node", script_path, target_file]
    elif script_path.endswith('.sh') or os.access(script_path, os.X_OK):
        return [script_path, target_file]
    return ["python3", script_path, target_file]  # fallback


def run_validator(script_path, target_file):
    cmd = validator_command(script_path, target_file)
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=5)
        return result.stdout.strip()
    except subprocess.TimeoutExpired:
        return "TIMEOUT"
    except Exception as e:
        return f"ERROR: {e}"


def extract_seed():
    cap = cv2.VideoCapture('/app/sync_signal.mp4')
    assert cap.isOpened(), "Could not open synchronization video"
    bits = []
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        bits.append(1 if float(frame.mean()) > 127.0 else 0)
    cap.release()
    assert len(bits) == 10, f"Expected 10 video frames, found {len(bits)}"
    seed = 0
    for bit in bits:
        seed = (seed << 1) | bit
    return seed


def reference_accept(raw, seed):
    lines = raw.splitlines(keepends=True)
    if not lines:
        return False

    header = lines[0]
    if header.endswith('\n'):
        header = header[:-1]
    match = re.fullmatch(r'CHECKSUM: (-?\d+)', header)
    if not match:
        return False

    instruction_text = ''.join(lines[1:])
    if int(match.group(1)) != sum(ord(c) for c in instruction_text) + seed:
        return False

    instructions = instruction_text.splitlines()
    if not instructions:
        return False

    stack = []
    ip = 0
    for _ in range(100):
        if ip < 0 or ip >= len(instructions):
            return False
        instruction = instructions[ip]

        push = re.fullmatch(r'PUSH ([+-]?\d+)', instruction)
        jump = re.fullmatch(r'JMP ([+-]?\d+)', instruction)
        if push:
            if len(stack) >= 10:
                return False
            stack.append(int(push.group(1)))
            ip += 1
        elif instruction == 'POP':
            if not stack:
                return False
            stack.pop()
            ip += 1
        elif instruction == 'ADD':
            if len(stack) < 2:
                return False
            a = stack.pop()
            b = stack.pop()
            stack.append(b + a)
            ip += 1
        elif instruction == 'SUB':
            if len(stack) < 2:
                return False
            a = stack.pop()
            b = stack.pop()
            stack.append(b - a)
            ip += 1
        elif jump:
            ip += int(jump.group(1))
            if ip < 0 or ip >= len(instructions):
                return False
        elif instruction == 'HALT':
            return True
        else:
            return False
    return False


def make_payload(seed, instructions, checksum_delta=0):
    instruction_text = '\n'.join(instructions) + '\n'
    checksum = sum(ord(c) for c in instruction_text) + seed + checksum_delta
    return f"CHECKSUM: {checksum}\n{instruction_text}"


def test_validator_exists():
    script_path = find_validator()
    assert script_path is not None, "Could not find validator script in /home/user/"


def test_clean_corpus():
    script_path = find_validator()
    if not script_path:
        pytest.fail("Validator script missing.")

    clean_dir = "/app/corpus/clean"
    assert os.path.isdir(clean_dir), f"{clean_dir} missing"

    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if os.path.isfile(os.path.join(clean_dir, f))]
    assert len(clean_files) > 0, "Clean corpus is empty."

    failed_files = []
    for f in clean_files:
        output = run_validator(script_path, f)
        if output != "ACCEPT":
            failed_files.append((os.path.basename(f), output))

    if failed_files:
        details = ", ".join([f"{name} (got {out})" for name, out in failed_files])
        pytest.fail(f"{len(failed_files)} of {len(clean_files)} clean files were incorrectly rejected or errored: {details}")


def test_evil_corpus():
    script_path = find_validator()
    if not script_path:
        pytest.fail("Validator script missing.")

    evil_dir = "/app/corpus/evil"
    assert os.path.isdir(evil_dir), f"{evil_dir} missing"

    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if os.path.isfile(os.path.join(evil_dir, f))]
    assert len(evil_files) > 0, "Evil corpus is empty."

    failed_files = []
    for f in evil_files:
        output = run_validator(script_path, f)
        if output != "REJECT":
            failed_files.append((os.path.basename(f), output))

    if failed_files:
        details = ", ".join([f"{name} (got {out})" for name, out in failed_files])
        pytest.fail(f"{len(failed_files)} of {len(evil_files)} evil files bypassed validation: {details}")


def test_generated_unseen_payloads():
    script_path = find_validator()
    if not script_path:
        pytest.fail("Validator script missing.")

    seed = extract_seed()
    rng = random.SystemRandom()
    a, b, c = [rng.randint(-1000000, 1000000) for _ in range(3)]

    exact_depth = [f"PUSH {rng.randint(-9999, 9999)}" for _ in range(10)] + ["ADD"] * 9 + ["HALT"]
    hundred_steps = sum(([f"PUSH {rng.randint(-9999, 9999)}", "POP"] for _ in range(49)), []) + [f"PUSH {a}", "HALT"]
    hundred_one_steps = sum(([f"PUSH {rng.randint(-9999, 9999)}", "POP"] for _ in range(50)), []) + ["HALT"]

    specs = [
        ([f"PUSH {a}", f"PUSH {b}", "ADD", f"PUSH {c}", "SUB", "HALT"], 0),
        ([f"PUSH {a}", "JMP 3", "POP", "POP", f"PUSH {b}", "ADD", "HALT"], 0),
        (exact_depth, 0),
        (hundred_steps, 0),
        (hundred_one_steps, 0),
        ([f"PUSH {a}", "HALT"], rng.choice([-9, -3, 1, 7, 13])),
        (["POP", "HALT"], 0),
        ([f"PUSH {a}", "ADD", "HALT"], 0),
        ([f"PUSH {a}", "SUB", "HALT"], 0),
        ([f"PUSH {i}" for i in range(11)] + ["HALT"], 0),
        (["JMP 0"], 0),
        ([f"PUSH {a}", "POP", "JMP -2"], 0),
        (["JMP -1", "HALT"], 0),
        (["JMP 2", "HALT"], 0),
        ([f"PUSH {a}"], 0),
        ([f"PUSH {a}", "BOGUS", "HALT"], 0),
        (["PUSH not_an_integer", "HALT"], 0),
        (["JMP nope", "HALT"], 0),
        ([f"PUSH {a} extra", "HALT"], 0),
        (["POP extra", "HALT"], 0),
    ]
    rng.shuffle(specs)

    case_dir = tempfile.mkdtemp()
    outcomes = set()
    for instructions, delta in specs:
        raw = make_payload(seed, instructions, delta)
        expected = "ACCEPT" if reference_accept(raw, seed) else "REJECT"
        outcomes.add(expected)
        path = os.path.join(case_dir, secrets.token_hex(12) + '.txt')
        with open(path, 'w', encoding='ascii', newline='') as handle:
            handle.write(raw)

        try:
            result = subprocess.run(
                validator_command(script_path, path),
                capture_output=True,
                text=True,
                timeout=5,
            )
        except subprocess.TimeoutExpired:
            pytest.fail(f"Validator timed out on generated payload {os.path.basename(path)}")

        assert result.returncode == 0, (
            f"Validator exited with {result.returncode} on generated payload "
            f"{os.path.basename(path)}: {result.stderr}"
        )
        assert result.stdout.strip() == expected, (
            f"Generated payload {os.path.basename(path)} expected {expected}, "
            f"got {result.stdout!r}"
        )

    assert outcomes == {"ACCEPT", "REJECT"}
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
