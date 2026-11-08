#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import re
import secrets
import stat
import string
import subprocess

SCRIPT = "/home/user/process_loc.sh"
INPUT = "/home/user/translations.csv"
OUTPUTS = [
    "/home/user/long_format.csv",
    "/home/user/anomalies.csv",
    "/home/user/sample.csv",
]


def get_original_data():
    return [
        {"key": "greeting", "en": "Hello", "fr": "Bonjour", "de": "Hallo", "es": "Hola"},
        {"key": "goodbye", "en": "Goodbye", "fr": "Au revoir", "de": "Auf Wiedersehen", "es": "Adiós"},
        {"key": "error_1", "en": "An unexpected error occurred.", "fr": "Une erreur inattendue s'est produite.", "de": "Ein unerwarteter Fehler ist aufgetreten.", "es": "Un error inesperado ha ocurrido."},
        {"key": "short_test", "en": "Yes", "fr": "Oui", "de": "Ja", "es": "Sí"},
        {"key": "anomaly_test", "en": "This is a normal sentence.", "fr": "C'est une phrase normale.", "de": "Dies ist ein normaler Satz.", "es": "X"},
        {"key": "long_anomaly", "en": "Short", "fr": "Ceci est une traduction française extrêmement longue qui ne correspond pas du tout au texte d'origine.", "de": "Kurz", "es": "Corto"},
        {"key": "btn_ok", "en": "OK", "fr": "OK", "de": "OK", "es": "OK"},
        {"key": "btn_cancel", "en": "Cancel", "fr": "Annuler", "de": "Abbrechen", "es": "Cancelar"}
    ]


def write_input(rows):
    lines = ["key,en,fr,de,es"]
    for row in rows:
        lines.append(",".join([row["key"], row["en"], row["fr"], row["de"], row["es"]]))
    with open(INPUT, "wb") as f:
        f.write(("\n".join(lines) + "\n").encode("iso-8859-1"))


