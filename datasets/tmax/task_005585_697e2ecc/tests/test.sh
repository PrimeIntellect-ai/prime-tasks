#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import pwd
import re
import sqlite3
import subprocess
import uuid
from pathlib import Path


def test_script_exists():
    script_path = "/home/user/etl_pipeline.py"
    assert os.path.isfile(script_path), f"ETL script {script_path} does not exist."


def test_files_moved_to_processed():
    processed_dir = "/home/user/processed"
    drops_dir = "/home/user/drops"

    expected_files = ["es.json", "fr.json", "de.json"]
    for file in expected_files:
        assert os.path.isfile(os.path.join(processed_dir, file)), f"File {file} was not moved to {processed_dir}."
        assert not os.path.isfile(os.path.join(drops_dir, file)), f"File {file} still exists in {drops_dir}."


def test_database_contents():
    db_path = "/home/user/loc_db.sqlite"
    assert os.path.isfile(db_path), f"Database {db_path} does not exist."

    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    cursor.execute("SELECT lang, key FROM translations ORDER BY lang, key;")
    rows = cursor.fetchall()
    conn.close()

    expected_rows = [
        ("de", "error_not_found"),
        ("de", "logout_btn"),
        ("de", "welcome_msg"),
        ("es", "logout_btn"),
        ("es", "welcome_msg"),
        ("fr", "error_not_found"),
        ("fr", "logout_btn"),
    ]

    assert rows == expected_rows, f"Database entries do not match expected valid translations. Found: {rows}"


