#!/bin/bash
set +e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import pytest

BASE_DIR = "/home/user/legacy_docs"
LOG_FILE = "/home/user/migration_log.csv"

FILES = [
    {
        "original_path": "drafts/overview.txt",
        "expected_name": "2020-05-12_overview.txt",
        "expected_utf8": "L’histoire de la bête",
    },
    {
        "original_path": "published/v1/api_specs.txt",
        "expected_name": "2018-11-23_api_specs.txt",
        "expected_utf8": "Méthodes et propriétés",
    },
    {
        "original_path": "readme.txt",
        "expected_name": "2023-01-02_readme.txt",
        "expected_utf8": "Copyright © 2023",
    }
]

def test_original_files_removed():
    for f in FILES:
        old_path = os.path.join(BASE_DIR, f["original_path"])
        assert not os.path.exists(old_path), f"Original file {old_path} should have been renamed/removed."

def test_new_files_exist_and_utf8_content():
    for f in FILES:
        dir_name = os.path.dirname(f["original_path"])
        new_path = os.path.join(BASE_DIR, dir_name, f["expected_name"])

        assert os.path.exists(new_path), f"Expected renamed file does not exist: {new_path}"

        with open(new_path, "rb") as file_obj:
            content_bytes = file_obj.read()

        try:
            content_str = content_bytes.decode("utf-8")
        except UnicodeDecodeError:
            pytest.fail(f"File {new_path} is not valid UTF-8.")

        assert content_str == f["expected_utf8"], f"Content of {new_path} does not match expected UTF-8 text."

def test_migration_log_csv():
    assert os.path.exists(LOG_FILE), f"Migration log {LOG_FILE} is missing."

    with open(LOG_FILE, "r", encoding="utf-8") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = []
    for f in FILES:
        old_path = os.path.join(BASE_DIR, f["original_path"])
        dir_name = os.path.dirname(f["original_path"])
        new_path = os.path.join(BASE_DIR, dir_name, f["expected_name"])
        expected_lines.append(f"{old_path},{new_path}")

    assert len(lines) == len(expected_lines), f"Expected {len(expected_lines)} lines in log file, but found {len(lines)}."

    for expected_line in expected_lines:
        assert expected_line in lines, f"Expected line '{expected_line}' not found in {LOG_FILE}."
TEST_EOF

ok=1
python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1 || ok=0

if [ "$ok" -eq 1 ]; then
    python3 - <<'PY' || ok=0
import os
import re

project = "/home/user/doc_processor"
cargo_toml = os.path.join(project, "Cargo.toml")
assert os.path.isdir(project), "The required Cargo project is missing"
assert os.path.isfile(cargo_toml), "Cargo.toml is missing"

rust_files = []
for root, dirs, files in os.walk(project):
    dirs[:] = [d for d in dirs if d != "target"]
    for name in files:
        if name.endswith(".rs"):
            rust_files.append(os.path.join(root, name))
assert rust_files, "The Cargo project contains no Rust source files"

source = "\n".join(open(path, encoding="utf-8").read() for path in rust_files)
assert not re.search(r"\bread_to_(?:end|string)\s*\(", source), \
    "The implementation uses a whole-file read instead of streaming/buffered I/O"
assert not re.search(r"\b(?:std::)?fs::read(?:_to_string)?\s*\(", source), \
    "The implementation uses a whole-file filesystem read"
assert re.search(r"BufReader|BufWriter|Mmap|mmap|\.read\s*\(|read_exact\s*\(", source), \
    "No buffered, mapped, or streaming I/O implementation was found"
PY
fi

