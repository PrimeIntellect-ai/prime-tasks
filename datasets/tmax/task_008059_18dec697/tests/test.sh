#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess

PROJECT_DIR = "/home/user/billing-service"
MAIN_PATH = os.path.join(PROJECT_DIR, "src", "main.rs")
LOG_PATH = "/home/user/trace_output.log"
TRACE_ID = "TXN-7734-ALPHA-09"
U64_MAX = (1 << 64) - 1


def run_main(source):
    with open(MAIN_PATH, "w") as f:
        f.write(source)
    try:
        return subprocess.run(
            ["cargo", "run", "--quiet"],
            cwd=PROJECT_DIR,
            capture_output=True,
            text=True,
        )
    finally:
        if os.path.exists(MAIN_PATH):
            os.remove(MAIN_PATH)


def expected_cost(base, multiplier, discount):
    subtotal = min(base * multiplier, U64_MAX)
    return subtotal, max(subtotal - discount, 0)


def test_resolution_txt_correct():
    path = "/home/user/resolution.txt"
    assert os.path.isfile(path), f"Resolution file {path} does not exist."

    with open(path, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(lines) >= 2, f"Expected at least 2 lines in {path}, found {len(lines)}"
    assert lines[0] == "TRACE_ID: TXN-7734-ALPHA-09", f"Line 1 incorrect. Got: {lines[0]}"
    assert lines[1] == "FIXED_TEST_COST: 0", f"Line 2 incorrect. Got: {lines[1]}"


def test_original_rust_code_behavior():
    if os.path.exists(LOG_PATH):
        os.remove(LOG_PATH)

    result = run_main("""
fn main() {
    let cost = billing_service::calculator::calculate_cost(1500, 3, 5000);
    println!("{}", cost);
}
""")

    assert result.returncode == 0, f"Cargo build/run failed:\n{result.stderr}"
    output = result.stdout.strip()
    assert output == "0", f"Expected calculated cost to be 0, but got: {output}"
    assert os.path.isfile(LOG_PATH), f"Log file {LOG_PATH} was not created by the function."

    with open(LOG_PATH, "r") as f:
        log_content = f.read()

    expected_log = "[TXN-7734-ALPHA-09] Intermediate Subtotal: 4500"
    assert expected_log in log_content, (
        f"Expected log entry '{expected_log}' not found in {LOG_PATH}. "
        f"Content:\n{log_content}"
    )


def test_saturating_behavior_and_tracing_across_inputs():
    rng = secrets.SystemRandom()
    cases = [
        (0, U64_MAX, U64_MAX),
        (U64_MAX, 2, 0),
        (U64_MAX, U64_MAX, U64_MAX - 1),
        (U64_MAX, 2, U64_MAX),
        (1, 1, 0),
        (5000, 3, 1000),
        (20, 30, 600),
        (20, 30, 601),
    ]

    # Random non-overflowing products exercise ordinary subtraction and underflow.
    for _ in range(12):
        base = rng.randrange(0, 1_000_000_001)
        multiplier = rng.randrange(0, 1_000_000_001)
        product = base * multiplier
        discount = rng.randrange(0, min(U64_MAX, product * 2 + 2) + 1)
        cases.append((base, multiplier, discount))

    # Full-width values make multiplication overflow overwhelmingly likely.
    for _ in range(12):
        cases.append((rng.getrandbits(64), rng.getrandbits(64), rng.getrandbits(64)))

    rust_cases = ",\n        ".join(
        f"({base}u64, {multiplier}u64, {discount}u64)"
        for base, multiplier, discount in cases
    )
    source = f"""
fn main() {{
    let cases: &[(u64, u64, u64)] = &[
        {rust_cases}
    ];
    for &(base, multiplier, discount) in cases {{
        let cost = billing_service::calculator::calculate_cost(base, multiplier, discount);
        println!("{{}}", cost);
    }}
}}
"""

    if os.path.exists(LOG_PATH):
        os.remove(LOG_PATH)

    result = run_main(source)
    assert result.returncode == 0, f"Cargo build/run failed on varied inputs:\n{result.stderr}"

    expected = [expected_cost(*case) for case in cases]
    expected_outputs = [str(cost) for _, cost in expected]
    actual_outputs = result.stdout.splitlines()
    assert actual_outputs == expected_outputs, (
        f"Incorrect results for varied inputs.\nCases: {cases}\n"
        f"Expected: {expected_outputs}\nActual: {actual_outputs}"
    )

    assert os.path.isfile(LOG_PATH), f"Log file {LOG_PATH} was not created by the function."
    with open(LOG_PATH, "r") as f:
        actual_logs = f.read().splitlines()

    expected_logs = [
        f"[{TRACE_ID}] Intermediate Subtotal: {subtotal}"
        for subtotal, _ in expected
    ]
    assert actual_logs == expected_logs, (
        "Intermediate tracing did not match the saturating subtotal for every call.\n"
        f"Expected: {expected_logs}\nActual: {actual_logs}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