def test_invalid_translations_log():
    log_path = "/home/user/invalid_translations.log"
    assert os.path.isfile(log_path), f"Log file {log_path} does not exist."

    with open(log_path, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    expected_lines = {
        "es.json:error_not_found:INVALID_PLACEHOLDERS",
        "fr.json:welcome_msg:INVALID_PLACEHOLDERS",
    }
    assert set(lines) == expected_lines, f"Log file contents do not match expected invalid translations. Found: {lines}"


def _cron_lines(text):
    schedule = re.compile(
        r"^\s*(?:\*/5|0,5,10,15,20,25,30,35,40,45,50,55|0-59/5)"
        r"\s+\*\s+\*\s+\*\s+\*\s+(.+?)\s*$"
    )
    result = []
    for raw in text.splitlines():
        if raw.lstrip().startswith("#"):
            continue
        match = schedule.match(raw)
        if match and "/home/user/etl_pipeline.py" in match.group(1):
            result.append((" ".join(raw.split()), match.group(1).strip()))
    return result


def _command_runs_pipeline(command):
    # /etc/crontab and /etc/cron.d entries have a username before the command.
    parts = command.split()
    usernames = {entry.pw_name for entry in pwd.getpwall()}
    if parts and parts[0] in usernames:
        parts = parts[1:]
    command = " ".join(parts)

    python_call = re.search(
        r"(?:^|[;&|]\s*|\bexec\s+)(?:/usr/bin/|/bin/)?python3?\s+"
        r"/home/user/etl_pipeline\.py(?:\s|$)",
        command,
    )
    direct_call = re.search(
        r"(?:^|[;&|]\s*|\bexec\s+)/home/user/etl_pipeline\.py(?:\s|$)",
        command,
    )
    if python_call:
        return True
    if direct_call:
        return os.access("/home/user/etl_pipeline.py", os.X_OK)
    return False


def test_cron_backup_and_installed_job():
    cron_path = "/home/user/cron_backup.txt"
    assert os.path.isfile(cron_path), f"Cron backup file {cron_path} does not exist."

    with open(cron_path, "r") as f:
        content = f.read().strip()

    assert "/home/user/etl_pipeline.py" in content or "etl_pipeline.py" in content, "Cron backup does not contain the script name."

    match_star_5 = re.search(r"\*/5\s+\*\s+\*\s+\*\s+\*", content)
    match_list_5 = re.search(r"(0,5,10,15,20,25,30,35,40,45,50,55|0-59/5)\s+\*\s+\*\s+\*\s+\*", content)
    assert match_star_5 or match_list_5, f"Cron backup does not specify a 5-minute interval. Found: {content}"

    backup_jobs = _cron_lines(content)
    assert backup_jobs, "Cron backup does not contain a valid five-minute job using the required absolute script path."
    assert any(_command_runs_pipeline(command) for _, command in backup_jobs), "Cron backup mentions the script but does not execute it."

    installed_sources = []
    for username in {entry.pw_name for entry in pwd.getpwall()}:
        proc = subprocess.run(
            ["crontab", "-u", username, "-l"],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
        )
        if proc.returncode == 0:
            installed_sources.append(proc.stdout)

    for path in [Path("/etc/crontab"), *sorted(Path("/etc/cron.d").glob("*"))]:
        try:
            if path.is_file():
                installed_sources.append(path.read_text(errors="replace"))
        except OSError:
            pass

    installed_jobs = []
    for source in installed_sources:
        installed_jobs.extend(_cron_lines(source))

    runnable_installed = [(line, cmd) for line, cmd in installed_jobs if _command_runs_pipeline(cmd)]
    assert runnable_installed, "No installed cron job runs /home/user/etl_pipeline.py every five minutes."

    backup_specs = {line for line, cmd in backup_jobs if _command_runs_pipeline(cmd)}
    installed_specs = {line for line, cmd in runnable_installed}
    assert backup_specs & installed_specs, "cron_backup.txt does not contain the cron specification that was actually installed."


def test_script_processes_fresh_unseen_drop():
    token = uuid.uuid4().hex
    lang = "zz" + token[:10]
    valid_key = "valid_" + token
    plain_key = "plain_" + token
    missing_key = "missing_" + token
    extra_key = "extra_" + token
    unknown_key = "unknown_" + token

    base_path = Path("/home/user/base_en.json")
    drop_path = Path("/home/user/drops") / f"{lang}.json"
    processed_path = Path("/home/user/processed") / f"{lang}.json"
    log_path = Path("/home/user/invalid_translations.log")
    original_base_text = base_path.read_text()
    base = json.loads(original_base_text)

    base.update({
        valid_key: "Account {User9} has {count2} items.",
        plain_key: "No placeholders here.",
        missing_key: "Account {User9} has {count2} items.",
        extra_key: "No placeholders here either.",
    })

    translations = {
        valid_key: "Le compte {User9} contient {count2} éléments.",
        plain_key: "Aucun paramètre.",
        missing_key: "Le compte {User9} contient des éléments.",
        extra_key: "Texte avec {surplus7}.",
        unknown_key: "Valeur inconnue.",
    }

    before_log = [line.strip() for line in log_path.read_text().splitlines() if line.strip()]

    conn = sqlite3.connect("/home/user/loc_db.sqlite")
    try:
        assert conn.execute("SELECT COUNT(*) FROM translations WHERE lang = ?", (lang,)).fetchone()[0] == 0
    finally:
        conn.close()

    try:
        base_path.write_text(json.dumps(base, ensure_ascii=False, indent=2))
        drop_path.write_text(json.dumps(translations, ensure_ascii=False, indent=2))

        proc = subprocess.run(
            ["python3", "/home/user/etl_pipeline.py"],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
        )
        assert proc.returncode == 0, f"ETL script failed on a fresh drop:\nstdout={proc.stdout}\nstderr={proc.stderr}"

        assert not drop_path.exists(), "Fresh drop was not removed from the drops directory."
        assert processed_path.is_file(), "Fresh drop was not moved to the processed directory."

        conn = sqlite3.connect("/home/user/loc_db.sqlite")
        try:
            rows = conn.execute(
                "SELECT key, text_val FROM translations WHERE lang = ? ORDER BY key",
                (lang,),
            ).fetchall()
        finally:
            conn.close()

        expected_rows = sorted([
            (valid_key, translations[valid_key]),
            (plain_key, translations[plain_key]),
        ])
        assert rows == expected_rows, f"Fresh drop was not validated and loaded correctly. Found: {rows}"

        after_log = [line.strip() for line in log_path.read_text().splitlines() if line.strip()]
        assert after_log[:len(before_log)] == before_log, "The ETL script did not append to the existing invalid-translations log."
        new_lines = after_log[len(before_log):]
        expected_invalid = {
            f"{lang}.json:{missing_key}:INVALID_PLACEHOLDERS",
            f"{lang}.json:{extra_key}:INVALID_PLACEHOLDERS",
            f"{lang}.json:{unknown_key}:INVALID_PLACEHOLDERS",
        }
        assert len(new_lines) == 3 and set(new_lines) == expected_invalid, f"Incorrect validation log entries for fresh drop: {new_lines}"
    finally:
        base_path.write_text(original_base_text)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
