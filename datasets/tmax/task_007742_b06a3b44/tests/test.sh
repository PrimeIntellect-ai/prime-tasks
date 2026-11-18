#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import re
import shutil
import subprocess
import tempfile
import time
import uuid
import pytest

SCRIPT_PATH = "/home/user/update_translations.py"
TSV_PATH = "/home/user/raw_data/translations.tsv"
LOCALES_PATH = "/home/user/locales"


def test_script_exists():
    assert os.path.isfile(SCRIPT_PATH), "The script /home/user/update_translations.py does not exist."


def test_locales_directory_exists():
    assert os.path.isdir(LOCALES_PATH), "The directory /home/user/locales does not exist."


def test_json_files_exist_and_correct():
    expected_data = {
        "es": {
            "apple": "Manzana",
            "farewell": "Adiós",
            "greeting": "Hola",
            "zebra": "Cebra"
        },
        "zh": {
            "apple": "苹果",
            "farewell": "再见",
            "greeting": "你好",
            "zebra": "斑马"
        },
        "ar": {
            "apple": "تفاحة",
            "farewell": "وداعا",
            "greeting": "مرحبًا",
            "zebra": "حمار وحشي"
        }
    }

    for lang, expected_dict in expected_data.items():
        file_path = f"/home/user/locales/{lang}.json"
        assert os.path.isfile(file_path), f"The file {file_path} does not exist."

        with open(file_path, "r", encoding="utf-8") as f:
            try:
                data = json.load(f)
            except json.JSONDecodeError:
                pytest.fail(f"The file {file_path} does not contain valid JSON.")

        assert data == expected_dict, f"The content of {file_path} is incorrect."

        # Check if keys are sorted alphabetically
        keys = list(data.keys())
        assert keys == sorted(keys), f"The keys in {file_path} are not sorted alphabetically."


def _scheduled_command():
    try:
        result = subprocess.run(["crontab", "-l"], capture_output=True, text=True, check=True)
    except subprocess.CalledProcessError:
        pytest.fail("Failed to read crontab. Ensure the crontab is set up for the current user.")

    pattern = re.compile(r"^15\s+3\s+\*\s+\*\s+\*.*?/home/user/update_translations\.py(\s|$)", re.MULTILINE)
    match = pattern.search(result.stdout)
    assert match, "The crontab does not contain the correct schedule (15 3 * * *) or does not point to the absolute path of the script."
    line = match.group(0).strip()
    fields = line.split(None, 5)
    assert len(fields) == 6 and fields[5], "The cron entry does not contain a command."
    return fields[5]


def test_script_processes_changed_input_when_executed():
    token = uuid.uuid4().hex[:10]
    expected = {
        f"qa_{token}": {
            "alpha": f"first-{token}",
            "middle": "مرحبا بالعالم",
            "zulu": "最後の翻訳"
        },
        f"qb_{token}": {
            "apple": "pomme",
            "greeting": f"bonjour-{token}",
            "omega": "Καληνύχτα"
        },
        f"qc_{token}": {
            "cat": "猫",
            "dog": "كلب",
            "welcome": "स्वागत"
        }
    }

    rows = []
    for lang, entries in expected.items():
        for key in reversed(list(entries.keys())):
            rows.append(f"{key}\t{lang}\t{entries[key]}\n")

    with open(TSV_PATH, "rb") as f:
        original_tsv = f.read()

    backup_root = tempfile.mkdtemp(prefix="locales_backup_")
    backup_locales = os.path.join(backup_root, "locales")
    if os.path.isdir(LOCALES_PATH):
        shutil.copytree(LOCALES_PATH, backup_locales)

    try:
        if os.path.exists(LOCALES_PATH):
            shutil.rmtree(LOCALES_PATH)
        with open(TSV_PATH, "w", encoding="utf-8", newline="") as f:
            f.writelines(rows)

        command = _scheduled_command()
        try:
            result = subprocess.run(
                command,
                shell=True,
                executable="/bin/bash",
                cwd="/home/user",
                capture_output=True,
                text=True,
                timeout=20
            )
        except subprocess.TimeoutExpired:
            pytest.fail("The scheduled translation command did not finish within 20 seconds.")

        assert result.returncode == 0, (
            "The scheduled translation command failed. "
            f"stdout: {result.stdout!r}; stderr: {result.stderr!r}"
        )

        # Allow a briefly backgrounded command to finish writing, while still
        # requiring the cron command to cause the requested output.
        deadline = time.time() + 3
        while time.time() < deadline:
            if all(os.path.isfile(os.path.join(LOCALES_PATH, f"{lang}.json")) for lang in expected):
                break
            time.sleep(0.05)

        assert os.path.isdir(LOCALES_PATH), "The script did not create /home/user/locales."
        for lang, expected_dict in expected.items():
            file_path = os.path.join(LOCALES_PATH, f"{lang}.json")
            assert os.path.isfile(file_path), f"The executed script did not create {file_path}."
            try:
                with open(file_path, "r", encoding="utf-8") as f:
                    data = json.load(f)
            except (UnicodeDecodeError, json.JSONDecodeError) as exc:
                pytest.fail(f"The executed script produced invalid UTF-8 JSON in {file_path}: {exc}")

            assert isinstance(data, dict), f"{file_path} must contain a JSON object."
            assert data == expected_dict, f"The executed script incorrectly processed changed input for {lang}."
            keys = list(data.keys())
            assert keys == sorted(keys), f"The keys in {file_path} are not sorted alphabetically."
            assert all(isinstance(k, str) and isinstance(v, str) for k, v in data.items()), (
                f"{file_path} must be a flat string key-value dictionary."
            )
    finally:
        with open(TSV_PATH, "wb") as f:
            f.write(original_tsv)
        if os.path.exists(LOCALES_PATH):
            shutil.rmtree(LOCALES_PATH)
        if os.path.isdir(backup_locales):
            shutil.copytree(backup_locales, LOCALES_PATH)
        shutil.rmtree(backup_root, ignore_errors=True)


def test_crontab_schedule():
    try:
        result = subprocess.run(["crontab", "-l"], capture_output=True, text=True, check=True)
        crontab_output = result.stdout
    except subprocess.CalledProcessError:
        pytest.fail("Failed to read crontab. Ensure the crontab is set up for the current user.")

    # Regex to match: 15 3 * * * followed by any characters and the script path
    pattern = re.compile(r"^15\s+3\s+\*\s+\*\s+\*.*?/home/user/update_translations\.py(\s|$)", re.MULTILINE)
    assert pattern.search(crontab_output), "The crontab does not contain the correct schedule (15 3 * * *) or does not point to the absolute path of the script."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
