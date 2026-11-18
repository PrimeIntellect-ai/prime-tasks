#!/bin/bash
mkdir -p /logs/verifier
reward=0

if [ -f /home/user/etl.cpp ] && [ ! -L /home/user/etl.cpp ]; then
    if cd /home/user && timeout 20 g++ -std=c++17 -o etl etl.cpp; then
        rm -f /home/user/measurements.csv /home/user/metadata.csv
        cat << 'EOF' > /home/user/measurements.csv
id,length,width,height,stated_volume
A1,10.0,5.0,2.0,100.0
A2,12.0,10.0,5.0,600.0
B1,7.5,4.0,2.0,62.0
B2,8.0,8.0,8.0,500.0
C1,15.0,2.0,2.0,60.5
C2,20.0,10.0,10.0,2000.0
EOF
        cat << 'EOF' > /home/user/metadata.csv
id,name,price_string
A1,Café,€12.50
A2,抹茶,¥1500.00
B1,Käse,€8.99
B2,سجادة,£45.00
C1,Crème,€15.25
C2,Té,£20.00
EOF
        rm -f /home/user/cleaned_products.jsonl

        if cd /home/user && timeout 10 runuser -u user -- ./etl; then
            cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import pytest


def test_cleaned_products_exists():
    filepath = "/home/user/cleaned_products.jsonl"
    assert os.path.exists(filepath), f"File {filepath} does not exist. The C++ program did not generate the expected output file."


def test_cleaned_products_content():
    filepath = "/home/user/cleaned_products.jsonl"
    assert os.path.exists(filepath), "Missing output file."

    with open(filepath, "r", encoding="utf-8") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 5, f"Expected exactly 5 valid records, but found {len(lines)}."

    parsed_records = []
    for i, line in enumerate(lines):
        try:
            record = json.loads(line)
            parsed_records.append(record)
        except json.JSONDecodeError:
            pytest.fail(f"Line {i+1} is not valid JSON: {line}")

    ids = [r.get("id") for r in parsed_records]
    assert ids == sorted(ids), "The output records are not ordered by 'id' ascending."

    expected_data = {
        "A1": {"name": "Café", "calculated_volume": 100.00, "numeric_price": 12.50},
        "A2": {"name": "抹茶", "calculated_volume": 600.00, "numeric_price": 1500.00},
        "B2": {"name": "سجادة", "calculated_volume": 512.00, "numeric_price": 45.00},
        "C1": {"name": "Crème", "calculated_volume": 60.00, "numeric_price": 15.25},
        "C2": {"name": "Té", "calculated_volume": 2000.00, "numeric_price": 20.00},
    }

    assert len(parsed_records) == len(expected_data), "Incorrect number of records."

    for record in parsed_records:
        assert set(record) == {"id", "name", "calculated_volume", "numeric_price"}, "Incorrect JSON object structure."
        rid = record.get("id")
        assert rid in expected_data, f"Unexpected record with id {rid}."

        expected = expected_data[rid]
        assert record.get("name") == expected["name"], f"Incorrect name for id {rid}."

        calc_vol = record.get("calculated_volume")
        assert isinstance(calc_vol, (int, float)), f"calculated_volume for {rid} must be a number."
        assert abs(calc_vol - expected["calculated_volume"]) < 1e-5, f"Incorrect calculated_volume for id {rid}."

        num_price = record.get("numeric_price")
        assert isinstance(num_price, (int, float)), f"numeric_price for {rid} must be a number."
        assert abs(num_price - expected["numeric_price"]) < 1e-5, f"Incorrect numeric_price for id {rid}."


def test_two_decimal_places_formatting():
    filepath = "/home/user/cleaned_products.jsonl"
    assert os.path.exists(filepath), "Missing output file."

    with open(filepath, "r", encoding="utf-8") as f:
        lines = [line.strip() for line in f if line.strip()]

    for i, line in enumerate(lines):
        decimals = re.findall(r"\.\d+", line)
        for dec in decimals:
            assert len(dec) == 3, f"Line {i+1} does not format numbers to exactly 2 decimal places: {line}"

        for field in ("calculated_volume", "numeric_price"):
            occurrences = re.findall(r'"' + re.escape(field) + r'"\s*:', line)
            assert len(occurrences) == 1, f"Line {i+1} must contain {field} exactly once: {line}"
            pattern = r'"' + re.escape(field) + r'"\s*:\s*-?(?:0|[1-9]\d*)\.\d{2}(?=\s*[,}])'
            assert re.search(pattern, line), f"Line {i+1} does not format {field} to exactly 2 decimal places: {line}"
