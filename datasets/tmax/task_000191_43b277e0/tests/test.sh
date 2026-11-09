#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import shutil
import secrets
import subprocess
import tempfile
from collections import Counter

SCRIPT_PATH = "/home/user/scripts/process_locales.sh"
PROP_PATH = "/home/user/locales/processed/master.prop"
INCOMING_PATH = "/home/user/locales/incoming"
DUMP_PATH = "/home/user/crontab_dump.txt"
CRON_PATTERN = re.compile(r"^30\s+2\s+\*\s+\*\s+\*\s+(?:.*)?/home/user/scripts/process_locales\.sh$")


def test_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable."


def test_master_prop_content():
    assert os.path.isfile(PROP_PATH), f"Output file {PROP_PATH} does not exist."

    with open(PROP_PATH, "r", encoding="utf-8") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = {
        'farewell_fr="Au revoir"',
        'error_404_fr="Non trouvé"',
        'midnight_fr="Minuit"',
        'greeting_es="Hola"',
        'button_save_es="Guardar"',
        'new_year_es="Feliz Año"'
    }

    unexpected_lines = {
        'greeting_fr="Bonjour"',
        'old_key_es="Viejo"'
    }

    actual_lines_set = set(lines)

    for expected in expected_lines:
        assert expected in actual_lines_set, f"Expected line '{expected}' missing from {PROP_PATH}."

    for unexpected in unexpected_lines:
        assert unexpected not in actual_lines_set, f"Unexpected line '{unexpected}' found in {PROP_PATH}."

    assert len(lines) == 6, f"Expected exactly 6 valid entries in {PROP_PATH}, but found {len(lines)}."


def test_script_processes_changed_inputs_when_executed():
    token = secrets.token_hex(8)
    records = [
        ("2023/10/01-00:00", f"threshold_{token}", f"Threshold {token}"),
        ("2023/12/19-17:42", f"recent_{token}", f"Recent value {token}"),
        ("2025/07/04-03:21", f"future_{token}", f"Future value {token}"),
    ]
    expected = [f'{key}="{value}"' for _, key, value in records]

    backup_root = tempfile.mkdtemp(prefix="locale-verifier-")
    backup_incoming = os.path.join(backup_root, "incoming")
    backup_prop = os.path.join(backup_root, "master.prop")
    had_prop = os.path.exists(PROP_PATH)

    try:
        shutil.move(INCOMING_PATH, backup_incoming)
        os.mkdir(INCOMING_PATH, 0o755)
        shutil.chown(INCOMING_PATH, user="user", group="user")

        if had_prop:
            shutil.move(PROP_PATH, backup_prop)

        with open(os.path.join(INCOMING_PATH, f"batch_a_{token}.txt"), "w", encoding="utf-8") as f:
            f.write(f'[{records[0][0]}] {records[0][1]} := "{records[0][2]}"\n')
            f.write(f'[2023/09/30-23:59] old_{token} := "Must be filtered"\n')
            f.write(f'not a translation line {token}\n')
            f.write(f'[2024/01/01-00:00] malformed_{token} = "Wrong separator"\n')

        with open(os.path.join(INCOMING_PATH, f"batch_b_{token}.txt"), "w", encoding="utf-8") as f:
            for timestamp, key, value in records[1:]:
                f.write(f'[{timestamp}] {key} := "{value}"\n')

        with open(os.path.join(INCOMING_PATH, f"ignored_{token}.dat"), "w", encoding="utf-8") as f:
            f.write(f'[2026/01/01-00:00] wrong_extension_{token} := "Ignore me"\n')

        for name in os.listdir(INCOMING_PATH):
            shutil.chown(os.path.join(INCOMING_PATH, name), user="user", group="user")

        with open(PROP_PATH, "w", encoding="utf-8") as f:
            f.write(f'stale_{token}="This must be cleared"\n')
        shutil.chown(PROP_PATH, user="user", group="user")

        result = subprocess.run(
            ["/usr/sbin/runuser", "-u", "user", "--", SCRIPT_PATH],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
        )
        assert result.returncode == 0, (
            f"Executing {SCRIPT_PATH} failed with status {result.returncode}. "
            f"stdout={result.stdout!r}, stderr={result.stderr!r}"
        )
        assert os.path.isfile(PROP_PATH), "The script did not create master.prop."

        with open(PROP_PATH, "r", encoding="utf-8") as f:
            actual = [line.strip() for line in f if line.strip()]

        assert Counter(actual) == Counter(expected), (
            "The script did not derive the exact filtered properties from the changed input files. "
            f"Expected {expected!r}, got {actual!r}."
        )
    finally:
        if os.path.exists(INCOMING_PATH):
            shutil.rmtree(INCOMING_PATH)
        shutil.move(backup_incoming, INCOMING_PATH)

        if os.path.exists(PROP_PATH):
            os.remove(PROP_PATH)
        if had_prop:
            shutil.move(backup_prop, PROP_PATH)
        shutil.rmtree(backup_root, ignore_errors=True)


def test_crontab_dump():
    assert os.path.isfile(DUMP_PATH), f"Crontab dump file {DUMP_PATH} does not exist."

    with open(DUMP_PATH, "r", encoding="utf-8") as f:
        content = f.read()

    match = False
    for line in content.splitlines():
        if CRON_PATTERN.match(line.strip()):
            match = True
            break

    assert match, "Crontab dump does not contain the correct cron job scheduling (30 2 * * * /home/user/scripts/process_locales.sh)."

    result = subprocess.run(
        ["/usr/bin/crontab", "-u", "user", "-l"],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )
    assert result.returncode == 0, f"User's active crontab could not be read: {result.stderr!r}"

    active_lines = result.stdout.splitlines()
    assert any(CRON_PATTERN.match(line.strip()) for line in active_lines), (
        "The user's active crontab does not schedule process_locales.sh daily at 2:30 AM."
    )
    assert content.splitlines() == active_lines, (
        "crontab_dump.txt is not a dump of the user's active crontab."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
