#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import shutil
import sqlite3
import subprocess
import tempfile

DB_PATH = "/home/user/db_perf/sales.db"
INDEX_SQL_PATH = "/home/user/db_perf/indexes.sql"
CPP_PATH = "/home/user/db_perf/aggregator.cpp"
EXE_PATH = "/home/user/db_perf/aggregator"
JSON_PATH = "/home/user/db_perf/regional_summary.json"
PROJECT_DIR = "/home/user/db_perf"


def custom_indexes(conn):
    rows = conn.execute("SELECT name, tbl_name, sql FROM sqlite_master WHERE type='index'").fetchall()
    return [row for row in rows if not row[0].startswith("sqlite_")]


def index_columns(conn, name):
    quoted = name.replace('"', '""')
    return [row[2].lower() for row in conn.execute(f'PRAGMA index_info("{quoted}")')]


def has_meaningful_strategy(conn):
    orders_ok = False
    items_ok = False
    for name, table, sql in custom_indexes(conn):
        cols = index_columns(conn, name)
        table = table.lower()
        definition = (sql or "").lower()
        if table == "orders":
            # A normal status index or a partial COMPLETED-order index supports
            # the required selective predicate.
            if "status" in cols or (" where " in definition and "status" in definition and "completed" in definition):
                orders_ok = True
        elif table == "order_items" and ("order_id" in cols or "product_id" in cols):
            items_ok = True
    return orders_ok and items_ok


def test_indexes_created_and_relevant():
    assert os.path.isfile(INDEX_SQL_PATH), f"File {INDEX_SQL_PATH} is missing."
    with open(INDEX_SQL_PATH, "r", encoding="utf-8") as f:
        index_sql = f.read()
    assert "create" in index_sql.lower() and "index" in index_sql.lower(), "indexes.sql contains no index creation statements."

    conn = sqlite3.connect(DB_PATH)
    try:
        indexes = custom_indexes(conn)
        assert len(indexes) > 0, "No custom indexes found in the database. You must apply the indexes."
        assert has_meaningful_strategy(conn), (
            "Applied indexes must support the COMPLETED-order filter and an order_items join."
        )
    finally:
        conn.close()

    # Verify that indexes.sql itself defines the relevant strategy, rather than
    # merely relying on unrelated indexes created separately in the database.
    staged = sqlite3.connect(":memory:")
    try:
        staged.executescript("""
            CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT, region TEXT);
            CREATE TABLE orders (id INTEGER PRIMARY KEY, user_id INTEGER, order_date TEXT, status TEXT);
            CREATE TABLE products (id INTEGER PRIMARY KEY, name TEXT, category TEXT);
            CREATE TABLE order_items (id INTEGER PRIMARY KEY, order_id INTEGER, product_id INTEGER, quantity INTEGER, price REAL);
        """)
        staged.executescript(index_sql)
        assert custom_indexes(staged), "indexes.sql does not create any custom indexes."
        assert has_meaningful_strategy(staged), (
            "indexes.sql must define indexes supporting the COMPLETED-order filter and an order_items join."
        )
    finally:
        staged.close()


def calculate_truth():
    conn = sqlite3.connect(DB_PATH)
    try:
        rows = conn.execute("""
            SELECT u.region, p.category, SUM(oi.quantity * oi.price), COUNT(DISTINCT o.id)
            FROM users u
            JOIN orders o ON u.id = o.user_id
            JOIN order_items oi ON o.id = oi.order_id
            JOIN products p ON oi.product_id = p.id
            WHERE o.status = 'COMPLETED'
            GROUP BY u.region, p.category
        """).fetchall()
    finally:
        conn.close()

    truth = {}
    for region, category, revenue, count in rows:
        truth.setdefault(region, {})[category] = {
            "revenue": round(revenue, 2),
            "order_count": count,
        }
    return truth


def validate_json(truth):
    assert os.path.isfile(JSON_PATH), f"JSON output missing at {JSON_PATH}."
    try:
        with open(JSON_PATH, "r", encoding="utf-8") as f:
            data = json.load(f)
    except (OSError, json.JSONDecodeError) as exc:
        raise AssertionError(f"File {JSON_PATH} is not valid readable JSON: {exc}")

    assert isinstance(data, list), "JSON root must be a list."
    regions = [obj.get("region") if isinstance(obj, dict) else None for obj in data]
    assert all(isinstance(region, str) for region in regions), "Every region entry must be an object with a string region."
    assert regions == sorted(regions), "Regions in JSON are not sorted alphabetically."
    assert regions == sorted(truth), "JSON must contain every expected region exactly once."

    for region_obj in data:
        assert set(region_obj) == {"region", "categories"}, "Region objects must exactly contain region and categories."
        region = region_obj["region"]
        assert region in truth, f"Unexpected region '{region}' in output."
        categories = region_obj["categories"]
        assert isinstance(categories, list), f"'categories' for region '{region}' must be a list."

        names = [cat.get("category") if isinstance(cat, dict) else None for cat in categories]
        assert all(isinstance(name, str) for name in names), f"Invalid category object in region '{region}'."
        assert names == sorted(names), f"Categories in region '{region}' are not sorted alphabetically."
        assert names == sorted(truth[region]), f"Missing, duplicate, or unexpected categories in region '{region}'."

        for cat_obj in categories:
            assert set(cat_obj) == {"category", "revenue", "order_count"}, (
                "Category objects must exactly contain category, revenue, and order_count."
            )
            category = cat_obj["category"]
            expected = truth[region][category]
            revenue = cat_obj["revenue"]
            count = cat_obj["order_count"]
            assert isinstance(revenue, (int, float)) and not isinstance(revenue, bool), "Revenue must be numeric."
            assert isinstance(count, int) and not isinstance(count, bool), "Order count must be an integer."
            assert abs(expected["revenue"] - revenue) < 0.1, (
                f"Revenue mismatch for {region}-{category}. Expected {expected['revenue']}, got {revenue}."
            )
            assert expected["order_count"] == count, (
                f"Order count mismatch for {region}-{category}. Expected {expected['order_count']}, got {count}."
            )


