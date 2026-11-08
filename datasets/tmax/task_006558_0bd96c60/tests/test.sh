#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import stat
import shutil
import subprocess
import tempfile
import uuid
import random

SCRIPT_PATH = "/home/user/process_drift.sh"
OUTPUT_PATH = "/home/user/top_drifts.txt"
REPORTS_PATH = "/home/user/reports"


def run_script():
    if os.path.exists(OUTPUT_PATH):
        os.remove(OUTPUT_PATH)
    result = subprocess.run([SCRIPT_PATH], capture_output=True, text=True, timeout=30)
    assert result.returncode == 0, f"Script failed to execute. stderr: {result.stderr}"
    assert os.path.isfile(OUTPUT_PATH), f"Output file {OUTPUT_PATH} was not created by the script."
    with open(OUTPUT_PATH, "r") as f:
        return [line.strip() for line in f if line.strip()]


def test_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    st = os.stat(SCRIPT_PATH)
    assert bool(st.st_mode & stat.S_IXUSR), f"Script {SCRIPT_PATH} is not executable."


def test_implementation_constraints():
    with open(SCRIPT_PATH, "r", errors="replace") as f:
        source = f.read()

    first_line = source.splitlines()[0] if source.splitlines() else ""
    assert first_line == "#!/bin/bash" or re.fullmatch(r"#!\s*/usr/bin/env\s+bash", first_line), \
        "process_drift.sh must be a Bash script."

    # Ignore full-line comments while checking that the implementation actually
    # contains a GNU parallel-processing invocation.
    active_source = "\n".join(
        line for line in source.splitlines() if not re.match(r"^\s*#", line)
    )
    uses_parallel_xargs = re.search(
        r"\bxargs\b[\s\S]{0,500}?(?:\s-P(?:\s|[0-9=]|$)|--max-procs(?:\s|=))",
        active_source,
    )
    uses_gnu_parallel = re.search(r"(?:^|[;&|]\s*)parallel(?:\s|$)", active_source, re.MULTILINE)
    assert uses_parallel_xargs or uses_gnu_parallel, \
        "The script must process files in parallel using xargs -P/--max-procs or GNU parallel."

    forbidden = re.search(
        r"(?m)(?:^|[;&|()]\s*|\benv\s+)(?:/usr/bin/|/bin/)?(?:python(?:3(?:\.\d+)?)?|perl)(?:\s|$)",
        active_source,
    )
    assert not forbidden, "Python and Perl may not be used by process_drift.sh."


def test_script_execution_and_output():
    lines = run_script()

    expected_lines = [
        "PaymentSvc:16.5",
        "InventorySvc:13.5",
        "CacheSvc:12.5"
    ]

    assert len(lines) == 3, f"Expected exactly 3 lines in {OUTPUT_PATH}, got {len(lines)}"

    for i, expected in enumerate(expected_lines):
        assert lines[i] == expected, f"Line {i+1} mismatch. Expected '{expected}', got '{lines[i]}'"


def test_dynamic_csv_processing_validation_and_aggregation():
    # Replace the fixtures with unpredictable service names and totals so fixed
    # output cannot pass. Expected answers are derived from the generated data.
    parent = os.path.dirname(REPORTS_PATH)
    backup_root = tempfile.mkdtemp(prefix="reports_backup_", dir=parent)
    backup = os.path.join(backup_root, "reports")
    shutil.copytree(REPORTS_PATH, backup)

    try:
        shutil.rmtree(REPORTS_PATH)
        os.makedirs(REPORTS_PATH)

        rng = random.SystemRandom()
        services = [f"Svc_{uuid.uuid4().hex[:10]}" for _ in range(5)]
        # Large gaps guarantee a stable ranking while random offsets make the
        # exact totals unpredictable.
        totals_tenths = [150 + rng.randrange(0, 6), 120 + rng.randrange(0, 6),
                         90 + rng.randrange(0, 6), 60 + rng.randrange(0, 6),
                         30 + rng.randrange(0, 6)]
        pieces = []
        for total in totals_tenths:
            first = rng.randrange(10, 31)
            second = rng.randrange(10, 31)
            pieces.append((first, second, total - first - second))

        for file_index, filename in enumerate(("north.csv", "south.csv", "central.csv")):
            path = os.path.join(REPORTS_PATH, filename)
            with open(path, "w") as f:
                f.write("service_name, day1, day2, day3, day4, day5\n")
                for service, service_pieces in zip(services, pieces):
                    valid = service_pieces[file_index] / 10.0
                    # Whitespace must be trimmed, while negatives, text, empty
                    # fields, and zero must not alter the mathematical sum.
                    f.write(f"  {service}  ,  {valid:.1f}  , -4.2, invalid, , 0\n")

        lines = run_script()
        expected = [
            f"{service}:{total / 10.0:.1f}"
            for service, total in zip(services[:3], totals_tenths[:3])
        ]
        assert lines == expected, f"Expected dynamically derived output {expected}, got {lines}"
    finally:
        if os.path.exists(REPORTS_PATH):
            shutil.rmtree(REPORTS_PATH)
        shutil.copytree(backup, REPORTS_PATH)
        shutil.rmtree(backup_root)


def test_cron_job_scheduled():
    result = subprocess.run(['crontab', '-l', '-u', 'user'], capture_output=True, text=True)
    stdout = result.stdout.strip()
    cron_lines = [line.strip() for line in stdout.split('\n') if line.strip() and not line.strip().startswith('#')]

    expected_cron_command = "/home/user/process_drift.sh"
    found = False
    for line in cron_lines:
        parts = line.split()
        if len(parts) >= 6:
            schedule = " ".join(parts[:5])
            command = " ".join(parts[5:])
            if schedule == "0 2 * * *" and expected_cron_command in command:
                found = True
                break

    assert found, "Cron job '0 2 * * * /home/user/process_drift.sh' not found for user 'user'."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
