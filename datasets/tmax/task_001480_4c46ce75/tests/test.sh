#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import difflib
import json
import os
import re
import subprocess
import pytest

MATCHES_PATH = "/home/user/matches.json"
REPORT_PATH = "/home/user/report.txt"
CATALOG_PATH = "/app/catalog.csv"
MANIFEST_PATH = "/app/manifest.png"


def normalize(text):
    return " ".join(re.sub(r"[^a-z0-9]+", " ", text.lower()).split())


def source_data():
    assert os.path.isfile(MANIFEST_PATH), f"File not found: {MANIFEST_PATH}"
    assert os.path.isfile(CATALOG_PATH), f"File not found: {CATALOG_PATH}"

    with open(CATALOG_PATH, newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        assert reader.fieldnames == ["product_id", "product_name"]
        catalog = list(reader)

    expected_catalog = [
        {"product_id": "101", "product_name": "Widget Pro X"},
        {"product_id": "102", "product_name": "Blender 500W Black"},
        {"product_id": "103", "product_name": "Coffee Maker Deluxe"},
        {"product_id": "104", "product_name": "SuperPhone 128GB"},
        {"product_id": "105", "product_name": "SuperPhone 64GB"},
        {"product_id": "106", "product_name": "Widget Standard"},
    ]
    assert catalog == expected_catalog, "The master catalog was modified"

    result = subprocess.run(
        ["tesseract", MANIFEST_PATH, "stdout", "--psm", "6"],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=True,
    )
    ocr_lines = [line.strip() for line in result.stdout.splitlines() if line.strip()]
    expected_source_lines = [
        "1x Wdget Pro X",
        "2x Blndr 500w Blck",
        "1x Cff Makr Dlux",
        "4x SuperPhone 128GB",
    ]
    assert ocr_lines == expected_source_lines, (
        f"Unexpected OCR source lines; the manifest may have been modified: {ocr_lines!r}"
    )
    return catalog, ocr_lines


def closest_product(line, catalog):
    normalized_line = normalize(line)
    return max(
        catalog,
        key=lambda row: difflib.SequenceMatcher(
            None, normalized_line, normalize(row["product_name"])
        ).ratio(),
    )


def test_matches_json_exists_and_metric():
    catalog, ocr_lines = source_data()
    assert os.path.exists(MATCHES_PATH), f"File not found: {MATCHES_PATH}"

    with open(MATCHES_PATH, "r", encoding="utf-8") as f:
        try:
            matches = json.load(f)
        except json.JSONDecodeError as e:
            pytest.fail(f"Failed to parse {MATCHES_PATH}: {e}")

    assert isinstance(matches, list), f"Expected list in {MATCHES_PATH}, got {type(matches)}"

    ground_truth_ids = ["101", "102", "103", "104"]
    predicted_ids = []
    for m in matches:
        assert isinstance(m, dict), "Each item in matches.json must be a dictionary"
        assert "ocr_text" in m, "Missing key 'ocr_text' in matches.json"
        assert "matched_product_id" in m, "Missing key 'matched_product_id' in matches.json"
        predicted_ids.append(str(m.get("matched_product_id", "")))

    correct = sum(1 for gt in ground_truth_ids if gt in predicted_ids)
    accuracy = correct / len(ground_truth_ids)
    assert accuracy >= 0.75, f"Match accuracy is {accuracy}, expected >= 0.75"

    assert len(matches) == len(ocr_lines), "There must be exactly one match per nonempty OCR line"
    expected_matches = []
    for line in ocr_lines:
        product = closest_product(line, catalog)
        expected_matches.append({
            "ocr_text": line,
            "matched_product_id": product["product_id"],
        })

    for index, match in enumerate(matches):
        assert set(match.keys()) == {"ocr_text", "matched_product_id"}, (
            "Each matches.json dictionary must contain exactly the required keys"
        )
        assert isinstance(match["ocr_text"], str), "ocr_text must be a string"
        assert isinstance(match["matched_product_id"], str), "matched_product_id must be a string"
        assert match == expected_matches[index], (
            f"Incorrect match for OCR line {index + 1}: expected {expected_matches[index]!r}, "
            f"got {match!r}"
        )


def test_report_txt_exists():
    catalog, ocr_lines = source_data()
    assert os.path.exists(REPORT_PATH), f"File not found: {REPORT_PATH}"
    with open(REPORT_PATH, "r", encoding="utf-8") as f:
        content = f.read().strip()
    assert len(content) > 0, f"{REPORT_PATH} is empty"

    lines = content.split("\n")
    for line in lines:
        if line.strip():
            assert line.startswith("Match: ["), f"Line in report.txt does not match template: {line}"
            assert "] " in line, f"Line in report.txt does not match template: {line}"
            assert " <- " in line, f"Line in report.txt does not match template: {line}"

    expected_lines = []
    for raw_line in ocr_lines:
        product = closest_product(raw_line, catalog)
        expected_lines.append(
            f"Match: [{product['product_id']}] {normalize(product['product_name'])} <- {raw_line}"
        )
    assert lines == expected_lines, (
        "report.txt must contain exactly one correctly formatted line for each OCR match"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