def run_and_check(executable, truth):
    if os.path.exists(JSON_PATH):
        os.unlink(JSON_PATH)
    result = subprocess.run(
        [executable], cwd=PROJECT_DIR, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, timeout=30
    )
    assert result.returncode == 0, (
        f"{executable} exited with status {result.returncode}.\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    validate_json(truth)


def add_runtime_challenge():
    token = secrets.token_hex(8)
    region = "VerifierRegion_" + token
    category = "VerifierCategory_" + token
    conn = sqlite3.connect(DB_PATH)
    try:
        user_id = conn.execute("SELECT COALESCE(MAX(id), 0) + 1 FROM users").fetchone()[0]
        product_id = conn.execute("SELECT COALESCE(MAX(id), 0) + 1 FROM products").fetchone()[0]
        order_id = conn.execute("SELECT COALESCE(MAX(id), 0) + 1 FROM orders").fetchone()[0]
        item_id = conn.execute("SELECT COALESCE(MAX(id), 0) + 1 FROM order_items").fetchone()[0]
        conn.execute("INSERT INTO users VALUES (?, ?, ?)", (user_id, "Verifier User", region))
        conn.execute("INSERT INTO products VALUES (?, ?, ?)", (product_id, "Verifier Product", category))
        conn.execute("INSERT INTO orders VALUES (?, ?, ?, 'COMPLETED')", (order_id, user_id, "2099-01-01"))
        conn.execute("INSERT INTO order_items VALUES (?, ?, ?, ?, ?)", (item_id, order_id, product_id, 3, 17.23))
        conn.execute("INSERT INTO order_items VALUES (?, ?, ?, ?, ?)", (item_id + 1, order_id, product_id, 2, 9.11))
        # This large pending order detects implementations that omit the status predicate.
        conn.execute("INSERT INTO orders VALUES (?, ?, ?, 'PENDING')", (order_id + 1, user_id, "2099-01-02"))
        conn.execute("INSERT INTO order_items VALUES (?, ?, ?, ?, ?)", (item_id + 2, order_id + 1, product_id, 100, 999.99))
        conn.commit()
    finally:
        conn.close()


def test_cpp_compiles_and_both_binaries_generate_output():
    assert os.path.isfile(CPP_PATH), f"C++ source file missing at {CPP_PATH}."
    assert os.path.getsize(CPP_PATH) > 0, f"C++ source file at {CPP_PATH} is empty."
    assert os.path.isfile(EXE_PATH), f"Compiled executable missing at {EXE_PATH}."
    assert os.access(EXE_PATH, os.X_OK), f"File {EXE_PATH} is not executable."
    with open(EXE_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "aggregator must be a compiled executable, not a script or placeholder."

    work = tempfile.mkdtemp(prefix="aggregator_verify_")
    compiled = os.path.join(work, "aggregator_from_source")
    original_db = os.path.join(work, "original.db")
    challenge_db = os.path.join(work, "challenge.db")
    shutil.copy2(DB_PATH, original_db)
    original_truth = calculate_truth()

    build = subprocess.run(
        ["g++", "-std=c++17", "-O2", CPP_PATH, "-o", compiled, "-lsqlite3"],
        cwd=PROJECT_DIR, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=60
    )
    assert build.returncode == 0, f"aggregator.cpp does not compile.\nstdout:\n{build.stdout}\nstderr:\n{build.stderr}"
    with open(compiled, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Freshly compiled aggregator is not an ELF executable."

    try:
        add_runtime_challenge()
        challenge_truth = calculate_truth()
        shutil.copy2(DB_PATH, challenge_db)

        # Test the submitted executable and an independently compiled build on
        # verifier-generated data not present when the agent produced its JSON.
        for executable in (EXE_PATH, compiled):
            shutil.copy2(challenge_db, DB_PATH)
            run_and_check(executable, challenge_truth)
    finally:
        shutil.copy2(original_db, DB_PATH)

    # Leave and verify a correct output for the original task database as well.
    run_and_check(EXE_PATH, original_truth)
    shutil.rmtree(work, ignore_errors=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
