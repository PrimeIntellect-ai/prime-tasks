#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import csv
import stat
import pytest


def luhn_check(card_str):
    digits = [int(c) for c in card_str if c.isdigit()]
    if len(digits) != 16:
        return False

    checksum = 0
    reverse_digits = digits[::-1]
    for i, d in enumerate(reverse_digits):
        if i % 2 == 1:
            d *= 2
            if d > 9:
                d -= 9
        checksum += d
    return checksum % 10 == 0


def mask_email(email):
    if "@" not in email:
        return email
    local, domain = email.split("@", 1)
    if not local:
        return email
    return f"{local[0]}***@{domain}"


def mask_card(card_str):
    chars = list(card_str)
    digit_count = 0
    total_digits = sum(1 for c in chars if c.isdigit())

    for i in range(len(chars)):
        if chars[i].isdigit():
            digit_count += 1
            if total_digits - digit_count >= 4:
                chars[i] = 'X'
    return "".join(chars)


def get_expected_data():
    raw_csv = "/home/user/raw_data/users.csv"
    raw_json = "/home/user/raw_data/users.json"

    records = []

    if os.path.exists(raw_csv):
        with open(raw_csv, "r", encoding="utf-8") as f:
            reader = csv.DictReader(f)
            for row in reader:
                records.append({
                    "id": int(row["id"]),
                    "name": row["name"],
                    "email": row["email"],
                    "age": int(row["age"]),
                    "card": row["card"]
                })

    if os.path.exists(raw_json):
        with open(raw_json, "r", encoding="utf-8") as f:
            data = json.load(f)
            for row in data:
                records.append({
                    "id": int(row["id"]),
                    "name": row["name"],
                    "email": row["email"],
                    "age": int(row["age"]),
                    "card": row["card"]
                })

    valid_records = []
    for r in records:
        if r["age"] >= 18 and luhn_check(r["card"]):
            masked_record = {
                "id": r["id"],
                "name": r["name"],
                "email": mask_email(r["email"]),
                "age": r["age"],
                "card": mask_card(r["card"])
            }
            valid_records.append(masked_record)

    valid_records.sort(key=lambda x: x["id"])
    return valid_records