def run_script(rows):
    write_input(rows)
    for path in OUTPUTS:
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    env = os.environ.copy()
    env["LC_ALL"] = "C.UTF-8"
    result = subprocess.run(
        [SCRIPT],
        cwd="/home/user",
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, (
        f"{SCRIPT} failed with exit status {result.returncode}. "
        f"stdout={result.stdout!r}, stderr={result.stderr!r}"
    )


def check_script_exists_and_executable():
    script_path = "/home/user/process_loc.sh"
    assert os.path.exists(script_path), f"Script missing at {script_path}"
    assert os.access(script_path, os.X_OK), f"Script at {script_path} is not executable"
    assert stat.S_ISREG(os.stat(script_path).st_mode), f"{script_path} is not a regular file"
    with open(script_path, "rb") as f:
        first_line = f.readline()
    assert re.match(rb"^#!\s*(?:/usr/bin/env\s+)?(?:/usr/bin/|/bin/)?bash(?:\s|$)", first_line), \
        f"{script_path} is not a Bash script"


def check_long_format_csv(rows):
    file_path = "/home/user/long_format.csv"
    assert os.path.exists(file_path), f"Missing {file_path}"

    with open(file_path, "r", encoding="utf-8") as f:
        reader = list(csv.reader(f))

    assert len(reader) > 0, f"{file_path} is empty"
    assert reader[0] == ["key", "locale", "translation"], f"Incorrect header in {file_path}"

    expected_rows = []
    for row in rows:
        key = row["key"]
        for loc in ["en", "fr", "de", "es"]:
            expected_rows.append([key, loc, row[loc]])

    actual_data = reader[1:]
    assert len(actual_data) == len(expected_rows), f"Expected {len(expected_rows)} rows, got {len(actual_data)}"

    for row in expected_rows:
        assert row in actual_data, f"Missing expected row {row} in {file_path}"


def check_anomalies_csv(rows):
    file_path = "/home/user/anomalies.csv"
    assert os.path.exists(file_path), f"Missing {file_path}"

    with open(file_path, "r", encoding="utf-8") as f:
        reader = list(csv.reader(f))

    assert len(reader) > 0, f"{file_path} is empty"
    assert reader[0] == ["key", "locale", "en_length", "trans_length"], f"Incorrect header in {file_path}"

    expected_anomalies = []
    for row in rows:
        key = row["key"]
        en_len = len(row["en"])
        for loc in ["fr", "de", "es"]:
            trans_len = len(row[loc])
            if trans_len < 0.3 * en_len or trans_len > 3.0 * en_len:
                expected_anomalies.append([key, loc, str(en_len), str(trans_len)])

    actual_data = reader[1:]
    assert len(actual_data) == len(expected_anomalies), f"Expected {len(expected_anomalies)} anomalies, got {len(actual_data)}"

    for row in expected_anomalies:
        assert row in actual_data, f"Missing expected anomaly {row} in {file_path}"


def check_sample_csv(rows):
    file_path = "/home/user/sample.csv"
    assert os.path.exists(file_path), f"Missing {file_path}"

    with open(file_path, "r", encoding="utf-8") as f:
        reader = list(csv.reader(f))

    assert len(reader) > 0, f"{file_path} is empty"
    assert reader[0] == ["key", "locale", "translation"], f"Incorrect header in {file_path}"

    sorted_keys = sorted([row["key"] for row in rows])
    top_2_keys = sorted_keys[:2]

    expected_sample = []
    for loc in ["de", "en", "es", "fr"]:
        for key in top_2_keys:
            trans = next(r[loc] for r in rows if r["key"] == key)
            expected_sample.append([key, loc, trans])

    actual_data = reader[1:]
    assert len(actual_data) == len(expected_sample), f"Expected {len(expected_sample)} sample rows, got {len(actual_data)}"
    assert actual_data == expected_sample, f"Sample data is incorrect or not sorted correctly. Expected: {expected_sample}, Got: {actual_data}"


def check_outputs(rows):
    check_long_format_csv(rows)
    check_anomalies_csv(rows)
    check_sample_csv(rows)


def make_dynamic_data():
    alphabet = string.ascii_lowercase + string.digits
    nonce = "".join(secrets.choice(alphabet) for _ in range(10))
    return [
        {"key": "zeta_" + nonce, "en": "A" * 20, "fr": "é" * 5, "de": "ü" * 60, "es": "ñ" * 61},
        {"key": "alpha_" + nonce, "en": "B" * 10, "fr": "é" * 3, "de": "ö" * 2, "es": "Hola" + nonce},
        {"key": "mu_" + nonce, "en": "Dynamic" + nonce, "fr": "Français" + nonce, "de": "Grüße" + nonce, "es": "Español" + nonce},
        {"key": "beta_" + nonce, "en": "Review" + nonce, "fr": "Révision" + nonce, "de": "Prüfung" + nonce, "es": "Revisión" + nonce},
        {"key": "omega_" + nonce, "en": "Content" + nonce, "fr": "Contenu" + nonce, "de": "Inhalt" + nonce, "es": "Contenido" + nonce},
    ]


def test_complete_pipeline_execution():
    check_script_exists_and_executable()
    original = get_original_data()
    try:
        # Preserve all original fixed-data assertions, but require the submitted
        # artifact itself to recreate the files from a clean state first.
        run_script(original)
        check_outputs(original)

        # A fresh, unpredictable ISO-8859-1 input prevents passing by writing the
        # known setup outputs directly. It also exercises character lengths and
        # both strict anomaly thresholds.
        dynamic = make_dynamic_data()
        run_script(dynamic)
        check_outputs(dynamic)
    finally:
        # Leave the task's original input and generated outputs in their expected state.
        write_input(original)
        try:
            for path in OUTPUTS:
                try:
                    os.remove(path)
                except FileNotFoundError:
                    pass
            subprocess.run(
                [SCRIPT], cwd="/home/user",
                env={**os.environ, "LC_ALL": "C.UTF-8"},
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                timeout=20,
            )
        except Exception:
            pass
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
