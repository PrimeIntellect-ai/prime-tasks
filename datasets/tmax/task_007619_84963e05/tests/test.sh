#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import sqlite3
import csv
import json
import secrets
import subprocess

PROJECT_DIR = "/home/user/log_processor"
JSON_PATH = "/home/user/logs.json"
CSV_PATH = "/home/user/processed_logs.csv"
DB_PATH = "/home/user/analysis.db"


def cargo_env():
    env = os.environ.copy()
    env["HOME"] = "/home/user"
    env["RUSTUP_HOME"] = "/opt/rust"
    env.pop("CARGO_HOME", None)
    return env


def find_rust_binary():
    manifest = os.path.join(PROJECT_DIR, "Cargo.toml")
    subprocess.run(
        ["cargo", "build", "--manifest-path", manifest],
        cwd=PROJECT_DIR,
        env=cargo_env(),
        check=True,
        timeout=180,
    )
    result = subprocess.run(
        ["cargo", "metadata", "--no-deps", "--format-version", "1", "--manifest-path", manifest],
        cwd=PROJECT_DIR,
        env=cargo_env(),
        check=True,
        capture_output=True,
        text=True,
        timeout=60,
    )
    metadata = json.loads(result.stdout)
    manifest_real = os.path.realpath(manifest)
    packages = [p for p in metadata["packages"] if os.path.realpath(p["manifest_path"]) == manifest_real]
    assert len(packages) == 1, "Could not identify the submitted Cargo package."
    package = packages[0]
    bins = [t for t in package["targets"] if "bin" in t.get("kind", [])]
    assert bins, "The Cargo project has no Rust binary target."

    default_run = package.get("default_run")
    if default_run:
        matches = [t for t in bins if t["name"] == default_run]
        assert len(matches) == 1, "Cargo default-run does not identify a binary target."
        target = matches[0]
    elif len(bins) == 1:
        target = bins[0]
    else:
        matches = [t for t in bins if t["name"] == package["name"]]
        assert len(matches) == 1, "Multiple binary targets exist without an identifiable default."
        target = matches[0]

    binary = os.path.join(metadata["target_directory"], "debug", target["name"])
    assert os.path.isfile(binary), f"Compiled Rust binary is missing: {binary}"
    assert os.access(binary, os.X_OK), f"Compiled Rust binary is not executable: {binary}"
    with open(binary, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Cargo output is not an ELF executable."
    return binary


def run_binary(binary):
    subprocess.run(
        [binary],
        cwd=PROJECT_DIR,
        env=cargo_env(),
        check=True,
        timeout=60,
    )


def read_csv():
    with open(CSV_PATH, "r", encoding="utf-8", newline="") as f:
        return list(csv.reader(f))


def expected_rows(data):
    return [[str(item["ts"]), str(item["code"]), item["msg"].lower()] for item in data]


def test_rust_program_actually_generates_csv():
    """Compile the Cargo binary and exercise it on verifier-generated input."""
    binary = find_rust_binary()
    original_json = open(JSON_PATH, "rb").read()
    original_csv = open(CSV_PATH, "rb").read() if os.path.isfile(CSV_PATH) else None
    nonce = secrets.token_hex(12)
    dynamic_data = [
        {"ts": 1900000000 + secrets.randbelow(100000), "code": 418, "msg": f"MiXeD, \"CSV\" {nonce}", "host": "untrusted-a"},
        {"ts": 1800000000 + secrets.randbelow(100000), "code": 599, "msg": "РусСКИЙ ТеКСТ", "host": "untrusted-b"},
        {"ts": 1700000000 + secrets.randbelow(100000), "code": 451, "msg": "日本語 ABC", "host": "untrusted-c"},
    ]

    try:
        with open(JSON_PATH, "w", encoding="utf-8") as f:
            json.dump(dynamic_data, f, ensure_ascii=False)
        if os.path.exists(CSV_PATH):
            os.unlink(CSV_PATH)

        run_binary(binary)
        assert os.path.isfile(CSV_PATH), "Running the compiled Rust binary did not create processed_logs.csv."
        rows = read_csv()
        assert rows[0] == ["timestamp", "error_code", "message"], f"Incorrect CSV headers: {rows[0]}"
        assert rows[1:] == expected_rows(dynamic_data), "Rust binary failed on verifier-generated input."
    finally:
        with open(JSON_PATH, "wb") as f:
            f.write(original_json)

    # Recreate the required final CSV from the original input using the same binary.
    try:
        if os.path.exists(CSV_PATH):
            os.unlink(CSV_PATH)
        run_binary(binary)
        assert os.path.isfile(CSV_PATH), "Rust binary did not recreate the final CSV."
    except Exception:
        if original_csv is not None:
            with open(CSV_PATH, "wb") as f:
                f.write(original_csv)
        raise


def test_rust_project_exists():
    """Verify the Rust project directory and Cargo.toml exist."""
    project_dir = PROJECT_DIR
    assert os.path.isdir(project_dir), f"Rust project directory {project_dir} does not exist."
    cargo_toml = os.path.join(project_dir, "Cargo.toml")
    assert os.path.isfile(cargo_toml), f"Cargo.toml missing in {project_dir}."


def test_processed_csv_content():
    """Verify the processed CSV file exists and contains the correctly transformed data."""
    csv_path = CSV_PATH
    assert os.path.isfile(csv_path), f"Processed CSV file {csv_path} is missing."

    with open(csv_path, 'r', encoding='utf-8') as f:
        reader = csv.reader(f)
        rows = list(reader)

    assert len(rows) > 0, "CSV file is empty."
    headers = rows[0]
    assert headers == ["timestamp", "error_code", "message"], f"Incorrect CSV headers: {headers}"

    with open(JSON_PATH, 'r', encoding='utf-8') as f:
        original_data = json.load(f)

    assert len(rows) - 1 == len(original_data), "Number of rows in CSV does not match JSON entries."

    for i, orig in enumerate(original_data):
        csv_row = rows[i + 1]
        assert str(orig["ts"]) == csv_row[0], f"Row {i+1}: timestamp mismatch."
        assert str(orig["code"]) == csv_row[1], f"Row {i+1}: error_code mismatch."
        assert orig["msg"].lower() == csv_row[2], f"Row {i+1}: message mismatch or not properly lowercased."


def test_csv_is_bulk_importable_with_sqlite3_cli(tmp_path):
    """Exercise the required sqlite3 CLI bulk-import operation on the Rust-generated CSV."""
    temp_db = tmp_path / "cli_import.db"
    script = f""".bail on
CREATE TABLE normalized_logs(timestamp INTEGER, error_code INTEGER, message TEXT);
.mode csv
.import --skip 1 {CSV_PATH} normalized_logs
"""
    subprocess.run(
        ["sqlite3", str(temp_db)],
        input=script,
        text=True,
        check=True,
        capture_output=True,
        timeout=60,
    )

    with open(JSON_PATH, "r", encoding="utf-8") as f:
        original_data = json.load(f)
    conn = sqlite3.connect(temp_db)
    rows = conn.execute("SELECT timestamp, error_code, message FROM normalized_logs ORDER BY rowid").fetchall()
    conn.close()
    assert len(rows) == len(original_data), "sqlite3 CLI did not import every generated CSV row."
    for row, orig in zip(rows, original_data):
        assert str(row[0]) == str(orig["ts"])
        assert str(row[1]) == str(orig["code"])
        assert row[2] == orig["msg"].lower()


def test_sqlite_database_content():
    """Verify the SQLite database exists and contains the correct table and data."""
    db_path = DB_PATH
    assert os.path.isfile(db_path), f"SQLite database {db_path} is missing."

    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='normalized_logs';")
    table = cursor.fetchone()
    assert table is not None, "Table 'normalized_logs' does not exist in the database."

    cursor.execute("SELECT timestamp, error_code, message FROM normalized_logs ORDER BY timestamp ASC;")
    rows = cursor.fetchall()

    with open(JSON_PATH, 'r', encoding='utf-8') as f:
        original_data = json.load(f)
        original_data.sort(key=lambda x: x["ts"])

    assert len(rows) == len(original_data), "Number of rows in SQLite database does not match JSON entries."

    for i, orig in enumerate(original_data):
        db_row = rows[i]
        assert str(orig["ts"]) == str(db_row[0]), f"DB Row {i+1}: timestamp mismatch."
        assert str(orig["code"]) == str(db_row[1]), f"DB Row {i+1}: error_code mismatch."
        assert orig["msg"].lower() == db_row[2], f"DB Row {i+1}: message mismatch or not properly lowercased."

    conn.close()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
