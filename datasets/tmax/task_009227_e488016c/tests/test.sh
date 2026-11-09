#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess
import tempfile

SOURCE = "/home/user/log_processor.c"
EXECUTABLE = "/home/user/log_processor"
OUTPUT = "/home/user/processed.log"
COMPILED = "/tmp/log_processor_test"


def test_c_source_exists():
    assert os.path.exists(SOURCE), "The source file /home/user/log_processor.c is missing."
    assert os.path.isfile(SOURCE), "/home/user/log_processor.c is not a regular file."


def test_executable_exists():
    assert os.path.exists(EXECUTABLE), "The executable /home/user/log_processor is missing."
    assert os.path.isfile(EXECUTABLE), "/home/user/log_processor is not a regular file."
    assert os.access(EXECUTABLE, os.X_OK), "/home/user/log_processor is not executable."


def test_processed_log_content():
    expected_content = """99 10.0.0.1 PRE
100 10.0.0.1 START
100 10.0.0.2 START
101 10.0.0.1 ACTION
101 10.0.0.2 ACTION
102 10.0.0.1 ACTION
102 10.0.0.2 END
102 10.0.0.3 START
105 10.0.0.1 END
"""
    assert os.path.exists(OUTPUT), "/home/user/processed.log is missing."
    with open(OUTPUT, "r") as f:
        content = f.read()
    assert content == expected_content, "Content of /home/user/processed.log does not match expected output for the provided logs."


def compile_submission():
    result = subprocess.run(
        ["gcc", "-O3", SOURCE, "-o", COMPILED],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, f"Compilation failed:\n{result.stderr}"
    assert os.path.isfile(COMPILED) and os.access(COMPILED, os.X_OK)


def run_and_read(executable, log1, log2):
    if os.path.exists(OUTPUT):
        os.remove(OUTPUT)
    result = subprocess.run(
        [executable, log1, log2],
        capture_output=True,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, f"Execution failed for {executable}:\n{result.stderr}"
    assert os.path.exists(OUTPUT), "processed.log was not created by the executable."
    with open(OUTPUT, "rb") as f:
        return f.read()


def oracle(entries):
    entries = sorted(entries, key=lambda e: (e[0], e[1], e[2]))
    last_allowed = {}
    kept = []
    for timestamp, ip, action in entries:
        if ip not in last_allowed or timestamp > last_allowed[ip]:
            kept.append((timestamp, ip, action))
            last_allowed[ip] = timestamp
    return "".join(f"{t} {ip} {action}\n" for t, ip, action in kept).encode()


def test_hidden_test_case():
    compile_submission()

    log1 = "/tmp/hidden_server1.log"
    log2 = "/tmp/hidden_server2.log"
    with open(log1, "w") as f:
        f.write("10 10.0.0.1 A\n20 10.0.0.1 B\n20 10.0.0.2 A\n")
    with open(log2, "w") as f:
        f.write("15 10.0.0.1 C\n20 10.0.0.1 A\n25 10.0.0.2 B\n")

    expected_hidden_output = b"""10 10.0.0.1 A
15 10.0.0.1 C
20 10.0.0.1 A
20 10.0.0.2 A
25 10.0.0.2 B
"""
    hidden_content = run_and_read(COMPILED, log1, log2)
    assert hidden_content == expected_hidden_output, (
        f"Hidden test case output does not match expected logic. Expected:\n"
        f"{expected_hidden_output.decode()}\nGot:\n{hidden_content.decode(errors='replace')}"
    )


def test_randomized_general_behavior():
    rng = secrets.SystemRandom()
    actions = ["A", "B2", "LOGIN", "LOGOUT9", "PING", "START7", "ZED"]

    with tempfile.TemporaryDirectory(prefix="log_processor_cases_") as directory:
        for case_number in range(10):
            ips = [
                f"10.{rng.randrange(0, 256)}.{rng.randrange(0, 256)}.{i}"
                for i in range(1, 7)
            ]
            entries = []
            for _ in range(35 + case_number):
                entries.append((
                    rng.randrange(-5000, 5001),
                    rng.choice(ips),
                    rng.choice(actions),
                ))

            # Force equal-timestamp ordering/rate-limit cases into every trial.
            tied_ip = rng.choice(ips)
            tied_time = rng.randrange(-1000, 1001)
            entries.extend([
                (tied_time, tied_ip, "ZED"),
                (tied_time, tied_ip, "A"),
                (tied_time, rng.choice([ip for ip in ips if ip != tied_ip]), "B2"),
                (tied_time + 1, tied_ip, "LOGIN"),
                (tied_time - 1, tied_ip, "PING"),
            ])

            rng.shuffle(entries)
            split = rng.randrange(1, len(entries))
            first, second = entries[:split], entries[split:]
            log1 = os.path.join(directory, f"{case_number}_a.log")
            log2 = os.path.join(directory, f"{case_number}_b.log")
            with open(log1, "w") as f:
                for t, ip, action in first:
                    f.write(f"{t} {ip} {action}\n")
            with open(log2, "w") as f:
                for t, ip, action in second:
                    f.write(f"{t} {ip} {action}\n")

            expected = oracle(entries)
            for executable in (COMPILED, EXECUTABLE):
                actual = run_and_read(executable, log1, log2)
                assert actual == expected, (
                    f"Incorrect output for randomized case {case_number} using {executable}.\n"
                    f"Expected:\n{expected.decode()}\nGot:\n{actual.decode(errors='replace')}"
                )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
