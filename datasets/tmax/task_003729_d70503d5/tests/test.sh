#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import stat
import subprocess
import tempfile

import pytest

SOURCE = "/home/user/sec_parser.c"
SERVER = "/home/user/sec_server"
FUZZER = "/home/user/sec_fuzzer"
INPUTS = "/home/user/inputs.txt"
REPORT = "/home/user/qa_report.log"

EXPECTED_INPUTS = (
    "SEC-PROTO V1.5.1\n"
    "SEC-PROTO V1.5.2\n"
    "SEC-PROTO V2.0.0\n"
    "SEC-PROTO V1.4.99\n"
    "SEC-PROTO V1.a.2\n"
    "UNKNOWN V1.5.2\n"
)

EXPECTED_REPORT = (
    "[REJECTED] Insecure version\n"
    "[ACCEPTED] Secure version\n"
    "[ACCEPTED] Secure version\n"
    "[REJECTED] Insecure version\n"
    "[ERROR] Invalid version format\n"
    "[ERROR] Malformed prefix\n"
)


def run(path, input_text):
    return subprocess.run(
        [path], input=input_text, text=True, capture_output=True, timeout=5
    )


def expected_for(line):
    prefix = "SEC-PROTO V"
    if not line.startswith(prefix):
        return "[ERROR] Malformed prefix", 1

    version = line[len(prefix):]
    parts = version.split(".")
    if len(parts) != 3 or any(not p or not p.isascii() or not p.isdigit() for p in parts):
        return "[ERROR] Invalid version format", 1

    parsed = tuple(int(p) for p in parts)
    if parsed < (1, 5, 2):
        return "[REJECTED] Insecure version", 2
    return "[ACCEPTED] Secure version", 0


def generated_cases():
    rng = random.Random(secrets.randbits(128))
    cases = []

    # Fresh semantic versions make a fixed lookup-table implementation insufficient.
    for _ in range(70):
        major = rng.randrange(0, 50)
        minor = rng.randrange(0, 100)
        patch = rng.randrange(0, 100)
        cases.append(f"SEC-PROTO V{major}.{minor}.{patch}")

    for _ in range(20):
        a, b, c, d = [rng.randrange(0, 100) for _ in range(4)]
        malformed_versions = [
            f"SEC-PROTO V{a}.{b}",
            f"SEC-PROTO V{a}..{c}",
            f"SEC-PROTO V{a}.x{b}.{c}",
            f"SEC-PROTO V{a}.{b}.{c}tail",
            f"SEC-PROTO V+{a}.{b}.{c}",
            f"SEC-PROTO V{a}.{b}.{c}.{d}",
        ]
        cases.append(rng.choice(malformed_versions))

    for _ in range(20):
        token = secrets.token_hex(6)
        cases.append(f"OTHER-{token} V{rng.randrange(10)}.{rng.randrange(10)}.{rng.randrange(10)}")

    rng.shuffle(cases)
    return cases


@pytest.fixture(scope="session")
def rebuilt_programs():
    with tempfile.TemporaryDirectory(prefix="sec_rebuild_") as directory:
        server = os.path.join(directory, "sec_server")
        fuzzer = os.path.join(directory, "sec_fuzzer")

        normal_build = subprocess.run(
            ["gcc", SOURCE, "-o", server], text=True, capture_output=True, timeout=20
        )
        assert normal_build.returncode == 0, (
            "sec_parser.c does not compile in normal mode:\n" + normal_build.stderr
        )

        fuzz_build = subprocess.run(
            ["gcc", "-DFUZZ_MODE", SOURCE, "-o", fuzzer],
            text=True,
            capture_output=True,
            timeout=20,
        )
        assert fuzz_build.returncode == 0, (
            "sec_parser.c does not compile with -DFUZZ_MODE:\n" + fuzz_build.stderr
        )
        yield server, fuzzer


def test_files_exist():
    artifacts = [SOURCE, SERVER, FUZZER, INPUTS, REPORT]
    for artifact in artifacts:
        assert os.path.exists(artifact), f"Missing expected file: {artifact}"


