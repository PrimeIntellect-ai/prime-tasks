#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import json
import os
import secrets
import stat
import subprocess

import pytest

APP_DIR = "/home/user/app"
REPORT_PATH = "/home/user/app/uptime_report.json"
WAL_PATH = "/home/user/data/tracker.wal"
RUN_PATH = "/home/user/app/run.sh"
MAIN_PATH = "/home/user/app/main.go"
CONFIG_PATH = "/home/user/data/config.json"


def derive_expected(wal_bytes):
    expected_total = 0
    expected_up = 0
    for raw_line in wal_bytes.decode("utf-8").splitlines():
        line = raw_line.strip()
        if not line:
            continue
        try:
            entry = json.loads(line)
            expected_total += 1
            if entry.get("status") == "up":
                expected_up += 1
        except json.JSONDecodeError:
            pass
    return expected_total, expected_up


def read_report_with_original_assertions(expected_total, expected_up):
    assert os.path.isfile(REPORT_PATH), f"Report file {REPORT_PATH} was not generated."
    with open(REPORT_PATH, "r") as f:
        try:
            report_data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"Report file {REPORT_PATH} does not contain valid JSON.")

    assert "total_processed" in report_data, "Report is missing 'total_processed' key."
    assert "up_count" in report_data, "Report is missing 'up_count' key."

    actual_total = report_data["total_processed"]
    actual_up = report_data["up_count"]
    assert actual_total == expected_total, f"Expected total_processed to be {expected_total}, but got {actual_total}."
    assert actual_up == expected_up, f"Expected up_count to be {expected_up}, but got {actual_up}."
    return report_data


def make_challenge():
    count = 4 + secrets.randbelow(5)
    statuses = ["up", "down"] + [secrets.choice(["up", "down"]) for _ in range(count - 2)]
    lines = []
    for i, status in enumerate(statuses):
        # Repeated '~' characters ensure standard Base64 produces '+' or '/'.
        url = f"https://example.test/{'~' * 30}/{secrets.token_hex(8)}/{i}"
        encoded = base64.b64encode(url.encode("utf-8")).decode("ascii")
        assert "+" in encoded or "/" in encoded
        lines.append(json.dumps({
            "timestamp": 1700000000 + i,
            "url": encoded,
            "status": status,
        }, separators=(",", ":")))

    # Match the crash scenario: a truncated JSON record follows all valid records.
    lines.append('{"timestamp":1700999999,"ur')
    wal = ("\n".join(lines) + "\n").encode("utf-8")
    return wal, count, statuses.count("up")


def run_and_check(command, env):
    challenge, expected_total, expected_up = make_challenge()
    with open(WAL_PATH, "wb") as f:
        f.write(challenge)
    os.chmod(WAL_PATH, 0o644)

    if os.path.exists(REPORT_PATH):
        os.unlink(REPORT_PATH)

    result = subprocess.run(
        command,
        cwd=APP_DIR,
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=90,
    )
    assert result.returncode == 0, f"Command {' '.join(command)} failed:\n{result.stdout}"
    assert os.path.isfile(REPORT_PATH), "The application did not generate uptime_report.json."

    with open(WAL_PATH, "rb") as f:
        assert f.read() == challenge, "The application must process the WAL without replacing or modifying it."

    report = read_report_with_original_assertions(expected_total, expected_up)
    assert set(report) == {"total_processed", "up_count"}, "Report contains fields not present in the Report struct."
    assert type(report["total_processed"]) is int
    assert type(report["up_count"]) is int


def test_uptime_report_exists_and_correct_and_application_runs():
    assert os.path.isfile(WAL_PATH), f"WAL file {WAL_PATH} is missing."
    assert os.path.isfile(REPORT_PATH), f"Report file {REPORT_PATH} was not generated."

    with open(WAL_PATH, "rb") as f:
        original_wal = f.read()
    original_total, original_up = derive_expected(original_wal)

    # Preserve all assertions made by the original verifier.
    read_report_with_original_assertions(original_total, original_up)

    run_stat = os.lstat(RUN_PATH)
    main_stat = os.lstat(MAIN_PATH)
    assert stat.S_ISREG(run_stat.st_mode), "run.sh must be a regular file."
    assert stat.S_ISREG(main_stat.st_mode), "main.go must be a regular file."
    assert os.access(RUN_PATH, os.X_OK), "run.sh is not executable."
    assert os.path.isfile(CONFIG_PATH), f"Config file {CONFIG_PATH} is missing."

    clean_env = {
        "PATH": "/usr/local/go/bin:/usr/bin:/bin",
        "HOME": "/home/user",
        "LANG": "C",
    }

    try:
        # Execute the demanded startup artifact with no inherited config variable.
        run_and_check([RUN_PATH], clean_env)

        # Independently exercise the repaired Go source so run.sh cannot substitute
        # a fabricated report for the application itself.
        main_env = dict(clean_env)
        main_env["UPTIME_CONFIG_PATH"] = CONFIG_PATH
        run_and_check(["go", "run", MAIN_PATH], main_env)
    finally:
        with open(WAL_PATH, "wb") as f:
            f.write(original_wal)
        os.chmod(WAL_PATH, 0o644)

    # Leave the service's report corresponding to the restored WAL.
    if os.path.exists(REPORT_PATH):
        os.unlink(REPORT_PATH)
    result = subprocess.run(
        [RUN_PATH], cwd=APP_DIR, env=clean_env,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        text=True, timeout=90,
    )
    assert result.returncode == 0, f"run.sh failed on the restored WAL:\n{result.stdout}"
    read_report_with_original_assertions(original_total, original_up)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
