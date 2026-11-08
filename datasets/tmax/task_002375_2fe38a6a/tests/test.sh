#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import decimal
import os
import random
import re
import shutil
import sqlite3
import subprocess
import sys
import tempfile

DB_PATH = "/home/user/supply_chain.db"
CSV_PATH = "/home/user/materials_needed.csv"
ITEMS_PATH = "/home/user/data/items.csv"
BOM_PATH = "/home/user/data/bom.csv"


def test_database_and_indexes():
    """Verify that the SQLite database exists and has appropriate indexes."""
    assert os.path.isfile(DB_PATH), f"Database file {DB_PATH} does not exist."

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute("SELECT name, tbl_name FROM sqlite_master WHERE type='index';")
    indexes = cursor.fetchall()

    assert len(indexes) > 0, "No indexes found in the database."

    tables_with_indexes = set(tbl_name.lower() for name, tbl_name in indexes)
    assert 'bom' in tables_with_indexes, "No index found on the 'bom' table for optimizing downward graph traversal."
    assert 'items' in tables_with_indexes, "No index found on the 'items' table for fast primary key lookups."

    cursor.execute("PRAGMA table_info(items)")
    item_columns = cursor.fetchall()
    cursor.execute("PRAGMA table_info(bom)")
    bom_columns = cursor.fetchall()
    assert {r[1] for r in item_columns} >= {"item_id", "item_name", "item_type"}
    assert {r[1] for r in bom_columns} >= {"parent_id", "child_id", "quantity"}

    item_id_is_pk = any(r[1] == "item_id" and r[5] > 0 for r in item_columns)
    item_id_indexed = False
    parent_id_indexed = False
    for index_name, table_name in indexes:
        try:
            cols = [r[2] for r in cursor.execute(f"PRAGMA index_info('{index_name.replace(chr(39), chr(39)*2)}')")]
        except sqlite3.DatabaseError:
            continue
        if table_name.lower() == "items" and cols and cols[0] == "item_id":
            item_id_indexed = True
        if table_name.lower() == "bom" and cols and cols[0] == "parent_id":
            parent_id_indexed = True

    conn.close()
    assert item_id_is_pk or item_id_indexed, "items.item_id is not a primary key or indexed lookup column."
    assert parent_id_indexed, "No bom index begins with parent_id for downward traversal."


def test_csv_data_was_imported():
    with open(ITEMS_PATH, newline="") as f:
        expected_items = list(csv.DictReader(f))
    with open(BOM_PATH, newline="") as f:
        expected_bom = list(csv.DictReader(f))

    conn = sqlite3.connect(DB_PATH)
    actual_items = conn.execute(
        "SELECT item_id, item_name, item_type FROM items"
    ).fetchall()
    actual_bom = conn.execute(
        "SELECT parent_id, child_id, quantity FROM bom"
    ).fetchall()
    conn.close()

    assert sorted(actual_items) == sorted(
        (r["item_id"], r["item_name"], r["item_type"]) for r in expected_items
    ), "The items table is not an exact import of items.csv."

    def norm_bom(rows):
        return sorted((str(a), str(b), decimal.Decimal(str(q))) for a, b, q in rows)

    expected_bom_rows = [
        (r["parent_id"], r["child_id"], r["quantity"]) for r in expected_bom
    ]
    assert norm_bom(actual_bom) == norm_bom(expected_bom_rows), \
        "The bom table is not an exact import of bom.csv."


def test_materials_needed_csv():
    """Verify that the output CSV exists, has the correct header, sorted rows, and accurate calculations."""
    assert os.path.isfile(CSV_PATH), f"Output file {CSV_PATH} does not exist."

    with open(CSV_PATH, 'r', newline='') as f:
        reader = csv.reader(f)
        rows = list(reader)

    assert len(rows) > 0, "CSV file is empty."

    header = rows[0]
    expected_header = ["leaf_item_id", "leaf_item_name", "total_quantity_needed"]
    assert header == expected_header, f"Expected header {expected_header}, but got {header}."

    data_rows = rows[1:]
    expected_data = [
        ["RAW-1", "SteelSheet", "300"],
        ["RAW-2", "SiliconWafer", "800"],
        ["RAW-3", "CopperWire", "250"]
    ]

    leaf_ids = [row[0] for row in data_rows if len(row) > 0]
    assert leaf_ids == sorted(leaf_ids), "Data rows are not sorted alphabetically by leaf_item_id."
    assert data_rows == expected_data, f"Expected data {expected_data}, but got {data_rows}."


def find_recursive_query_artifacts():
    found = []
    excluded = {DB_PATH, CSV_PATH, ITEMS_PATH, BOM_PATH}
    for root, dirs, files in os.walk("/home/user"):
        dirs[:] = [d for d in dirs if d not in {"data", ".cache", "__pycache__", ".local"}]
        for name in files:
            path = os.path.join(root, name)
            if path in excluded:
                continue
            try:
                if os.path.getsize(path) > 1024 * 1024:
                    continue
                with open(path, "r", errors="ignore") as f:
                    text = f.read()
            except OSError:
                continue
            if re.search(r"\bWITH\s+RECURSIVE\b", text, re.I) and re.search(r"\bbom\b", text, re.I):
                found.append((path, text))
    return found


def read_result(stdout):
    if os.path.isfile(CSV_PATH):
        with open(CSV_PATH, newline="") as f:
            return list(csv.reader(f))

    lines = [line.strip() for line in stdout.splitlines() if line.strip()]
    header = "leaf_item_id,leaf_item_name,total_quantity_needed"
    for i, line in enumerate(lines):
        if line.replace(" ", "") == header:
            return list(csv.reader(lines[i:]))
    pipe_header = "leaf_item_id|leaf_item_name|total_quantity_needed"
    for i, line in enumerate(lines):
        if line.replace(" ", "") == pipe_header:
            return [x.split("|") for x in lines[i:]]
    return []


