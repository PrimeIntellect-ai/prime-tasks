#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import subprocess
import random
import string
import pytest

SCRIPT_PATH = "/home/user/process_stream.sh"
ORACLE_PATH = "/app/legacy_etl"


def test_script_exists_and_executable():
    """Check that the script exists and is executable."""
    assert os.path.exists(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is not a file."
    st = os.stat(SCRIPT_PATH)
    assert bool(st.st_mode & stat.S_IXUSR), f"Script {SCRIPT_PATH} is not executable."

    # The requested replacement must not simply be the compiled legacy artifact.
    if os.path.exists(ORACLE_PATH):
        with open(SCRIPT_PATH, "rb") as submitted, open(ORACLE_PATH, "rb") as oracle:
            assert submitted.read() != oracle.read(), "Replacement is byte-identical to the legacy binary."


def test_cron_job_exists():
    """Verify the cron job is scheduled correctly."""
    try:
        result = subprocess.run(
            ["crontab", "-l", "-u", "user"],
            capture_output=True,
            text=True,
            check=True
        )
        crontab_content = result.stdout
    except subprocess.CalledProcessError:
        pytest.fail("Failed to read crontab for user 'user'.")

    expected_cron = "30 2 * * * /home/user/process_stream.sh < /data/daily.csv > /data/processed.csv"
    found = any(line.strip() == expected_cron for line in crontab_content.splitlines())
    assert found, f"Expected cron job not found in crontab. Expected: '{expected_cron}'"


def generate_random_csv_stream():
    """Generate valid input and independently derive the specified output."""
    num_lines = random.randint(100, 500)
    lines = []
    expected = []
    valid_bytes = [b for b in range(0x20, 0x100) if b not in (0x2C, 0x0A)]

    for _ in range(num_lines):
        id_val = random.randint(1, 100)
        category = "".join(random.choices(string.ascii_uppercase, k=4))
        value = "" if random.random() < 0.2 else f"{random.uniform(0.0, 1000.0):.2f}"
        note_length = random.randint(5, 50)
        notes_bytes = bytes(random.choices(valid_bytes, k=note_length))

        lines.append(
            f"{id_val},{category},{value},".encode("ascii") + notes_bytes + b"\n"
        )

        if id_val % 10 == 0:
            output_value = value if value else "0.0"
            expected.append(
                f"{id_val},{category},{output_value},".encode("ascii")
                + notes_bytes.decode("iso-8859-1").encode("utf-8")
                + b"\n"
            )

    return b"".join(lines), b"".join(expected)


def run_agent(input_data):
    proc = subprocess.run(
        ["/bin/bash", SCRIPT_PATH],
        input=input_data,
        capture_output=True
    )
    assert proc.returncode == 0, (
        f"Agent script failed with exit code {proc.returncode}:\n"
        f"{proc.stderr.decode('utf-8', errors='replace')}"
    )
    return proc.stdout


def test_missing_value_imputation_and_encoding():
    """Directly exercise the required empty-value behavior and Latin-1 conversion."""
    input_data = (
        b"10,TEST,,caf\xe9\n"
        b"11,DROP,,ignored\n"
        b"20,DATA,12.50,\xffnote\n"
        b"30,ZERO,,plain\n"
    )
    expected = (
        "10,TEST,0.0,café\n"
        "20,DATA,12.50,ÿnote\n"
        "30,ZERO,0.0,plain\n"
    ).encode("utf-8")
    assert run_agent(input_data) == expected


def test_fuzz_equivalence_to_specification():
    """Fuzz the replacement against answers derived from the stated rules."""
    random.seed(42)
    for i in range(200):
        input_data, expected = generate_random_csv_stream()
        actual = run_agent(input_data)
        if actual != expected:
            pytest.fail(
                f"Output mismatch on random input {i}.\n"
                f"Input data length: {len(input_data)} bytes\n"
                f"Expected output length: {len(expected)} bytes\n"
                f"Agent output length: {len(actual)} bytes\n"
                f"First 200 bytes of expected output: {expected[:200]!r}\n"
                f"First 200 bytes of agent output: {actual[:200]!r}"
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