def test_required_artifacts():
    source = "/home/user/workspace/cleaner.cpp"
    executable = "/home/user/workspace/cleaner"
    assert os.path.isfile(source), f"Source file {source} does not exist."
    assert os.path.isfile(executable), f"Compiled program {executable} does not exist."
    mode = os.stat(executable).st_mode
    assert stat.S_ISREG(mode), f"{executable} is not a regular file."
    assert os.access(executable, os.X_OK), f"{executable} is not executable."
    with open(executable, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{executable} is not a compiled ELF executable."


def test_clean_data_directory():
    clean_dir = "/home/user/clean_data"
    assert os.path.isdir(clean_dir), f"Directory {clean_dir} does not exist."

    files = set(os.listdir(clean_dir))
    expected_files = {"unified.csv", "unified.json"}
    assert files == expected_files, f"Expected exactly {expected_files} in {clean_dir}, but found {files}. Intermediate files might have been left behind."


def test_unified_csv():
    csv_path = "/home/user/clean_data/unified.csv"
    assert os.path.isfile(csv_path), f"File {csv_path} does not exist."

    expected_data = get_expected_data()

    actual_data = []
    with open(csv_path, "r", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        assert reader.fieldnames == ["id", "name", "email", "age", "card"], "CSV header is incorrect."
        for row in reader:
            actual_data.append({
                "id": int(row["id"]),
                "name": row["name"],
                "email": row["email"],
                "age": int(row["age"]),
                "card": row["card"]
            })

    assert actual_data == expected_data, "The contents of unified.csv do not match the expected masked and filtered records."


def test_unified_json():
    json_path = "/home/user/clean_data/unified.json"
    assert os.path.isfile(json_path), f"File {json_path} does not exist."

    expected_data = get_expected_data()

    with open(json_path, "r", encoding="utf-8") as f:
        try:
            actual_data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("unified.json is not a valid JSON file.")

    assert isinstance(actual_data, list), "unified.json must contain a JSON array."

    for row in actual_data:
        assert isinstance(row.get("id"), int), "ID in JSON must be an integer."
        assert isinstance(row.get("age"), int), "Age in JSON must be an integer."

    assert actual_data == expected_data, "The contents of unified.json do not match the expected masked and filtered records."
TEST_EOF

status=0

# Replace the visible fixtures with randomized records so precomputed output cannot pass.
python3 - << 'PY' || status=1
import csv
import json
import os
import secrets


def luhn(number):
    digits = [int(c) for c in number]
    total = 0
    for i, digit in enumerate(reversed(digits)):
        if i % 2 == 1:
            digit *= 2
            if digit > 9:
                digit -= 9
        total += digit
    return total % 10 == 0


def valid_card():
    prefix = ''.join(str(secrets.randbelow(10)) for _ in range(15))
    for check in range(10):
        candidate = prefix + str(check)
        if luhn(candidate):
            return candidate
    raise RuntimeError("unable to generate Luhn card")


def dashed(card):
    return '-'.join(card[i:i + 4] for i in range(0, 16, 4))


def invalid(card):
    replacement = str((int(card[-1]) + 1) % 10)
    candidate = card[:-1] + replacement
    assert not luhn(candidate)
    return candidate

os.makedirs('/home/user/raw_data', exist_ok=True)
base = secrets.randbelow(700000) + 10000
ids = [base + x for x in (31, 4, 72, 18, 55, 9)]
tag = secrets.token_hex(6)
c1, c2, c3, c4 = valid_card(), valid_card(), valid_card(), valid_card()

csv_rows = [
    {"id": ids[0], "name": "Csv Valid " + tag, "email": "alpha." + tag + "@dynamic.example", "age": 18, "card": dashed(c1)},
    {"id": ids[1], "name": "Csv Underage " + tag, "email": "minor." + tag + "@dynamic.example", "age": 17, "card": dashed(c2)},
    {"id": ids[2], "name": "Csv Bad Card " + tag, "email": "bad." + tag + "@dynamic.example", "age": 46, "card": dashed(invalid(c3))},
]
json_rows = [
    {"id": ids[3], "name": "Json Plain " + tag, "email": "plain." + tag + "@json.example", "age": 29, "card": c2},
    {"id": ids[4], "name": "Json Short " + tag, "email": "short." + tag + "@json.example", "age": 38, "card": c3[:-1]},
    {"id": ids[5], "name": "Json Dashed " + tag, "email": "z" + tag + "@json.example", "age": 67, "card": dashed(c4)},
]

with open('/home/user/raw_data/users.csv', 'w', newline='', encoding='utf-8') as f:
    writer = csv.DictWriter(f, fieldnames=['id', 'name', 'email', 'age', 'card'])
    writer.writeheader()
    writer.writerows(csv_rows)

with open('/home/user/raw_data/users.json', 'w', encoding='utf-8') as f:
    json.dump(json_rows, f, indent=2)
PY

# Confirm the submitted source is compilable and retain a separately built copy.
if [ "$status" -eq 0 ]; then
    g++ -std=c++17 -O2 /home/user/workspace/cleaner.cpp -o /tmp/cleaner_from_source || status=1
fi

run_and_check() {
    program="$1"
    rm -rf /home/user/clean_data
    timeout 20s "$program" >/tmp/cleaner.stdout 2>/tmp/cleaner.stderr || return 1
    python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1 || return 1
}

# Exercise both the required submitted executable and a build of the required source.
if [ "$status" -eq 0 ]; then
    run_and_check /home/user/workspace/cleaner || status=1
fi
if [ "$status" -eq 0 ]; then
    run_and_check /tmp/cleaner_from_source || status=1
fi

if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
