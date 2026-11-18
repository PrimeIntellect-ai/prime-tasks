#!/bin/bash
set +e
mkdir -p /logs/verifier

verify() {
    WORK=/home/user/loc_pipeline
    INPUT="$WORK/raw_translations.csv"
    OUTPUT="$WORK/normalized_translations.jsonl"

    [ -d "$WORK" ] || { echo "Workspace missing" >&2; return 1; }

    # Require an actual Go implementation that imports and uses NFC from the
    # package named in the instruction.
    find "$WORK" -type f -name '*.go' -print -quit | grep -q . || {
        echo "No Go source file found" >&2
        return 1
    }
    grep -R --include='*.go' -q '"golang.org/x/text/unicode/norm"' "$WORK" || {
        echo "Go source does not import golang.org/x/text/unicode/norm" >&2
        return 1
    }
    grep -R --include='*.go' -q 'NFC' "$WORK" || {
        echo "Go source does not use NFC" >&2
        return 1
    }

    cd "$WORK" || return 1
    PACKAGE_LIST=$(go list -f '{{if eq .Name "main"}}{{.Dir}}{{end}}' ./... 2>&1) || {
        echo "$PACKAGE_LIST" >&2
        return 1
    }
    mapfile -t MAIN_DIRS < <(printf '%s\n' "$PACKAGE_LIST" | sed '/^[[:space:]]*$/d')
    [ "${#MAIN_DIRS[@]}" -gt 0 ] || {
        echo "No Go main package found" >&2
        return 1
    }

    MAIN_DIR=""
    for d in "${MAIN_DIRS[@]}"; do
        if [ "$d" = "$WORK" ]; then
            MAIN_DIR="$d"
            break
        fi
    done
    if [ -z "$MAIN_DIR" ]; then
        [ "${#MAIN_DIRS[@]}" -eq 1 ] || {
            echo "Multiple Go main packages found and none is at workspace root" >&2
            return 1
        }
        MAIN_DIR="${MAIN_DIRS[0]}"
    fi

    DEPS=$(cd "$MAIN_DIR" && go list -deps . 2>&1) || {
        echo "$DEPS" >&2
        return 1
    }
    printf '%s\n' "$DEPS" | grep -Fxq 'golang.org/x/text/unicode/norm' || {
        echo "Built program does not depend on golang.org/x/text/unicode/norm" >&2
        return 1
    }

    REL=$(realpath --relative-to="$WORK" "$MAIN_DIR") || return 1
    if [ "$REL" = "." ]; then
        TARGET="."
    else
        TARGET="./$REL"
    fi

    # The audited emoji row had eight fields. Use the intended seven-column
    # fixture so the Japanese value is actually in the ja column.
    cat > "$INPUT" <<'CSV_EOF'
timestamp,string_key,en,es,fr,ja,ar
2023-10-01T09:00:00Z,btn_submit,Submit,Enviar,,,
2023-10-01T10:00:00Z,btn_submit,,,,,إرسال
2023-10-01T08:00:00Z,btn_cancel,Cancel,Cancelar,Annuler,,
2023-10-01T09:30:00Z,btn_cancel,,,Annuler (updated),キャンセル,
2023-10-01T08:00:00Z,msg_welcome,,Bienvenido,,,
2023-10-01T09:00:00Z,msg_welcome,,,,ようこそ,
2023-10-01T11:00:00Z,lbl_user,User,,Utilisateur,,مستخدم
2023-10-01T10:00:00Z,lbl_user,User,Usuario,,,
2023-10-01T12:00:00Z,emoji_test,Hello 😊,,,,
2023-10-01T12:05:00Z,emoji_test,,,Bonjour,こんにちは 😊,
CSV_EOF

    rm -f "$OUTPUT"
    timeout 120s go run "$TARGET" || return 1

    # Preserve the original verifier's assertions against the corrected fixture.
    python3 - <<'PY' || return 1
import json
import os
import unicodedata

OUTPUT_FILE = "/home/user/loc_pipeline/normalized_translations.jsonl"
assert os.path.isfile(OUTPUT_FILE), f"Expected output file {OUTPUT_FILE} does not exist."

records = []
with open(OUTPUT_FILE, "r", encoding="utf-8") as f:
    for line_num, line in enumerate(f, 1):
        line = line.strip()
        if not line:
            continue
        try:
            records.append(json.loads(line))
        except json.JSONDecodeError:
            raise AssertionError(f"Line {line_num} is not valid JSON: {line}")

for rec in records:
    assert isinstance(rec, dict), f"Record is not an object: {rec}"
    assert set(rec.keys()) == {"key", "locale", "translation"}, f"Record has incorrect keys: {rec}"
    for v in rec.values():
        if isinstance(v, str):
            assert v == unicodedata.normalize("NFC", v), f"String {v!r} is not NFC normalized."

data_map = {}
for rec in records:
    k = rec["key"]
    loc = rec["locale"]
    if k not in data_map:
        data_map[k] = {}
    data_map[k][loc] = rec["translation"]

assert "msg_welcome" not in data_map, "Key 'msg_welcome' should have been dropped because 'en' is empty."
assert "btn_cancel" in data_map, "Missing 'btn_cancel' key."
assert data_map["btn_cancel"].get("fr") == "Annuler (updated)", "FR translation for 'btn_cancel' did not update correctly."
assert "lbl_user" in data_map, "Missing 'lbl_user' key."
lbl_user_locales = set(data_map["lbl_user"].keys())
assert lbl_user_locales == {"en", "es", "fr", "ar"}, f"Expected locales for 'lbl_user', got {lbl_user_locales}"

expected_data = {
    "btn_submit": {"en": "Submit", "es": "Enviar", "ar": "إرسال"},
    "btn_cancel": {"en": "Cancel", "es": "Cancelar", "fr": "Annuler (updated)", "ja": "キャンセル"},
    "lbl_user": {"en": "User", "es": "Usuario", "fr": "Utilisateur", "ar": "مستخدم"},
    "emoji_test": {"en": "Hello 😊", "fr": "Bonjour", "ja": "こんにちは 😊"},
}
for k in expected_data:
    for loc in expected_data[k]:
        expected_data[k][loc] = unicodedata.normalize("NFC", expected_data[k][loc])
assert data_map == expected_data, "The final merged and reshaped data does not match the expected state."
PY

    # Generate a fresh valid fixture. Its randomized values and expected result
    # are derived at verification time, preventing a precomputed JSONL artifact
    # from satisfying the task.
    python3 - <<'PY' || return 1
import csv
import json
import secrets
import unicodedata
from collections import defaultdict
from datetime import datetime

path = "/home/user/loc_pipeline/raw_translations.csv"
token = secrets.token_hex(10)
key1 = "cafe\u0301_" + token
key2 = "quoted_" + token
invalid = "invalid_" + token
rows = [
    ["2024-02-01T11:00:00Z", key1, "Newest " + token, "", "Français, révisé", "こんにちは 😊", ""],
    ["2024-02-01T09:00:00Z", key1, "Old " + token, "Viejo", "Ancien", "", "قديم"],
    ["2024-02-01T12:00:00Z", key1, "", "Nuevo " + token, "", "", "مرحبا " + token],
    ["2024-02-01T10:00:00Z", key1, "Middle", "", "Cafe\u0301", "", ""],
    ["2024-02-01T08:00:00Z", invalid, "", "solo español", "", "", ""],
    ["2024-02-02T08:00:00Z", key2, 'English "quoted", ' + token, "", "", "絵文字 🚀", ""],
    ["2024-02-02T09:00:00Z", key2, "", "Español", "", "", "العربية"],
]
secrets.SystemRandom().shuffle(rows)
with open(path, "w", encoding="utf-8", newline="") as f:
    w = csv.writer(f)
    w.writerow(["timestamp", "string_key", "en", "es", "fr", "ja", "ar"])
    w.writerows(rows)

locales = ["en", "es", "fr", "ja", "ar"]
groups = defaultdict(list)
for row in rows:
    groups[row[1]].append(row)
expected = []
for key, group in groups.items():
    merged = {loc: "" for loc in locales}
    for row in sorted(group, key=lambda r: datetime.fromisoformat(r[0].replace("Z", "+00:00"))):
        for i, loc in enumerate(locales, 2):
            if row[i] != "":
                merged[loc] = row[i]
    if merged["en"] == "":
        continue
    nkey = unicodedata.normalize("NFC", key)
    for loc in locales:
        if merged[loc] != "":
            expected.append({
                "key": nkey,
                "locale": loc,
                "translation": unicodedata.normalize("NFC", merged[loc]),
            })
with open("/tmp/loc_expected.json", "w", encoding="utf-8") as f:
    json.dump(expected, f, ensure_ascii=False)
PY

    rm -f "$OUTPUT"
    timeout 120s go run "$TARGET" || return 1

    python3 - <<'PY' || return 1
import json
import os
import unicodedata
from collections import Counter

output = "/home/user/loc_pipeline/normalized_translations.jsonl"
assert os.path.isfile(output), "Program did not create normalized_translations.jsonl"
with open("/tmp/loc_expected.json", encoding="utf-8") as f:
    expected = json.load(f)

actual = []
with open(output, encoding="utf-8") as f:
    for number, line in enumerate(f, 1):
        if not line.strip():
            continue
        try:
            rec = json.loads(line)
        except json.JSONDecodeError as e:
            raise AssertionError(f"Output line {number} is not valid JSON: {e}")
        assert isinstance(rec, dict), f"Line {number} is not a JSON object"
        assert set(rec) == {"key", "locale", "translation"}, f"Incorrect keys on line {number}: {set(rec)}"
        assert all(isinstance(rec[k], str) for k in rec), f"All values must be strings: {rec}"
        assert rec["locale"] in {"en", "es", "fr", "ja", "ar"}, f"Invalid locale: {rec}"
        assert rec["translation"] != "", f"Empty translations must not be emitted: {rec}"
        for value in rec.values():
            assert value == unicodedata.normalize("NFC", value), f"Value is not NFC: {value!r}"
        actual.append(rec)

def packed(records):
    return Counter((r["key"], r["locale"], r["translation"]) for r in records)

assert packed(actual) == packed(expected), f"Output mismatch. Expected {expected!r}, got {actual!r}"
assert len(actual) == len(expected), "Output contains duplicate or extra records"
PY
}

if verify; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
