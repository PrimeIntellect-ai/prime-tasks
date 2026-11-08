#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import secrets
import shutil
import subprocess
import xml.etree.ElementTree as ET

import pytest

WORKSPACE = "/home/user/workspace"


def test_copied_csv_exists():
    path = "/home/user/workspace/translations.csv"
    assert os.path.exists(path), f"Copied CSV missing at {path}. Did you copy it from the remote directory?"


def test_process_script_exists_and_regenerates_outputs():
    script = os.path.join(WORKSPACE, "process.py")
    assert os.path.isfile(script), f"Required Python script missing at {script}"

    long_csv = os.path.join(WORKSPACE, "translations_long.csv")
    output_dir = os.path.join(WORKSPACE, "output")
    if os.path.exists(long_csv):
        os.remove(long_csv)
    if os.path.exists(output_dir):
        shutil.rmtree(output_dir)

    result = subprocess.run(
        ["python3", script],
        cwd=WORKSPACE,
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"process.py failed with exit code {result.returncode}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def test_long_csv():
    path = "/home/user/workspace/translations_long.csv"
    assert os.path.exists(path), f"Long CSV missing at {path}"

    with open(path, 'r', encoding='utf-8') as f:
        reader = csv.reader(f)
        header = next(reader, None)
        assert header == ['string_id', 'locale', 'value'], f"CSV columns incorrect. Expected ['string_id', 'locale', 'value'], got {header}"

        rows = list(reader)
        assert len(rows) == 12, f"CSV should have exactly 12 data rows, found {len(rows)}"

        expected_rows = [
            ['greeting', 'en', 'Hello'],
            ['greeting', 'es', 'Hola'],
            ['greeting', 'fr', 'Bonjour'],
            ['farewell', 'en', 'Goodbye'],
            ['farewell', 'es', 'Adiós'],
            ['farewell', 'fr', 'Au revoir'],
            ['login', 'en', 'Log In'],
            ['login', 'es', 'Iniciar sesión'],
            ['login', 'fr', 'Connexion'],
            ['error_404', 'en', 'Not Found'],
            ['error_404', 'es', 'No encontrado'],
            ['error_404', 'fr', 'Introuvable']
        ]

        for er in expected_rows:
            assert er in rows, f"Expected row {er} not found in {path}"


def test_xml_outputs():
    expected_data = {
        'en': {
            'greeting': 'Hello',
            'farewell': 'Goodbye',
            'login': 'Log In',
            'error_404': 'Not Found'
        },
        'es': {
            'greeting': 'Hola',
            'farewell': 'Adiós',
            'login': 'Iniciar sesión',
            'error_404': 'No encontrado'
        },
        'fr': {
            'greeting': 'Bonjour',
            'farewell': 'Au revoir',
            'login': 'Connexion',
            'error_404': 'Introuvable'
        }
    }

    for loc, strings_dict in expected_data.items():
        xml_path = f"/home/user/workspace/output/values-{loc}/strings.xml"
        assert os.path.exists(xml_path), f"Missing XML output for locale '{loc}' at {xml_path}"

        try:
            tree = ET.parse(xml_path)
        except ET.ParseError as e:
            pytest.fail(f"Failed to parse XML at {xml_path}: {e}")

        root = tree.getroot()
        assert root.tag == 'resources', f"Root element should be 'resources' in {xml_path}, got '{root.tag}'"

        strings = root.findall('string')
        assert len(strings) == 4, f"Should be exactly 4 'string' elements in {xml_path}, found {len(strings)}"

        actual_strings = {el.get('name'): el.text for el in strings}
        for expected_name, expected_value in strings_dict.items():
            assert expected_name in actual_strings, f"Missing string name='{expected_name}' in {xml_path}"
            assert actual_strings[expected_name] == expected_value, f"Value mismatch for '{expected_name}' in {xml_path}. Expected '{expected_value}', got '{actual_strings[expected_name]}'"


def test_process_handles_runtime_generated_input():
    token = secrets.token_hex(8)
    locales = [f"x{token[:6]}", f"y{token[6:12]}"]
    string_ids = [f"item_{token}_{i}" for i in range(3)]
    values = {
        locale: {
            string_id: f"value_{token}_{locale}_{i}"
            for i, string_id in enumerate(string_ids)
        }
        for locale in locales
    }

    copied_csv = os.path.join(WORKSPACE, "translations.csv")
    with open(copied_csv, "w", encoding="utf-8", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["string_id", *locales])
        for string_id in string_ids:
            writer.writerow([string_id, *[values[locale][string_id] for locale in locales]])

    long_csv = os.path.join(WORKSPACE, "translations_long.csv")
    output_dir = os.path.join(WORKSPACE, "output")
    if os.path.exists(long_csv):
        os.remove(long_csv)
    if os.path.exists(output_dir):
        shutil.rmtree(output_dir)

    script = os.path.join(WORKSPACE, "process.py")
    result = subprocess.run(
        ["python3", script],
        cwd=WORKSPACE,
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"process.py failed on generated input with exit code {result.returncode}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )

    assert os.path.exists(long_csv), "process.py did not regenerate translations_long.csv"
    with open(long_csv, "r", encoding="utf-8", newline="") as f:
        reader = csv.reader(f)
        header = next(reader, None)
        rows = list(reader)

    assert header == ["string_id", "locale", "value"], f"CSV columns incorrect after regeneration: {header}"
    expected_rows = {
        (string_id, locale, values[locale][string_id])
        for string_id in string_ids
        for locale in locales
    }
    assert len(rows) == len(expected_rows), f"Unexpected number of generated rows: {len(rows)}"
    assert {tuple(row) for row in rows} == expected_rows, "Long CSV was not derived from the generated input"

    for locale in locales:
        xml_path = os.path.join(output_dir, f"values-{locale}", "strings.xml")
        assert os.path.exists(xml_path), f"Missing generated XML for runtime locale '{locale}'"
        try:
            root = ET.parse(xml_path).getroot()
        except ET.ParseError as e:
            pytest.fail(f"Failed to parse generated XML at {xml_path}: {e}")

        assert root.tag == "resources", f"Root element should be 'resources' in {xml_path}"
        strings = root.findall("string")
        assert len(strings) == len(string_ids), f"Wrong number of strings in {xml_path}"
        actual = {element.get("name"): element.text for element in strings}
        assert actual == values[locale], f"XML for locale '{locale}' was not derived from the generated input"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
