#!/bin/bash
mkdir -p /logs/verifier
rm -f /tmp/pow_preflight_ok

preflight_ok=1

cat > /home/user/requests.txt <<'EOF'
REQ001|3 4 +|7|210
REQ002|10 5 - 2 *|10|185
REQ003|5 5 +|10|100
REQ004|20 2 * 10 -|30|12
REQ005|7 8 *|56|215
EOF

if [ ! -d /home/user/pow-shield ]; then
    preflight_ok=0
else
    if ! (cd /home/user/pow-shield && timeout 180 /usr/bin/cargo test > /home/user/test_results.log 2>&1); then
        preflight_ok=0
    fi

    rm -f /home/user/results.log
    if [ ! -x /home/user/pow-shield/target/release/pow-shield ]; then
        preflight_ok=0
    elif ! (cd /home/user/pow-shield && timeout 30 ./target/release/pow-shield); then
        preflight_ok=0
    fi
fi

if [ "$preflight_ok" -eq 1 ]; then
    touch /tmp/pow_preflight_ok
fi

cat <<'TEST_EOF' > /tmp/test_final_state.py
import collections
import os
import random
import re
import subprocess

PROJECT = "/home/user/pow-shield"
BINARY = PROJECT + "/target/release/pow-shield"
REQUESTS = "/home/user/requests.txt"
RESULTS = "/home/user/results.log"


def test_preflight_completed():
    assert os.path.isfile("/tmp/pow_preflight_ok"), "cargo test or the canonical release-binary run failed."


def test_rust_project_exists():
    """Test that the Rust project pow-shield was created."""
    assert os.path.isdir(PROJECT), "The pow-shield directory does not exist."
    assert os.path.isfile(PROJECT + "/Cargo.toml"), "Cargo.toml is missing in pow-shield."
    assert os.path.isfile(PROJECT + "/src/main.rs"), "src/main.rs is missing in pow-shield."


def test_rust_code_requirements():
    """Test that the Rust code uses threads, mpsc, and has tests."""
    main_rs_path = PROJECT + "/src/main.rs"
    with open(main_rs_path, "r") as f:
        content = f.read()

    # Preserve the original source assertions.
    assert "std::thread" in content or "thread::" in content, "Code does not seem to use std::thread."
    assert "mpsc" in content, "Code does not seem to use mpsc channels."
    test_count = content.count("#[test]")
    assert test_count >= 2, f"Expected at least 2 unit tests, found {test_count}."

    # Do not allow comments alone to satisfy the concurrency checks.
    code = re.sub(r"/\*.*?\*/", "", content, flags=re.S)
    code = re.sub(r"//.*?$", "", code, flags=re.M)
    assert re.search(r"(?:thread::spawn|\.spawn\s*\()", code), "No worker-thread spawn was found in executable code."
    assert re.search(r"mpsc::(?:channel|sync_channel)\s*\(", code), "No mpsc channel construction was found in executable code."


def test_release_binary_exists():
    """Test that the project was built in release mode."""
    assert os.path.isfile(BINARY), f"Release binary not found at {BINARY}. Did you run cargo build --release?"
    assert os.access(BINARY, os.X_OK), "Release binary is not executable."
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", "The release artifact is not an ELF executable."


def test_results_log():
    """Test the output produced by executing the binary on the canonical input."""
    assert os.path.isfile(RESULTS), f"{RESULTS} does not exist."
    with open(RESULTS, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_results = {
        "REQ001: VALID",
        "REQ002: INVALID",
        "REQ003: INVALID",
        "REQ004: INVALID",
        "REQ005: INVALID",
    }
    assert len(lines) == len(expected_results), "results.log has missing, duplicate, or extra lines."
    assert set(lines) == expected_results, f"Results in {RESULTS} do not match expected output."


def test_test_results_log():
    """Test that the freshly executed cargo test run passed at least two tests."""
    log_path = "/home/user/test_results.log"
    assert os.path.isfile(log_path), f"{log_path} does not exist."
    with open(log_path, "r") as f:
        content = f.read()

    assert "test result: ok" in content, "test_results.log does not indicate successful test execution ('test result: ok')."
    passed_counts = [int(n) for n in re.findall(r"(\d+) passed", content)]
    if passed_counts:
        assert max(passed_counts) >= 2, f"Expected at least 2 tests to pass, but found {passed_counts}."
    else:
        assert content.count("... ok") >= 2, "Could not find at least 2 successful tests in test_results.log."


def checksum(expr):
    return sum(expr.encode("ascii")) % 256


def apply_op(a, b, op):
    if op == "+":
        return a + b
    if op == "-":
        return a - b
    return a * b


def test_release_binary_on_generated_requests():
    """Execute the submitted release binary on verifier-generated requests."""
    rng = random.SystemRandom()
    request_lines = []
    expected = []
    index = 1

    # Generate valid expressions whose answers and checksums are independently derived.
    valid_cases = []
    for _ in range(12):
        a, b, c = (rng.randint(-30, 30) for _ in range(3))
        op1 = rng.choice(["+", "-", "*"])
        op2 = rng.choice(["+", "-", "*"])
        separator = "  " if rng.choice([True, False]) else " "
        expr = f"{a}{separator}{b} {op1} {c} {op2}"
        value = apply_op(apply_op(a, b, op1), c, op2)
        valid_cases.append((expr, value))

    for expr, value in valid_cases:
        rid = f"DYN{index:03d}"
        index += 1
        request_lines.append(f"{rid}|{expr}|{value}|{checksum(expr)}")
        expected.append(f"{rid}: VALID")

    # Correct checksum but deliberately incorrect claimed result.
    for expr, value in valid_cases[:5]:
        rid = f"DYN{index:03d}"
        index += 1
        request_lines.append(f"{rid}|{expr}|{value + 1}|{checksum(expr)}")
        expected.append(f"{rid}: INVALID")

    # Correct result but deliberately incorrect checksum.
    for expr, value in valid_cases[5:10]:
        rid = f"DYN{index:03d}"
        index += 1
        bad_checksum = (checksum(expr) + rng.randint(1, 255)) % 256
        request_lines.append(f"{rid}|{expr}|{value}|{bad_checksum}")
        expected.append(f"{rid}: INVALID")

    # Invalid RPN syntax with otherwise correctly calculated checksums.
    malformed = [("1 +", 1), ("1 2", 2), ("4 2 /", 2), ("x 2 +", 2), ("3 4 + +", 7)]
    for expr, claimed in malformed:
        rid = f"DYN{index:03d}"
        index += 1
        request_lines.append(f"{rid}|{expr}|{claimed}|{checksum(expr)}")
        expected.append(f"{rid}: INVALID")

    rng.shuffle(request_lines)
    with open(REQUESTS, "w", newline="\n") as f:
        f.write("\n".join(request_lines) + "\n")
    if os.path.exists(RESULTS):
        os.remove(RESULTS)

    completed = subprocess.run(
        [BINARY], cwd=PROJECT, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, timeout=30
    )
    assert completed.returncode == 0, f"Release binary failed: {completed.stderr}"
    assert os.path.isfile(RESULTS), "Release binary did not create /home/user/results.log."

    with open(RESULTS, "r") as f:
        actual = [line.strip() for line in f if line.strip()]
    assert collections.Counter(actual) == collections.Counter(expected), (
        "Release binary produced incorrect results for verifier-generated requests."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
