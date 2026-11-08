#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import hashlib
import json
import os
import random
import re
import secrets
import subprocess
import tempfile
import uuid

import pytest
from PIL import Image, ImageDraw, ImageFont

SCRIPT_PATH = "/home/user/validate_l10n.py"
CLEAN_CORPUS_DIR = "/app/corpus/clean"
EVIL_CORPUS_DIR = "/app/corpus/evil"
SECRET_IMAGE = "/app/l10n_secret.png"


def run_validator(path):
    return subprocess.run(
        ["python3", SCRIPT_PATH, path],
        capture_output=True,
        timeout=15,
    )


def test_script_exists():
    assert os.path.isfile(SCRIPT_PATH), f"Agent script not found at {SCRIPT_PATH}"


def test_adversarial_corpus():
    assert os.path.isfile(SCRIPT_PATH), f"Agent script not found at {SCRIPT_PATH}"

    clean_files = glob.glob(os.path.join(CLEAN_CORPUS_DIR, "*.json"))
    evil_files = glob.glob(os.path.join(EVIL_CORPUS_DIR, "*.json"))

    assert len(clean_files) > 0, "No clean corpus files found."
    assert len(evil_files) > 0, "No evil corpus files found."

    clean_failures = []
    for clean_file in clean_files:
        result = run_validator(clean_file)
        if result.returncode != 0:
            clean_failures.append(os.path.basename(clean_file))

    evil_failures = []
    for evil_file in evil_files:
        result = run_validator(evil_file)
        if result.returncode == 0:
            evil_failures.append(os.path.basename(evil_file))

    error_msgs = []
    if evil_failures:
        error_msgs.append(
            f"{len(evil_failures)} of {len(evil_files)} evil bypassed: "
            + ", ".join(evil_failures)
        )
    if clean_failures:
        error_msgs.append(
            f"{len(clean_failures)} of {len(clean_files)} clean modified/rejected: "
            + ", ".join(clean_failures)
        )

    if error_msgs:
        pytest.fail(" | ".join(error_msgs))


def test_generated_hidden_cases_and_current_ocr_salt():
    assert os.path.isfile(SCRIPT_PATH), f"Agent script not found at {SCRIPT_PATH}"
    assert os.path.isfile(SECRET_IMAGE), f"Salt image not found at {SECRET_IMAGE}"

    with open(SECRET_IMAGE, "rb") as f:
        original_image = f.read()

    try:
        displayed_salt = "VerifierSalt" + str(secrets.randbelow(90000000) + 10000000)
        image = Image.new("RGB", (800, 110), "white")
        draw = ImageDraw.Draw(image)
        font_path = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
        font = ImageFont.truetype(font_path, 48) if os.path.isfile(font_path) else ImageFont.load_default()
        draw.text((20, 20), f"SALT: {displayed_salt}", fill="black", font=font)
        image.save(SECRET_IMAGE)

        ocr = subprocess.run(
            ["tesseract", SECRET_IMAGE, "stdout"],
            capture_output=True,
            text=True,
            timeout=15,
            check=True,
        ).stdout
        match = re.search(r"SALT:\s*([^\s]+)", ocr)
        assert match, f"Verifier could not OCR its generated salt image: {ocr!r}"
        salt = match.group(1).strip()
        assert salt == displayed_salt, f"Generated salt was not OCR-stable: {ocr!r}"

        def signature(msgid, msgstr, selected_salt=salt):
            return hashlib.md5((msgid + msgstr + selected_salt).encode("utf-8")).hexdigest()

        valid_one = [
            {"msgid": "menu.file.open", "msgstr": "Ouvrir", "hash": signature("menu.file.open", "Ouvrir")},
            {"msgid": "status.snowman", "msgstr": "Bonhomme de neige ☃", "hash": signature("status.snowman", "Bonhomme de neige ☃")},
        ]
        valid_two = [
            {"msgid": "x", "msgstr": "", "hash": signature("x", "")},
            {"msgid": "xy", "msgstr": "z", "hash": signature("xy", "z")},
            {"msgid": "x.y", "msgstr": "日本語", "hash": signature("x.y", "日本語")},
        ]
        duplicate = [
            {"msgid": "repeat.id", "msgstr": "First", "hash": signature("repeat.id", "First")},
            {"msgid": "repeat.id", "msgstr": "Second", "hash": signature("repeat.id", "Second")},
        ]
        bad_digest = [
            {"msgid": "account.save", "msgstr": "Enregistrer", "hash": "0" * 32}
        ]
        wrong_salt = "DefinitelyNot" + salt
        wrong_salt_case = [
            {
                "msgid": "dialog.cancel",
                "msgstr": "Annuler",
                "hash": signature("dialog.cancel", "Annuler", wrong_salt),
            }
        ]
        mixed = [
            {"msgid": "good.id", "msgstr": "Correct", "hash": signature("good.id", "Correct")},
            {"msgid": "bad.id", "msgstr": "Corrupt", "hash": signature("bad.id", "Corrupt")[:-1] + "f"},
        ]
        if mixed[1]["hash"] == signature("bad.id", "Corrupt"):
            mixed[1]["hash"] = mixed[1]["hash"][:-1] + "e"

        cases = [
            (valid_one, 0),
            (valid_two, 0),
            (duplicate, 1),
            (bad_digest, 1),
            (wrong_salt_case, 1),
            (mixed, 1),
        ]
        random.SystemRandom().shuffle(cases)

        failures = []
        with tempfile.TemporaryDirectory(prefix="l10n_validation_") as case_dir:
            for data, expected in cases:
                path = os.path.join(case_dir, uuid.uuid4().hex + ".json")
                with open(path, "w", encoding="utf-8") as f:
                    json.dump(data, f, ensure_ascii=False)
                result = run_validator(path)
                if result.returncode != expected:
                    failures.append(
                        f"case {os.path.basename(path)} expected exit {expected}, "
                        f"got {result.returncode}; stdout={result.stdout!r}, stderr={result.stderr!r}"
                    )

        assert not failures, " | ".join(failures)
    finally:
        with open(SECRET_IMAGE, "wb") as f:
            f.write(original_image)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
