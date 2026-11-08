#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import math
import os
import re
from functools import lru_cache

import pytesseract
from PIL import Image, ImageDraw, ImageOps

REFERENCE_PATH = "/app/reference_db.csv"
SCREENSHOT_PATH = "/app/ui_screenshot.png"
METRICS_PATH = "/home/user/metrics.json"
LOG_PATH = "/home/user/audit_log.txt"

EXPECTED_ROWS = [
    {"key": "ERR_404", "english": "Not Found", "french_expected": "Non trouvé"},
    {"key": "BTN_OK", "english": "OK", "french_expected": "D'accord"},
    {"key": "BTN_CANCEL", "english": "Cancel", "french_expected": "Annuler"},
    {"key": "MSG_WELCOME", "english": "Welcome", "french_expected": "Bienvenue"},
    {"key": "LBL_USER", "english": "Username", "french_expected": "Nom d'utilisateur"},
    {"key": "LBL_PASS", "english": "Password", "french_expected": "Mot de passe"},
    {"key": "MSG_LOGOUT", "english": "Log out", "french_expected": "Déconnexion"},
    {"key": "TXT_RETRY", "english": "Try again", "french_expected": "Réessayer"},
]

SCREEN_TEXT = """ERR_404: Non trouve
BTN_OK: D'accor
BTN_CANCEL: Anuler
MSG_WELCOME: Bienvenue
LBL_USER: Nom d utilisateur
LBL_PASS: Mot de passe
MSG_LOGOUT: Deconnexion
TXT_RETRY: Reessayer"""


def levenshtein(a, b):
    previous = list(range(len(b) + 1))
    for i, ca in enumerate(a, 1):
        current = [i]
        for j, cb in enumerate(b, 1):
            current.append(min(
                current[-1] + 1,
                previous[j] + 1,
                previous[j - 1] + (ca != cb),
            ))
        previous = current
    return previous[-1]


@lru_cache(maxsize=1)
def independently_computed_results():
    assert os.path.isfile(REFERENCE_PATH), f"Missing input: {REFERENCE_PATH}"
    with open(REFERENCE_PATH, newline="", encoding="utf-8") as f:
        rows = list(csv.DictReader(f))
    assert rows == EXPECTED_ROWS, f"{REFERENCE_PATH} was modified or is malformed"

    assert os.path.isfile(SCREENSHOT_PATH), f"Missing input: {SCREENSHOT_PATH}"
    actual_image = Image.open(SCREENSHOT_PATH).convert("RGB")
    expected_image = Image.new("RGB", (400, 300), color=(255, 255, 255))
    ImageDraw.Draw(expected_image).text((10, 10), SCREEN_TEXT, fill=(0, 0, 0))
    assert actual_image.size == expected_image.size and actual_image.tobytes() == expected_image.tobytes(), \
        f"{SCREENSHOT_PATH} was modified"

    # OCR the supplied artifact independently. Upscaling preserves the rendered
    # text while making the small default-font glyphs reliable for Tesseract.
    prepared = ImageOps.autocontrast(actual_image.convert("L"))
    prepared = prepared.resize(
        (prepared.width * 4, prepared.height * 4), Image.Resampling.NEAREST
    )
    prepared = prepared.point(lambda p: 255 if p > 180 else 0)
    ocr_text = pytesseract.image_to_string(prepared, config="--psm 6")

    extracted = {}
    for raw_line in ocr_text.splitlines():
        line = raw_line.strip()
        match = re.match(r"^([A-Z][A-Z0-9_]*):\s*(.*?)\s*$", line)
        if not match:
            continue
        key, translation = match.groups()
        translation = re.sub(r"\s+", " ", translation).strip()
        assert key not in extracted, f"OCR produced duplicate key {key!r}: {ocr_text!r}"
        extracted[key] = translation

    reference = {row["key"]: row["french_expected"] for row in rows}
    assert set(extracted) == set(reference), \
        f"OCR did not recover all rendered keys; got {extracted!r} from {ocr_text!r}"

    distances = {
        key: levenshtein(extracted[key], reference[key]) for key in reference
    }
    mean = sum(distances.values()) / len(distances)
    return distances, mean


def test_metrics_json_exists_and_valid():
    assert os.path.isfile(METRICS_PATH), f"Missing required file: {METRICS_PATH}"

    with open(METRICS_PATH, "r", encoding="utf-8") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"{METRICS_PATH} is not a valid JSON file"

    assert "mean_distance" in data, f"'mean_distance' key missing in {METRICS_PATH}"

    val = float(data["mean_distance"])
    target = 0.75
    tolerance = 0.15
    assert abs(val - target) <= tolerance, \
        f"mean_distance {val} is not within {tolerance} of target {target}"

    _, expected_mean = independently_computed_results()
    assert math.isfinite(val) and abs(val - expected_mean) <= 1e-9, \
        f"mean_distance {val} does not equal recomputed value {expected_mean}"


def test_audit_log_exists_and_format():
    assert os.path.isfile(LOG_PATH), f"Missing required file: {LOG_PATH}"

    with open(LOG_PATH, "r", encoding="utf-8") as f:
        content = f.read().strip()

    lines = content.split('\n')
    assert len(lines) >= 2, f"{LOG_PATH} must contain at least two lines for WORST and BEST"

    worst_found = False
    best_found = False
    parsed = {"WORST": [], "BEST": []}

    for line in lines:
        if line.startswith("WORST:"):
            worst_found = True
            keys = line.replace("WORST:", "", 1).strip().split(",")
            assert len(keys) >= 2, "WORST line must contain at least 2 keys"
            parsed["WORST"].append([key.strip() for key in keys])
        elif line.startswith("BEST:"):
            best_found = True
            keys = line.replace("BEST:", "", 1).strip().split(",")
            assert len(keys) >= 2, "BEST line must contain at least 2 keys"
            parsed["BEST"].append([key.strip() for key in keys])

    assert worst_found, "WORST line missing or incorrectly formatted in audit_log.txt"
    assert best_found, "BEST line missing or incorrectly formatted in audit_log.txt"

    distances, _ = independently_computed_results()
    worst_cutoff = sorted(distances.values(), reverse=True)[1]
    best_cutoff = sorted(distances.values())[1]

    for label, groups in parsed.items():
        for keys in groups:
            assert len(keys) == 2, f"{label} line must contain exactly 2 keys"
            assert len(set(keys)) == 2, f"{label} keys must be distinct"
            assert all(key in distances for key in keys), \
                f"{label} contains an unknown or unmatched key: {keys!r}"
            if label == "WORST":
                assert all(distances[key] >= worst_cutoff for key in keys), \
                    f"WORST keys are not among the two highest-distance strata: {keys!r}"
            else:
                assert all(distances[key] <= best_cutoff for key in keys), \
                    f"BEST keys are not among the two lowest-distance strata: {keys!r}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