TEST_EOF

            if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
                cat << 'DYNAMIC_EOF' > /tmp/test_dynamic.py
import json
import os
import random
import re
import secrets
import subprocess

home = "/home/user"
rng = random.SystemRandom()
token = secrets.token_hex(4).upper()
ids = [f"R{token}{letter}" for letter in "ABCDE"]
names = ["Étoile", "抹茶箱", "سجادة", "Crème", "Käse"]
currencies = ["€", "¥", "£", "€", "¥"]
factors = [1.0, 1.02, 0.971, 1.031, 0.99]

measurement_rows = []
metadata_rows = []
expected = {}
for index, rid in enumerate(ids):
    length = rng.randint(3, 12) + 0.5
    width = rng.randint(2, 9)
    height = rng.randint(2, 7)
    actual = length * width * height
    stated = actual * factors[index]
    price = rng.randint(10, 900) + rng.randint(0, 99) / 100.0
    measurement_rows.append([rid, f"{length:.1f}", str(width), str(height), f"{stated:.6f}"])
    metadata_rows.append([rid, names[index], currencies[index] + f"{price:.2f}"])
    if abs(stated - actual) <= 0.03 * actual:
        expected[rid] = {
            "id": rid,
            "name": names[index],
            "calculated_volume": round(actual, 2),
            "numeric_price": round(price, 2),
        }

measurement_rows.append([f"R{token}MEASURE_ONLY", "4.0", "5", "6", "120.0"])
metadata_rows.append([f"R{token}META_ONLY", "孤立", "€77.77"])
rng.shuffle(measurement_rows)
rng.shuffle(metadata_rows)

with open(os.path.join(home, "measurements.csv"), "w", encoding="utf-8", newline="") as f:
    f.write("id,length,width,height,stated_volume\n")
    for row in measurement_rows:
        f.write(",".join(row) + "\n")

with open(os.path.join(home, "metadata.csv"), "w", encoding="utf-8", newline="") as f:
    f.write("id,name,price_string\n")
    for row in metadata_rows:
        f.write(",".join(row) + "\n")

output = os.path.join(home, "cleaned_products.jsonl")
try:
    os.unlink(output)
except FileNotFoundError:
    pass

subprocess.run(
    ["runuser", "-u", "user", "--", os.path.join(home, "etl")],
    cwd=home,
    check=True,
    timeout=10,
)
assert os.path.isfile(output), "The executable did not generate cleaned_products.jsonl for the dynamic fixture."

with open(output, "r", encoding="utf-8") as f:
    raw_lines = [line.strip() for line in f if line.strip()]
assert len(raw_lines) == len(expected), f"Expected {len(expected)} dynamically derived valid records, found {len(raw_lines)}."

records = []
for line_number, line in enumerate(raw_lines, 1):
    record = json.loads(line)
    assert set(record) == {"id", "name", "calculated_volume", "numeric_price"}, "Incorrect JSON object structure."
    for field in ("calculated_volume", "numeric_price"):
        assert len(re.findall(r'"' + re.escape(field) + r'"\s*:', line)) == 1
        assert re.search(r'"' + re.escape(field) + r'"\s*:\s*-?(?:0|[1-9]\d*)\.\d{2}(?=\s*[,}])', line), f"Line {line_number} does not format {field} with exactly two decimal places: {line}"
    records.append(record)

assert [record["id"] for record in records] == sorted(expected), "Dynamic output is not ordered by id."
for record in records:
    rid = record["id"]
    assert rid in expected, f"Unexpected dynamic record {rid}."
    wanted = expected[rid]
    assert record["name"] == wanted["name"]
    assert isinstance(record["calculated_volume"], (int, float)) and not isinstance(record["calculated_volume"], bool)
    assert isinstance(record["numeric_price"], (int, float)) and not isinstance(record["numeric_price"], bool)
    assert abs(record["calculated_volume"] - wanted["calculated_volume"]) < 1e-5
    assert abs(record["numeric_price"] - wanted["numeric_price"]) < 1e-5
DYNAMIC_EOF

                if python3 /tmp/test_dynamic.py 2>&1; then
                    reward=1
                fi
            fi
        fi
    fi
fi

echo "$reward" > /logs/verifier/reward.txt
