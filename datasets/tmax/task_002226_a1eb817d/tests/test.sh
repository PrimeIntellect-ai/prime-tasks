#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
from datetime import datetime, timezone, timedelta
import pytest

SCRIPT_PATH = "/home/user/parser.sh"
EU_PATH = "/home/user/incoming/syslog_eu.log"
ASIA_PATH = "/home/user/incoming/app_asia.log"
OUTPUT_PATH = "/home/user/extracted_errors.log"


def test_parser_script_exists_and_executable():
    script_path = "/home/user/parser.sh"
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."
    with open(script_path, "rb") as f:
        first_line = f.readline()
    assert first_line.startswith(b"#!") and b"bash" in first_line, "parser.sh must be a Bash script with a Bash shebang."


def test_extracted_errors_log():
    log_path = "/home/user/extracted_errors.log"
    assert os.path.isfile(log_path), f"Log file {log_path} does not exist. Did you run your script?"

    with open(log_path, "r", encoding="utf-8") as f:
        content = f.read().strip().splitlines()

    expected_lines = [
        "1697114100|Connexion échouée à la base de données",
        "1697114700|致命的なエラーが発生しました",
        "1697116222|Fichier introuvable",
        "1697116530|タイムアウト例外"
    ]

    assert len(content) == len(expected_lines), f"Expected {len(expected_lines)} lines in {log_path}, but found {len(content)}."

    for i, (actual, expected) in enumerate(zip(content, expected_lines)):
        assert actual == expected, f"Line {i+1} mismatch. Expected: '{expected}', Got: '{actual}'"


def test_cron_job_installed():
    try:
        result = subprocess.run(
            ["crontab", "-l", "-u", "user"],
            capture_output=True,
            text=True,
            check=True
        )
        crontab_output = result.stdout
    except subprocess.CalledProcessError:
        pytest.fail("Failed to retrieve crontab for user 'user'.")

    cron_lines = [line.strip() for line in crontab_output.splitlines() if line.strip() and not line.strip().startswith("#")]

    found = False
    for line in cron_lines:
        parts = line.split()
        if len(parts) >= 6:
            schedule = " ".join(parts[:5])
            command = " ".join(parts[5:])
            if schedule == "*/5 * * * *" and "parser.sh" in command:
                found = True
                break

    assert found, "Could not find a cron job for 'user' running parser.sh every 5 minutes (*/5 * * * *)."


def test_parser_executes_on_changed_encoded_inputs_and_appends_sorted_output():
    eu_records = [
        ("03/Feb/2024:23:59:58 -0330", "ERROR", "Échec réseau à Montréal"),
        ("15/Jan/2023:00:00:00 +1245", "ERROR", "Entrée très ancienne"),
    ]
    asia_records = [
        ("2024-07-01 00:00:01", "JST", "FAIL", "障害が二件発生"),
        ("2024-06-30 15:00:02", "UTC", "FAIL", "再試行に失敗"),
    ]

    eu_text = "\n".join([
        "[03/Feb/2024:23:59:57 -0330] INFO: message contenant ERROR: mais non erreur",
        *[f"[{stamp}] {level}: {message}" for stamp, level, message in eu_records],
        "[04/Feb/2024:00:00:00 -0330] WARNING: rien à extraire",
    ]) + "\n"
    asia_text = "\n".join([
        "2024-06-30 14:59:59 UTC - OK - texte contenant - FAIL - mais niveau OK",
        *[f"{stamp} {tz} - {level} - {message}" for stamp, tz, level, message in asia_records],
        "2024-07-01 00:01:00 JST - OK - 正常終了",
    ]) + "\n"

    with open(EU_PATH, "wb") as f:
        f.write(eu_text.encode("iso-8859-1"))
    with open(ASIA_PATH, "wb") as f:
        f.write(asia_text.encode("utf-16le"))

    sentinel = "1|Existing entry"
    with open(OUTPUT_PATH, "w", encoding="utf-8") as f:
        f.write(sentinel + "\n")
    os.chmod(OUTPUT_PATH, 0o666)

    result = subprocess.run(
        ["runuser", "-u", "user", "--", SCRIPT_PATH],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"parser.sh failed when executed as user (exit {result.returncode}). "
        f"stdout: {result.stdout!r}; stderr: {result.stderr!r}"
    )

    expected = [(1, "Existing entry")]
    for stamp, _level, message in eu_records:
        dt = datetime.strptime(stamp, "%d/%b/%Y:%H:%M:%S %z")
        expected.append((int(dt.timestamp()), message))

    asia_offsets = {"JST": timedelta(hours=9), "UTC": timedelta(0)}
    for stamp, tz_name, _level, message in asia_records:
        dt = datetime.strptime(stamp, "%Y-%m-%d %H:%M:%S").replace(
            tzinfo=timezone(asia_offsets[tz_name])
        )
        expected.append((int(dt.timestamp()), message))

    expected_lines = [f"{epoch}|{message}" for epoch, message in sorted(expected)]
    with open(OUTPUT_PATH, "r", encoding="utf-8") as f:
        actual_lines = f.read().splitlines()

    assert actual_lines == expected_lines, (
        "parser.sh did not correctly decode, filter, normalize, append, and numerically sort changed inputs.\n"
        f"Expected: {expected_lines!r}\nGot: {actual_lines!r}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