if [ "$ok" -eq 1 ]; then
    backup_dir=$(mktemp -d /tmp/doc_processor_verify.XXXXXX)
    had_log=0

    if ! mv /home/user/legacy_docs "$backup_dir/legacy_docs"; then
        ok=0
    fi
    if [ -e /home/user/migration_log.csv ]; then
        if mv /home/user/migration_log.csv "$backup_dir/migration_log.csv"; then
            had_log=1
        else
            ok=0
        fi
    fi

    cleanup_dynamic() {
        rm -rf /home/user/legacy_docs
        rm -f /home/user/migration_log.csv
        if [ -e "$backup_dir/legacy_docs" ]; then
            mv "$backup_dir/legacy_docs" /home/user/legacy_docs
        fi
        if [ "$had_log" -eq 1 ] && [ -e "$backup_dir/migration_log.csv" ]; then
            mv "$backup_dir/migration_log.csv" /home/user/migration_log.csv
        fi
        rm -rf "$backup_dir"
    }
    trap cleanup_dynamic EXIT

    if [ "$ok" -eq 1 ]; then
        python3 - <<'PY' || ok=0
import datetime
import json
import os
import secrets

base = "/home/user/legacy_docs"
token = secrets.token_hex(6)
fixtures = [
    (f"level_{token}/alpha_{token}.txt", bytes([0x93]) + b"Quoted" + bytes([0x94, 0x20, 0x97, 0x20, 0x80]), 946782245),
    (f"level_{token}/deeper_{token}/beta_{token}.txt", b"Cr\xe8me br\xfbl\xe9e\r\nDeuxi\xe8me ligne", 1273914123),
    (f"root_{token}.txt", b"Espa\xf1a, Fran\xe7ais and \xa9", 1698827696),
]
expected = []
for relative, raw, timestamp in fixtures:
    old_path = os.path.join(base, relative)
    os.makedirs(os.path.dirname(old_path), exist_ok=True)
    with open(old_path, "wb") as f:
        f.write(raw)
    os.utime(old_path, (timestamp, timestamp))
    date = datetime.datetime.fromtimestamp(timestamp, datetime.timezone.utc).strftime("%Y-%m-%d")
    new_path = os.path.join(os.path.dirname(old_path), date + "_" + os.path.basename(old_path))
    expected.append({
        "old": old_path,
        "new": new_path,
        "text": raw.decode("cp1252"),
    })

untouched = os.path.join(base, f"level_{token}", f"ignore_{token}.bin")
raw_untouched = b"\x92\xff\x00not-a-text-file"
with open(untouched, "wb") as f:
    f.write(raw_untouched)

with open("/tmp/doc_processor_dynamic_expected.json", "w", encoding="utf-8") as f:
    json.dump({"files": expected, "untouched": untouched, "untouched_bytes": list(raw_untouched)}, f)
PY
    fi

    if [ "$ok" -eq 1 ]; then
        (cd /home/user/doc_processor && timeout 240s cargo run --offline --quiet) || ok=0
    fi

    if [ "$ok" -eq 1 ]; then
        python3 - <<'PY' || ok=0
import json
import os

with open("/tmp/doc_processor_dynamic_expected.json", encoding="utf-8") as f:
    spec = json.load(f)

expected_lines = set()
for item in spec["files"]:
    assert not os.path.exists(item["old"]), f"Original dynamic input was not renamed: {item['old']}"
    assert os.path.isfile(item["new"]), f"Expected dynamically named output is missing: {item['new']}"
    with open(item["new"], "rb") as f:
        result = f.read()
    assert result.decode("utf-8") == item["text"], f"Incorrect Windows-1252 conversion for {item['new']}"
    expected_lines.add(item["old"] + "," + item["new"])

with open(spec["untouched"], "rb") as f:
    assert f.read() == bytes(spec["untouched_bytes"]), "A non-.txt file was modified"

log_path = "/home/user/migration_log.csv"
assert os.path.isfile(log_path), "The executed utility did not create migration_log.csv"
with open(log_path, "r", encoding="utf-8") as f:
    lines = [line.rstrip("\r\n") for line in f]
assert all(lines), "The migration log contains blank lines"
assert set(lines) == expected_lines, "The migration log does not exactly describe all dynamic inputs"
assert len(lines) == len(expected_lines), "The migration log contains duplicate or extra entries"
PY
    fi

    cleanup_dynamic
    trap - EXIT
fi

if [ "$ok" -eq 1 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