def test_submitted_programs_are_native_executables():
    for artifact in (SERVER, FUZZER):
        mode = os.stat(artifact).st_mode
        assert stat.S_ISREG(mode), f"{artifact} must be a regular executable file"
        assert os.access(artifact, os.X_OK), f"{artifact} is not executable"
        with open(artifact, "rb") as f:
            assert f.read(4) == b"\x7fELF", f"{artifact} is not a compiled ELF executable"


def test_inputs_content_is_exact():
    with open(INPUTS, "r") as f:
        assert f.read() == EXPECTED_INPUTS, "inputs.txt does not contain exactly the required six lines"


def test_qa_report_content():
    with open(REPORT, "r") as f:
        content = f.read()
    assert content.strip() == EXPECTED_REPORT.strip(), "qa_report.log content does not match expected output."


def test_qa_report_matches_live_fuzzer_run():
    process = run(FUZZER, EXPECTED_INPUTS)
    assert process.stdout == EXPECTED_REPORT
    with open(REPORT, "r") as f:
        assert f.read().strip() == process.stdout.strip()


def test_sec_fuzzer_behavior():
    test_input = "SEC-PROTO V1.6.0\nSEC-PROTO V0.9.9\nSEC-PROTO V1.5.1\nMALFORMED V2.0.0\n"
    expected_output = (
        "[ACCEPTED] Secure version\n"
        "[REJECTED] Insecure version\n"
        "[REJECTED] Insecure version\n"
        "[ERROR] Malformed prefix\n"
    )
    process = run(FUZZER, test_input)
    assert process.stdout.strip() == expected_output.strip(), "sec_fuzzer output is incorrect for test inputs."


def test_sec_server_behavior_accepted():
    process = run(SERVER, "SEC-PROTO V1.5.2\n")
    assert "Listening..." in process.stdout, "sec_server should print 'Listening...'"
    assert "[ACCEPTED] Secure version" in process.stdout, "sec_server did not accept valid version."
    assert process.returncode == 0, f"Expected return code 0, got {process.returncode}"


def test_sec_server_behavior_rejected():
    process = run(SERVER, "SEC-PROTO V1.4.9\n")
    assert "Listening..." in process.stdout, "sec_server should print 'Listening...'"
    assert "[REJECTED] Insecure version" in process.stdout, "sec_server did not reject insecure version."
    assert process.returncode == 2, f"Expected return code 2, got {process.returncode}"


def test_sec_server_behavior_error():
    process = run(SERVER, "BAD-PROTO V1.5.2\n")
    assert "Listening..." in process.stdout, "sec_server should print 'Listening...'"
    assert "[ERROR] Malformed prefix" in process.stdout, "sec_server did not error on bad prefix."
    assert process.returncode == 1, f"Expected return code 1, got {process.returncode}"


def test_sec_server_behavior_format_error():
    process = run(SERVER, "SEC-PROTO V1.a.2\n")
    assert "Listening..." in process.stdout, "sec_server should print 'Listening...'"
    assert "[ERROR] Invalid version format" in process.stdout, "sec_server did not error on invalid version format."
    assert process.returncode == 1, f"Expected return code 1, got {process.returncode}"


def test_randomized_fuzzer_behavior_for_submitted_and_rebuilt(rebuilt_programs):
    rebuilt_server, rebuilt_fuzzer = rebuilt_programs
    cases = generated_cases()
    test_input = "\n".join(cases) + "\n"
    expected_output = "".join(expected_for(case)[0] + "\n" for case in cases)

    for executable in (FUZZER, rebuilt_fuzzer):
        process = run(executable, test_input)
        assert process.stdout == expected_output, f"{executable} failed generated parser cases"
        assert "Listening..." not in process.stdout, f"{executable} printed the server prompt in FUZZ_MODE"


def test_randomized_server_behavior_for_submitted_and_rebuilt(rebuilt_programs):
    rebuilt_server, rebuilt_fuzzer = rebuilt_programs
    cases = generated_cases()[:24]

    for executable in (SERVER, rebuilt_server):
        for case in cases:
            expected_message, expected_code = expected_for(case)
            process = run(executable, case + "\n")
            assert "Listening..." in process.stdout, f"{executable} omitted the server prompt"
            assert expected_message in process.stdout, f"{executable} misclassified generated input {case!r}"
            assert process.returncode == expected_code, (
                f"{executable} returned {process.returncode} for {case!r}; expected {expected_code}"
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
