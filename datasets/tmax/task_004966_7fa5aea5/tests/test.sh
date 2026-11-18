#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import re
import secrets
import shlex
import shutil
import sqlite3
import subprocess
import tempfile
from collections import Counter

import pytest

HOME = "/home/user"
SNAPSHOTS = "/app/data/snapshots"
METRIC = "/app/bin/eval_metric"
COLUMNS = ["date", "msg_id", "locale", "translation"]


def metric_score(text):
    result = subprocess.run(
        [METRIC, text], capture_output=True, text=True, timeout=10, check=True
    )
    return float(result.stdout.strip())


def is_spam(text):
    return metric_score(text) > 0.5


def read_long(path):
    with open(path, newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        assert reader.fieldnames == COLUMNS, f"Incorrect columns in {path}: {reader.fieldnames}"
        return [tuple(row[c] for c in COLUMNS) for row in reader]


def expected_reshaped_rows():
    rows = []
    files = sorted(
        os.path.join(SNAPSHOTS, name)
        for name in os.listdir(SNAPSHOTS)
        if name.endswith(".csv")
    )
    assert files, "No snapshot inputs found"
    for path in files:
        with open(path, newline="", encoding="utf-8") as f:
            reader = csv.DictReader(f)
            assert reader.fieldnames is not None
            assert reader.fieldnames[:2] == ["date", "msg_id"]
            locales = reader.fieldnames[2:]
            for row in reader:
                for locale in locales:
                    rows.append((row["date"], row["msg_id"], locale, row[locale]))
    return rows


def run_orchestrator():
    for path in [
        os.path.join(HOME, "reshaped_long.csv"),
        os.path.join(HOME, "sanitized_long.csv"),
        os.path.join(HOME, "locales.db"),
    ]:
        if os.path.lexists(path):
            if os.path.isdir(path) and not os.path.islink(path):
                shutil.rmtree(path)
            else:
                os.unlink(path)

    templates = os.path.join(HOME, "templates")
    if os.path.lexists(templates):
        if os.path.isdir(templates) and not os.path.islink(templates):
            shutil.rmtree(templates)
        else:
            os.unlink(templates)

    pipeline = os.path.join(HOME, "pipeline.py")
    makefile = os.path.join(HOME, "Makefile")
    if os.path.isfile(pipeline):
        command = ["python3", pipeline]
    elif os.path.isfile(makefile):
        command = ["make", "-C", HOME, "all"]
    else:
        pytest.fail("Neither /home/user/pipeline.py nor /home/user/Makefile exists")

    result = subprocess.run(command, cwd=HOME, capture_output=True, text=True, timeout=60)
    assert result.returncode == 0, (
        f"Pipeline orchestrator failed with status {result.returncode}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


@pytest.fixture(scope="session", autouse=True)
def executed_pipeline():
    run_orchestrator()


def test_pipeline_outputs_exist():
    assert os.path.isfile(os.path.join(HOME, "reshaped_long.csv")), "reshaped_long.csv is missing"
    assert os.path.isfile(os.path.join(HOME, "sanitized_long.csv")), "sanitized_long.csv is missing"
    assert os.path.isfile(os.path.join(HOME, "locales.db")), "locales.db is missing"

    templates_dir = os.path.join(HOME, "templates")
    assert os.path.isdir(templates_dir), "templates directory is missing"

    expected_locales = ["en_US", "fr_FR", "es_ES", "de_DE"]
    for loc in expected_locales:
        po_file = os.path.join(templates_dir, f"locale_{loc}.po")
        assert os.path.isfile(po_file), f"Template file missing: {po_file}"


def test_reshaped_and_sanitized_contents():
    expected_wide_to_long = expected_reshaped_rows()
    actual_reshaped = read_long(os.path.join(HOME, "reshaped_long.csv"))
    assert Counter(actual_reshaped) == Counter(expected_wide_to_long)
    assert len(actual_reshaped) == len(expected_wide_to_long)

    expected_clean = [row for row in expected_wide_to_long if not is_spam(row[3])]
    actual_clean = read_long(os.path.join(HOME, "sanitized_long.csv"))
    assert Counter(actual_clean) == Counter(expected_clean)
    assert len(actual_clean) == len(expected_clean)


def test_database_content():
    db_path = os.path.join(HOME, "locales.db")
    assert os.path.isfile(db_path)
    conn = sqlite3.connect(db_path)
    try:
        cursor = conn.cursor()
        cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='translations_ts'")
        assert cursor.fetchone() is not None, "Table translations_ts missing in locales.db"

        cursor.execute("SELECT COUNT(*) FROM translations_ts")
        count = cursor.fetchone()[0]
        assert count > 0, "translations_ts table is empty"

        cursor.execute("PRAGMA table_info(translations_ts)")
        columns = [row[1] for row in cursor.fetchall()]
        for column in COLUMNS:
            assert column in columns, f"Column {column} missing from translations_ts"

        cursor.execute("SELECT date, msg_id, locale, translation FROM translations_ts")
        actual = [tuple(str(value) for value in row) for row in cursor.fetchall()]
        expected = [row for row in expected_reshaped_rows() if not is_spam(row[3])]
        assert Counter(actual) == Counter(expected)
        assert len(actual) == len(expected)
    finally:
        conn.close()


def parse_po(path):
    with open(path, encoding="utf-8") as f:
        lines = [line.rstrip("\n") for line in f if line.strip()]
    assert len(lines) % 2 == 0, f"Malformed PO file: {path}"
    entries = []
    for index in range(0, len(lines), 2):
        msgid = re.fullmatch(r'msgid "(.*)"', lines[index])
        msgstr = re.fullmatch(r'msgstr "(.*)"', lines[index + 1])
        assert msgid is not None, f"Malformed msgid line in {path}: {lines[index]}"
        assert msgstr is not None, f"Malformed msgstr line in {path}: {lines[index + 1]}"
        entries.append((msgid.group(1), msgstr.group(1)))
    return entries


def test_latest_translation_templates():
    clean = [row for row in expected_reshaped_rows() if not is_spam(row[3])]
    latest = {}
    for date, msg_id, locale, translation in clean:
        key = (msg_id, locale)
        if key not in latest or date > latest[key][0]:
            latest[key] = (date, translation)

    expected_by_locale = {}
    for (msg_id, locale), (_, translation) in latest.items():
        expected_by_locale.setdefault(locale, []).append((msg_id, translation))

    templates_dir = os.path.join(HOME, "templates")
    expected_names = {f"locale_{locale}.po" for locale in expected_by_locale}
    actual_names = {name for name in os.listdir(templates_dir) if name.endswith(".po")}
    assert actual_names == expected_names

    for locale, expected_entries in expected_by_locale.items():
        actual_entries = parse_po(os.path.join(templates_dir, f"locale_{locale}.po"))
        assert Counter(actual_entries) == Counter(expected_entries)
        assert len(actual_entries) == len(expected_entries)


def wide_file_to_long(path):
    rows = []
    with open(path, newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            for locale in reader.fieldnames[2:]:
                rows.append((row["date"], row["msg_id"], locale, row[locale]))
    return rows


def invoke_sanitiser(rows, require_metric_for=()):
    sanitiser = os.path.join(HOME, "sanitiser.py")
    assert os.path.isfile(sanitiser), f"Sanitiser script missing: {sanitiser}"

    temp_dir = tempfile.mkdtemp(prefix="sanitiser-test-")
    input_path = os.path.join(temp_dir, "input.csv")
    output_path = os.path.join(temp_dir, "output.csv")
    log_path = os.path.join(temp_dir, "metric.log")
    backup = os.path.join(temp_dir, "eval_metric.real")

    try:
        with open(input_path, "w", newline="", encoding="utf-8") as f:
            writer = csv.writer(f)
            writer.writerow(COLUMNS)
            writer.writerows(rows)

        os.replace(METRIC, backup)
        wrapper = (
            "#!/bin/sh\n"
            f"printf '%s\\n' \"$1\" >> {shlex.quote(log_path)}\n"
            f"exec {shlex.quote(backup)} \"$1\"\n"
        )
        with open(METRIC, "w", encoding="utf-8") as f:
            f.write(wrapper)
        os.chmod(METRIC, 0o755)

        try:
            result = subprocess.run(
                ["python3", sanitiser, "--input", input_path, "--output", output_path],
                capture_output=True, text=True, timeout=30
            )
        finally:
            if os.path.lexists(METRIC):
                os.unlink(METRIC)
            os.replace(backup, METRIC)

        assert result.returncode == 0, (
            f"sanitiser.py crashed\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
        assert os.path.isfile(output_path), "sanitiser.py did not create its output"
        actual = read_long(output_path)
        expected = [row for row in rows if not is_spam(row[3])]
        assert Counter(actual) == Counter(expected)
        assert len(actual) == len(expected)

        logged = []
        if os.path.isfile(log_path):
            with open(log_path, encoding="utf-8") as f:
                logged = [line.rstrip("\n") for line in f]
        for translation in require_metric_for:
            assert translation in logged, "sanitiser.py did not query /app/bin/eval_metric for tested data"
    finally:
        if not os.path.exists(METRIC) and os.path.exists(backup):
            os.replace(backup, METRIC)
        shutil.rmtree(temp_dir, ignore_errors=True)


def test_adversarial_corpus_sanitiser():
    for corpus_dir in ["/app/corpus/evil", "/app/corpus/clean"]:
        for name in sorted(os.listdir(corpus_dir)):
            if name.endswith(".csv"):
                rows = wide_file_to_long(os.path.join(corpus_dir, name))
                invoke_sanitiser(rows)


def test_sanitiser_on_independent_long_format_corpus():
    nonce = secrets.token_hex(12)
    just_below = "A" * 49 + "a" * 51 + nonce.lower()
    just_above = "A" * 51 + "a" * 49 + nonce.upper()
    rows = [
        ("2041-01-01", "clean_" + nonce, "xx_XX", just_below),
        ("2041-01-02", "spam_" + nonce, "xx_XX", just_above),
        ("2041-01-03", "punct_" + nonce, "yy_YY", "1234 -- ..."),
        ("2041-01-04", "natural_" + nonce, "yy_YY", "Ordinary translated sentence " + nonce.lower()),
        ("2041-01-05", "loud_" + nonce, "zz_ZZ", "BUY NOW " + nonce.upper()),
    ]
    assert metric_score(just_below) < 0.5
    assert metric_score(just_above) > 0.5
    invoke_sanitiser(rows, require_metric_for=(just_below, just_above))
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
