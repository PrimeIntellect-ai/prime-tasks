#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import shutil
import sqlite3
import statistics
import subprocess
import tempfile
from pathlib import Path

import pytest


def test_recovered_sql_contains_data():
    recovered_path = "/home/user/recovered.sql"
    assert os.path.isfile(recovered_path), f"Expected recovered SQL file does not exist at {recovered_path}"

    with open(recovered_path, "r") as f:
        content = f.read()

    expected_values = ["1000000001.1", "1000000001.3", "1000000001.5"]
    for val in expected_values:
        assert val in content, f"Expected value {val} not found in {recovered_path}"


def test_variance_calculation():
    variance_path = "/home/user/variance.txt"
    assert os.path.isfile(variance_path), f"Expected variance output file does not exist at {variance_path}"

    with open(variance_path, "r") as f:
        content = f.read().strip()

    assert content == "0.0400", f"Expected variance to be '0.0400', but got '{content}'"


def recover_source_rows():
    source = Path("/home/user/sensor.db").read_bytes()
    assert len(source) >= 16, "sensor.db is too short to be the supplied database"
    repaired = b"SQLite format 3\x00" + source[16:]
    with tempfile.NamedTemporaryFile(suffix=".db") as tmp:
        tmp.write(repaired)
        tmp.flush()
        con = sqlite3.connect(tmp.name)
        try:
            tables = con.execute(
                "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name"
            ).fetchall()
            assert tables == [("measurements",)], "The repaired source database does not contain the expected single table"
            columns = con.execute("PRAGMA table_info(measurements)").fetchall()
            assert len(columns) == 1
            assert columns[0][1] == "value"
            assert columns[0][2].upper() == "REAL"
            return [row[0] for row in con.execute("SELECT value FROM measurements ORDER BY rowid")]
        finally:
            con.close()


def test_recovered_sql_is_an_executable_complete_dump():
    expected_rows = recover_source_rows()
    dump = Path("/home/user/recovered.sql").read_text()

    con = sqlite3.connect(":memory:")
    try:
        con.executescript(dump)
        tables = con.execute(
            "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name"
        ).fetchall()
        assert tables == [("measurements",)], "Recovered SQL must reconstruct the single measurements table"

        columns = con.execute("PRAGMA table_info(measurements)").fetchall()
        assert len(columns) == 1, "measurements must have exactly one column"
        assert columns[0][1] == "value", "The reconstructed column must be named value"
        assert columns[0][2].upper() == "REAL", "The reconstructed value column must have REAL type"

        actual_rows = [row[0] for row in con.execute("SELECT value FROM measurements ORDER BY rowid")]
        assert actual_rows == expected_rows, "Recovered SQL does not reconstruct all rows from sensor.db"
    finally:
        con.close()


def script_command(path):
    suffix = path.suffix.lower()
    interpreters = {
        ".py": "python3",
        ".pl": "perl",
        ".rb": "ruby",
        ".sh": "bash",
        ".js": "node",
        ".php": "php",
        ".lua": "lua",
        ".awk": "awk",
    }
    if suffix in interpreters and shutil.which(interpreters[suffix]):
        return [interpreters[suffix], str(path)]
    try:
        first = path.open("rb").readline(256)
    except OSError:
        return None
    if first.startswith(b"#!") and os.access(path, os.X_OK):
        return [str(path)]
    return None


def test_submitted_script_executes_and_computes_unseen_values():
    home = Path("/home/user")
    recovered = home / "recovered.sql"
    variance = home / "variance.txt"

    excluded = {home / "recovered.sql", home / "variance.txt", home / "sensor.db"}
    candidates = []
    for path in home.rglob("*"):
        if path.is_file() and path not in excluded:
            command = script_command(path)
            if command is not None:
                candidates.append((path, command))
    assert candidates, "No variance-calculation script was found under /home/user"

    db_paths = sorted(
        {p for pattern in ("*.db", "*.sqlite", "*.sqlite3") for p in home.rglob(pattern) if p.is_file()}
    )
    assert home / "sensor.db" in db_paths

    original_files = {}
    for path in set(db_paths + [recovered, variance]):
        original_files[path] = (path.read_bytes(), path.stat().st_mode)

    original_db_set = set(db_paths)

    def restore_originals():
        for pattern in ("*.db", "*.sqlite", "*.sqlite3"):
            for path in home.rglob(pattern):
                if path.is_file() and path not in original_db_set:
                    path.unlink()
        for path, (data, mode) in original_files.items():
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
            os.chmod(path, mode)

    offsets = [-17.25, -3.5, 2.75, 11.0, 29.5, 46.25]
    alternate_values = [1000000000.0 + x for x in offsets]
    alternate_sql = "CREATE TABLE measurements (value REAL);\n" + "\n".join(
        f"INSERT INTO measurements(value) VALUES ({value!r});" for value in alternate_values
    ) + "\n"

    with tempfile.NamedTemporaryFile(suffix=".db", delete=False) as tmp:
        alternate_db_path = Path(tmp.name)
    try:
        con = sqlite3.connect(str(alternate_db_path))
        con.executescript(alternate_sql)
        stored_values = [r[0] for r in con.execute("SELECT value FROM measurements ORDER BY rowid")]
        con.close()
        alternate_db = alternate_db_path.read_bytes()
    finally:
        alternate_db_path.unlink(missing_ok=True)

    expected_alternate = format(statistics.variance(stored_values), ".4f")
    assert expected_alternate != "0.0400"

    successful = None
    try:
        for path, command in candidates:
            restore_originals()
            recovered.write_text(alternate_sql)
            for db_path in db_paths:
                db_path.write_bytes(alternate_db)
            variance.write_text("SCRIPT_DID_NOT_UPDATE_OUTPUT\n")

            try:
                result = subprocess.run(
                    command,
                    cwd=str(home),
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    text=True,
                    timeout=15,
                    env={**os.environ, "HOME": str(home)},
                )
            except (OSError, subprocess.TimeoutExpired):
                continue

            if result.returncode == 0 and variance.is_file() and variance.read_text().strip() == expected_alternate:
                successful = (path, command)
                break

        assert successful is not None, (
            "No submitted script recomputed the sample variance for verifier-generated recovered values"
        )

        restore_originals()
        variance.write_text("SCRIPT_DID_NOT_UPDATE_OUTPUT\n")
        result = subprocess.run(
            successful[1],
            cwd=str(home),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=15,
            env={**os.environ, "HOME": str(home)},
        )
        assert result.returncode == 0, f"The submitted script failed on the recovered data: {result.stderr}"
        assert variance.read_text().strip() == "0.0400", "The submitted script did not regenerate the required final output"
    finally:
        if successful is None:
            restore_originals()

TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