def result_matches(rows, expected):
    if not rows or rows[0] != ["leaf_item_id", "leaf_item_name", "total_quantity_needed"]:
        return False
    if [r[0] for r in rows[1:] if len(r) == 3] != sorted(r[0] for r in rows[1:] if len(r) == 3):
        return False
    try:
        actual = [(r[0], r[1], decimal.Decimal(r[2])) for r in rows[1:] if len(r) == 3]
    except decimal.InvalidOperation:
        return False
    return actual == expected


def test_parameterized_recursive_query_executes_on_changed_inputs():
    artifacts = find_recursive_query_artifacts()
    assert artifacts, "No script containing a recursive BOM CTE was found."

    rng = random.SystemRandom()
    target_qty = rng.randint(7, 29)
    sub_a_qty = rng.randint(3, 11)
    sub_b_qty = rng.randint(2, 9)
    expected = [
        ("RAW-1", "SteelSheet", decimal.Decimal(target_qty * sub_a_qty * 3)),
        ("RAW-2", "SiliconWafer", decimal.Decimal(target_qty * (sub_a_qty * 4 + sub_b_qty * 8))),
        ("RAW-3", "CopperWire", decimal.Decimal(target_qty * sub_b_qty * 5)),
    ]

    with tempfile.TemporaryDirectory() as td:
        db_backup = os.path.join(td, "supply_chain.db")
        out_backup = os.path.join(td, "materials_needed.csv")
        items_backup = os.path.join(td, "items.csv")
        bom_backup = os.path.join(td, "bom.csv")
        shutil.copy2(DB_PATH, db_backup)
        shutil.copy2(ITEMS_PATH, items_backup)
        shutil.copy2(BOM_PATH, bom_backup)
        output_existed = os.path.isfile(CSV_PATH)
        if output_existed:
            shutil.copy2(CSV_PATH, out_backup)

        def prepare_changed_inputs():
            shutil.copy2(db_backup, DB_PATH)
            shutil.copy2(items_backup, ITEMS_PATH)
            shutil.copy2(bom_backup, BOM_PATH)
            if os.path.exists(CSV_PATH):
                os.remove(CSV_PATH)

            conn = sqlite3.connect(DB_PATH)
            conn.execute("UPDATE bom SET quantity=? WHERE parent_id='PROD-002' AND child_id='SUB-A'", (sub_a_qty,))
            conn.execute("UPDATE bom SET quantity=? WHERE parent_id='PROD-002' AND child_id='SUB-B'", (sub_b_qty,))
            conn.commit()
            conn.close()

            with open(BOM_PATH, newline="") as f:
                rows = list(csv.DictReader(f))
            for row in rows:
                if row["parent_id"] == "PROD-002" and row["child_id"] == "SUB-A":
                    row["quantity"] = str(sub_a_qty)
                if row["parent_id"] == "PROD-002" and row["child_id"] == "SUB-B":
                    row["quantity"] = str(sub_b_qty)
            with open(BOM_PATH, "w", newline="") as f:
                writer = csv.DictWriter(f, fieldnames=["parent_id", "child_id", "quantity"])
                writer.writeheader()
                writer.writerows(rows)

        passed = False
        errors = []
        try:
            for path, text in artifacts:
                ext = os.path.splitext(path)[1].lower()
                if ext == ".sql":
                    prepare_changed_inputs()
                    sql = (
                        ".parameter init\n"
                        ".parameter set :item_id PROD-002\n"
                        ".parameter set :target_item_id PROD-002\n"
                        f".parameter set :target_quantity {target_qty}\n"
                        f".parameter set :quantity {target_qty}\n"
                        ".headers on\n.mode csv\n"
                        f".read {path}\n"
                    )
                    commands = [(["sqlite3", DB_PATH], sql)]
                else:
                    if ext == ".py":
                        base = [sys.executable, path]
                    elif ext in {".sh", ".bash"}:
                        base = ["bash", path]
                    elif os.access(path, os.X_OK):
                        base = [path]
                    else:
                        continue
                    commands = [
                        (base + ["PROD-002", str(target_qty)], None),
                        (base + ["--item-id", "PROD-002", "--target-quantity", str(target_qty)], None),
                        (base + ["--target-item-id", "PROD-002", "--target-quantity", str(target_qty)], None),
                        (base + ["PROD-002", str(target_qty), CSV_PATH], None),
                    ]

                for command, stdin_text in commands:
                    prepare_changed_inputs()
                    try:
                        proc = subprocess.run(
                            command, input=stdin_text, text=True, stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, cwd="/home/user", timeout=20
                        )
                    except (OSError, subprocess.TimeoutExpired) as exc:
                        errors.append(f"{path}: {exc}")
                        continue
                    rows = read_result(proc.stdout)
                    if proc.returncode == 0 and result_matches(rows, expected):
                        passed = True
                        break
                    errors.append(f"{path}: exit={proc.returncode}, stderr={proc.stderr[-300:]}")
                if passed:
                    break
        finally:
            shutil.copy2(db_backup, DB_PATH)
            shutil.copy2(items_backup, ITEMS_PATH)
            shutil.copy2(bom_backup, BOM_PATH)
            if output_existed:
                shutil.copy2(out_backup, CSV_PATH)
            elif os.path.exists(CSV_PATH):
                os.remove(CSV_PATH)

    assert passed, "No recursive-CTE artifact accepted parameters and computed changed BOM inputs. " + " | ".join(errors[-4:])
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
