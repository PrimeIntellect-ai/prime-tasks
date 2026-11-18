#!/bin/bash
set +e
mkdir -p /logs/verifier

run_checks() {
    # Require the requested source artifact and Go module.
    [ -f /home/user/process_loc.go ] && [ ! -L /home/user/process_loc.go ] && [ -s /home/user/process_loc.go ] || return 1
    [ -f /home/user/go.mod ] && [ ! -L /home/user/go.mod ] && [ -s /home/user/go.mod ] || return 1
    python3 - <<'PY' || return 1
import re
text = open('/home/user/go.mod', encoding='utf-8').read()
assert re.search(r'(?m)^\s*module\s+loc\s*$', text), 'go.mod must declare module loc'
PY

    # Preserve all checks against the original fixture and its produced artifacts.
    cat > /tmp/test_final_state.py <<'PY'
import os
import sqlite3
import math

def test_invalid_strings_log():
    log_path = "/home/user/invalid_strings.log"
    assert os.path.exists(log_path), f"Log file {log_path} does not exist."

    expected_lines = [
        "1620000015,fr,invalid-key,Hello,Bonjour",
        "1620000020,de,welcome_msg,Welcome {user}!,Willkommen {name}!",
        "1620000030,BAD,test,test,test"
    ]

    with open(log_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert lines == expected_lines, f"Contents of {log_path} do not match the expected invalid rows."

def test_translations_db():
    db_path = "/home/user/translations.db"
    assert os.path.exists(db_path), f"Database file {db_path} does not exist."

    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='translations';")
    assert cursor.fetchone() is not None, "Table 'translations' does not exist in the database."

    cursor.execute("SELECT lang_code, translation_key, original_text, translated_text, rolling_avg_ratio FROM translations ORDER BY lang_code DESC, translation_key DESC;")
    rows = cursor.fetchall()

    expected_rows = {
        ("fr", "welcome_msg"): ("Welcome {user}!", "Bienvenue cher {user}!", 1.28333333333333),
        ("fr", "goodbye"): ("Goodbye!", "Au revoir!", 1.19166666666666),
        ("es-ES", "welcome_msg"): ("Welcome {user}!", "Bienvenido {user}!", 1.2)
    }

    assert len(rows) == len(expected_rows), f"Expected {len(expected_rows)} rows in translations table, found {len(rows)}."
    for row in rows:
        lang_code, translation_key, original_text, translated_text, rolling_avg_ratio = row
        key = (lang_code, translation_key)
        assert key in expected_rows, f"Unexpected row found for {key}."
        expected_orig, expected_trans, expected_ratio = expected_rows[key]
        assert original_text == expected_orig, f"Expected original_text '{expected_orig}' for {key}, got '{original_text}'."
        assert translated_text == expected_trans, f"Expected translated_text '{expected_trans}' for {key}, got '{translated_text}'."
        assert math.isclose(rolling_avg_ratio, expected_ratio, rel_tol=1e-5), f"Expected rolling_avg_ratio ~{expected_ratio} for {key}, got {rolling_avg_ratio}."
    conn.close()
PY
    python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short || return 1

    # Generate a fresh, unpredictable fixture and independently derive its answers.
    python3 - <<'PY' || return 1
import csv
import io
import json
import secrets

suffix = secrets.token_hex(5)
base = 1700000000 + secrets.randbelow(50000000)
ph = "p" + suffix
key_update = "update_" + suffix
key_other = "other_" + suffix
key_es = "spanish_" + suffix

rows = [
    [str(base + 50), "fr", key_update, f"Hello {{{ph}}}!", f"Nouvelle version {{{ph}}}!"],
    [str(base + 40), "fr", "bad-key-" + suffix, "Invalid, key", "Cle, invalide"],
    [str(base + 20), "es-ES", key_es, f"Welcome {{{ph}}}", f"Bienvenido {{{ph}}}"],
    [str(base + 10), "fr", key_update, f"Hello {{{ph}}}!", f"Salut {{{ph}}}!"],
    [str(base + 70), "BAD", "lang_" + suffix, "Plain", "Texte"],
    [str(base + 30), "fr", key_other, "Goodbye!", "Au revoir!"],
    [str(base + 60), "de", "place_" + suffix, f"Hi {{{ph}}}", "Hallo {wrong}"],
    [str(base + 80), "en", "final_" + suffix, "Final", "Final"],
]

header = ["timestamp", "lang_code", "translation_key", "original_text", "translated_text"]
with open('/home/user/raw_translations.csv', 'w', newline='', encoding='utf-8') as f:
    writer = csv.writer(f, lineterminator='\n')
    writer.writerow(header)
    writer.writerows(rows)

def raw_line(row):
    out = io.StringIO(newline='')
    csv.writer(out, lineterminator='\n').writerow(row)
    return out.getvalue()

valid = [rows[3], rows[2], rows[5], rows[0], rows[7]]
sums = {}
counts = {}
latest = {}
for row in sorted(valid, key=lambda r: int(r[0])):
    ts, lang, key, original, translated = row
    ratio = len(translated) / len(original)
    sums[lang] = sums.get(lang, 0.0) + ratio
    counts[lang] = counts.get(lang, 0) + 1
    latest[(lang, key)] = [original, translated, sums[lang] / counts[lang], int(ts)]

expected = {
    "invalid": raw_line(rows[1]) + raw_line(rows[4]) + raw_line(rows[6]),
    "rows": [
        [lang, key, value[0], value[1], value[2]]
        for (lang, key), value in sorted(latest.items())
    ]
}
with open('/tmp/dynamic_expected.json', 'w', encoding='utf-8') as f:
    json.dump(expected, f)
PY

    rm -f /home/user/invalid_strings.log /home/user/translations.db /tmp/process_loc_submission

    # Compile and execute the submitted program against the fresh fixture.
    (cd /home/user && timeout 120s go build -o /tmp/process_loc_submission ./process_loc.go) || return 1
    [ -x /tmp/process_loc_submission ] || return 1
    (cd /home/user && timeout 30s /tmp/process_loc_submission) || return 1

    python3 - <<'PY' || return 1
import json
import math
import os
import sqlite3

with open('/tmp/dynamic_expected.json', encoding='utf-8') as f:
    expected = json.load(f)

log_path = '/home/user/invalid_strings.log'
db_path = '/home/user/translations.db'
assert os.path.isfile(log_path) and not os.path.islink(log_path)
assert os.path.isfile(db_path) and not os.path.islink(db_path)
with open(log_path, 'r', encoding='utf-8', newline='') as f:
    actual_log = f.read()
assert actual_log == expected['invalid'], 'invalid_strings.log did not preserve the exact raw invalid CSV lines'

conn = sqlite3.connect(db_path)
cur = conn.cursor()
cur.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='translations'")
assert cur.fetchone() is not None
cur.execute("PRAGMA table_info(translations)")
schema = cur.fetchall()
assert [(r[1], r[2].upper(), r[5]) for r in schema] == [
    ('lang_code', 'TEXT', 1),
    ('translation_key', 'TEXT', 2),
    ('original_text', 'TEXT', 0),
    ('translated_text', 'TEXT', 0),
    ('rolling_avg_ratio', 'REAL', 0),
], f'unexpected translations schema: {schema}'

cur.execute("SELECT lang_code, translation_key, original_text, translated_text, rolling_avg_ratio FROM translations ORDER BY lang_code, translation_key")
actual = cur.fetchall()
assert len(actual) == len(expected['rows'])
for got, want in zip(actual, expected['rows']):
    assert tuple(got[:4]) == tuple(want[:4]), (got, want)
    assert math.isclose(got[4], want[4], rel_tol=1e-9, abs_tol=1e-12), (got, want)
conn.close()
PY
}

if run_checks; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
