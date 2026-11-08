#!/bin/bash
mkdir -p /logs/verifier

if (
    set -euo pipefail

    rm -f /home/user/output/clean_translations.csv
    timeout 180s su -s /bin/bash user -c 'cd /home/user && bash /home/user/run.sh'

    cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import re
import unicodedata
import pytest

OUTPUT_CSV = "/home/user/output/clean_translations.csv"
RUN_SCRIPT = "/home/user/run.sh"
GO_CODE = "/home/user/loc_pipeline/process.go"

def test_files_exist():
    assert os.path.isfile(RUN_SCRIPT), f"Run script missing at {RUN_SCRIPT}"
    assert os.path.isfile(GO_CODE), f"Go source missing at {GO_CODE}"
    assert os.path.isfile(OUTPUT_CSV), f"Output file missing at {OUTPUT_CSV}"

def test_output_csv_content():
    if not os.path.isfile(OUTPUT_CSV):
        pytest.fail(f"Cannot check content, {OUTPUT_CSV} is missing.")

    with open(OUTPUT_CSV, "r", encoding="utf-8", newline='') as f:
        reader = csv.reader(f)
        rows = list(reader)

    assert len(rows) == 5, f"Expected 5 rows in the output CSV, but got {len(rows)}. Deduplication or processing might be incorrect."

    # Header
    assert rows[0] == ["EntryID", "Context", "SourceText", "Translation"], "Header row is incorrect or missing."

    # Row 1: Standard row
    assert rows[1] == ["1", "ui.button", "Save", "Enregistrer"], "First data row is incorrect."

    # Row 2: Embedded \r\n converted to \n
    assert rows[2] == ["2", "ui.alert", "Error occurred.\nPlease retry.", "Erreur.\nRéessayer."], "Embedded carriage returns were not correctly converted to standard newlines."

    # Row 3: Invalid UTF-8 replaced with U+FFFD
    assert rows[3][0] == "4"
    assert rows[3][1] == "ui.msg"
    assert "\ufffd" in rows[3][2], "Invalid UTF-8 byte sequence was not replaced with the Unicode Replacement Character (U+FFFD)."
    assert rows[3][3] == "Mauvais encodage"

    # Row 4: Unnormalized Unicode converted to NFC
    nfc_cafe = unicodedata.normalize('NFC', "Cafe\u0301")
    assert rows[4] == ["5", "ui.cafe", nfc_cafe, "Cafeteria"], "Unicode text was not correctly normalized to NFC."

def test_required_go_implementation_is_present():
    with open(GO_CODE, "r", encoding="utf-8") as f:
        source = f.read()
    with open(RUN_SCRIPT, "r", encoding="utf-8") as f:
        run_source = f.read()

    assert re.search(r'["`]encoding/csv["`]', source), "process.go must use Go's encoding/csv package."
    assert re.search(r'["`]crypto/sha256["`]', source), "process.go must use SHA-256 for deduplication."
    assert re.search(r'["`]golang.org/x/text/unicode/norm["`]', source), "process.go must use Unicode normalization support."
    assert re.search(r'\.Read\s*\(', source), "CSV records must be read incrementally."
    assert re.search(r'\.Write\s*\(', source), "CSV records must be written incrementally."
    assert not re.search(r'\bReadAll\s*\(', source), "The processor must not load the whole CSV with ReadAll."
    assert re.search(r'\bgo\s+build\b', run_source), "run.sh must build the Go program."
TEST_EOF

    python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short

    BIN="/tmp/loc_processor_$$_$RANDOM"
    trap 'rm -f "$BIN" /tmp/loc_expected.json /tmp/make_challenge.py /tmp/check_challenge.py' EXIT

    # Build process.go independently so the behavioral challenge necessarily
    # exercises the requested Go artifact rather than trusting run.sh.
    timeout 180s su -s /bin/bash user -c "cd /home/user/loc_pipeline && go build -o '$BIN' ./process.go"
    test -x "$BIN"

    cat << 'PY_EOF' > /tmp/make_challenge.py
import csv
import io
import json
import secrets
import unicodedata

path = "/home/user/input/raw_translations.csv"
token = secrets.token_hex(12)
context_decomposed = "dynamic-" + token + "-Cafe\u0301"
context_nfc = unicodedata.normalize("NFC", context_decomposed)
source_crlf = "First line " + token + "\r\nSecond line"
source_lf = source_crlf.replace("\r\n", "\n")
invalid_source_marker = "Bad INVALID_MARK byte " + token
invalid_source_clean = "Bad \ufffd byte " + token

rows = [
    ["EntryID", "Context", "SourceText", "Translation"],
    ["A\u030A", context_decomposed, source_crlf, "first INVALID_MARK e\u0301\r\nnext"],
    ["drop-me", context_nfc, source_lf, "later duplicate"],
    ["3", "invalid-" + token, invalid_source_marker, "Mauvais INVALID_MARK"],
    ["drop-too", "invalid-" + token, invalid_source_clean, "duplicate after cleaning"],
    ["5", "quotes," + token, 'He said "hello"', "Cafe\u0301, final"],
]

buf = io.StringIO(newline="")
writer = csv.writer(buf, lineterminator="\n")
writer.writerows(rows)
data = buf.getvalue().encode("utf-8").replace(b"INVALID_MARK", b"\xff")
with open(path, "wb") as f:
    f.write(data)

expected = [
    ["EntryID", "Context", "SourceText", "Translation"],
    ["Å", context_nfc, source_lf, "first \ufffd é\nnext"],
    ["3", "invalid-" + token, invalid_source_clean, "Mauvais \ufffd"],
    ["5", "quotes," + token, 'He said "hello"', "Café, final"],
]
with open("/tmp/loc_expected.json", "w", encoding="utf-8") as f:
    json.dump(expected, f, ensure_ascii=False)
PY_EOF

    python3 /tmp/make_challenge.py
    rm -f /home/user/output/clean_translations.csv
    timeout 120s su -s /bin/bash user -c "'$BIN'"

    cat << 'PY_EOF' > /tmp/check_challenge.py
import csv
import json
import os
import unicodedata

output = "/home/user/output/clean_translations.csv"
assert os.path.isfile(output), "The compiled Go processor did not create the output CSV"
with open("/tmp/loc_expected.json", "r", encoding="utf-8") as f:
    expected = json.load(f)
with open(output, "r", encoding="utf-8", newline="") as f:
    actual = list(csv.reader(f))

assert actual == expected, f"Compiled processor failed generated-input test. Expected {expected!r}, got {actual!r}"
assert all(len(row) == 4 for row in actual), "Every output record must contain four fields"
assert all("\r" not in field for row in actual for field in row), "Carriage returns were not normalized"
assert all(unicodedata.is_normalized("NFC", field) for row in actual for field in row), "All output fields must be NFC-normalized"
PY_EOF

    python3 /tmp/check_challenge.py
); then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
