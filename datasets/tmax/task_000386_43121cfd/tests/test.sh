#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import requests
import time
import random
import pytest

def test_retroapi_emulator_and_ratelimit():
    score = 0
    total = 80

    # Test 1: Rate limiting (30 requests in quick succession)
    # Reset any states by waiting 1.1 seconds
    time.sleep(1.1)
    status_codes = []
    for _ in range(30):
        try:
            r = requests.post("http://127.0.0.1:8000/run", json={"asm": "LOAD r0 1"}, timeout=0.5)
            status_codes.append(r.status_code)
        except Exception:
            status_codes.append(500)

    successes = status_codes.count(200)
    ratelimits = status_codes.count(429)

    # We expect roughly 20 successes and 10 rate limits. We'll grant points for each correct bucket.
    score += min(20, successes)
    score += min(10, ratelimits)

    # Test 2: Emulator accuracy (50 programs)
    # Wait to clear rate limit
    time.sleep(1.1)

    test_programs = [
        ("LOAD r0 5\nLOAD r1 10\nADD r0 r1", {"r0": 15, "r1": 10, "r2": 0, "r3": 0}),
        ("LOAD r2 3\nLOAD r3 4\nMUL r2 r3", {"r0": 0, "r1": 0, "r2": 12, "r3": 4}),
        ("LOAD r0 10\nLOAD r1 3\nSUB r0 r1", {"r0": 7, "r1": 3, "r2": 0, "r3": 0}),
    ]

    # Generate remaining programs programmatically for the test
    random.seed(42) # Use fixed seed for reproducibility in tests
    for _ in range(47):
        regs = {"r0": 0, "r1": 0, "r2": 0, "r3": 0}
        prog = []
        for _ in range(5):
            op = random.choice(["LOAD", "ADD", "SUB", "MUL"])
            rA = random.choice(["r0", "r1", "r2", "r3"])
            rB = random.choice(["r0", "r1", "r2", "r3"])
            if op == "LOAD":
                val = random.randint(1, 20)
                prog.append(f"LOAD {rA} {val}")
                regs[rA] = val
            elif op == "ADD":
                prog.append(f"ADD {rA} {rB}")
                regs[rA] = regs[rA] + regs[rB]
            elif op == "SUB":
                prog.append(f"SUB {rA} {rB}")
                regs[rA] = regs[rA] - regs[rB]
            elif op == "MUL":
                prog.append(f"MUL {rA} {rB}")
                regs[rA] = regs[rA] * regs[rB]
        test_programs.append(("\n".join(prog), regs))

    for asm, expected in test_programs:
        time.sleep(0.06) # avoid rate limit (20/sec = 1 per 50ms)
        try:
            r = requests.post("http://127.0.0.1:8000/run", json={"asm": asm}, timeout=1)
            if r.status_code == 200:
                data = r.json()
                # Check if all register values match
                if all(data.get(k) == expected[k] for k in expected):
                    score += 1
        except Exception:
            pass

    accuracy = score / total

    assert accuracy >= 0.95, f"Emulator accuracy {accuracy} is below the threshold of 0.95. Score: {score}/{total}. Rate limit successes: {successes}, rate limits: {ratelimits}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
