#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import hashlib
import json
import os
import re
import shutil
import sqlite3
import stat
import subprocess
import tempfile
import uuid

import pytest

DB_PATH = "/home/user/ecommerce.db"
SCRIPT_PATH = "/home/user/run_pipeline.py"
INSIGHTS_PATH = "/home/user/insights.json"


def get_expected_insights():
    """Compute the expected insights directly from the database."""
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    query = """
    SELECT DISTINCT p1.user_id, p1.product_id
    FROM purchases p1
    JOIN reviews r ON p1.user_id = r.user_id AND p1.product_id = r.product_id
    WHERE r.rating = 1
    """
    cursor.execute(query)
    bad_reviews = cursor.fetchall()

    target_products = set()
    for user_id, bad_product_id in bad_reviews:
        cursor.execute("""
        SELECT product_id
        FROM purchases
        WHERE user_id = ? AND product_id != ?
        """, (user_id, bad_product_id))
        for (prod_id,) in cursor.fetchall():
            target_products.add(prod_id)

    expected_insights = {}
    for prod_id in target_products:
        cursor.execute("SELECT title, category FROM products WHERE id = ?", (prod_id,))
        title, category = cursor.fetchone()
        expected_insights.setdefault(category, []).append(title)

    conn.close()
    for category in expected_insights:
        expected_insights[category].sort()
    return expected_insights


def run_pipeline():
    result = subprocess.run(
        ["python3", SCRIPT_PATH],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"run_pipeline.py exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def read_json_output():
    assert os.path.exists(INSIGHTS_PATH), f"Expected output file {INSIGHTS_PATH} does not exist."
    assert os.path.isfile(INSIGHTS_PATH), f"{INSIGHTS_PATH} is not a file."
    with open(INSIGHTS_PATH, "r", encoding="utf-8") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError as exc:
            pytest.fail(f"{INSIGHTS_PATH} does not contain valid JSON: {exc}")


def test_pipeline_script_exists_and_has_required_implementation_signals():
    assert os.path.exists(SCRIPT_PATH), f"Required script {SCRIPT_PATH} does not exist."
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is not a file."
    assert stat.S_ISREG(os.stat(SCRIPT_PATH).st_mode), f"{SCRIPT_PATH} is not a regular file."

    with open(SCRIPT_PATH, "r", encoding="utf-8") as f:
        source = f.read()
    try:
        tree = ast.parse(source, filename=SCRIPT_PATH)
    except SyntaxError as exc:
        pytest.fail(f"{SCRIPT_PATH} is not valid Python: {exc}")

    parameterized_calls = []
    for node in ast.walk(tree):
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute):
            if node.func.attr in {"execute", "executemany"}:
                has_params = len(node.args) >= 2 or any(
                    kw.arg in {"params", "parameters"} for kw in node.keywords
                )
                if has_params:
                    parameterized_calls.append(node)

    has_placeholder = "?" in source or re.search(r"(?<!:):[A-Za-z_][A-Za-z0-9_]*", source)
    assert parameterized_calls and has_placeholder, (
        "The pipeline must use parameterized SQL when reading relational data."
    )

    string_literals = {
        node.value for node in ast.walk(tree)
        if isinstance(node, ast.Constant) and isinstance(node.value, str)
    }
    assert "PURCHASED" in string_literals and "REVIEWED" in string_literals, (
        "The in-memory graph must represent both PURCHASED and REVIEWED edge types."
    )

    uses_networkx = any(
        (isinstance(node, ast.Import) and any(alias.name == "networkx" for alias in node.names))
        or (isinstance(node, ast.ImportFrom) and node.module == "networkx")
        for node in ast.walk(tree)
    )
    uses_custom_containers = any(
        isinstance(node, (ast.Dict, ast.List, ast.Set, ast.DictComp, ast.ListComp, ast.SetComp))
        for node in ast.walk(tree)
    )
    assert uses_networkx or uses_custom_containers, (
        "The pipeline must build an in-memory graph using networkx or custom data structures."
    )


def test_pipeline_executes_on_original_database():
    if os.path.lexists(INSIGHTS_PATH):
        os.remove(INSIGHTS_PATH)
    before_hash = hashlib.sha256(open(DB_PATH, "rb").read()).hexdigest()
    run_pipeline()
    after_hash = hashlib.sha256(open(DB_PATH, "rb").read()).hexdigest()
    assert after_hash == before_hash, "The ETL pipeline must not modify the source database."


def test_insights_file_exists():
    assert os.path.exists(INSIGHTS_PATH), f"Expected output file {INSIGHTS_PATH} does not exist."
    assert os.path.isfile(INSIGHTS_PATH), f"{INSIGHTS_PATH} is not a file."


def test_insights_content():
    assert os.path.exists(INSIGHTS_PATH), f"Cannot check content, {INSIGHTS_PATH} is missing."

    with open(INSIGHTS_PATH, 'r') as f:
        try:
            actual_insights = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{INSIGHTS_PATH} does not contain valid JSON.")

    expected_insights = get_expected_insights()

    assert set(actual_insights.keys()) == set(expected_insights.keys()), \
        f"Categories in insights.json {list(actual_insights.keys())} do not match expected {list(expected_insights.keys())}."

    for category, expected_titles in expected_insights.items():
        actual_titles = actual_insights[category]
        assert isinstance(actual_titles, list), f"Value for category '{category}' should be a list."
        assert actual_titles == expected_titles, \
            f"Titles for category '{category}' do not match expected. Expected: {expected_titles}, Actual: {actual_titles}."


def test_pipeline_handles_unseen_database_content():
    token = uuid.uuid4().hex
    temp_dir = tempfile.mkdtemp(prefix="pipeline_verify_")
    db_backup = os.path.join(temp_dir, "ecommerce.db")
    shutil.copy2(DB_PATH, db_backup)
    output_existed = os.path.exists(INSIGHTS_PATH)
    output_backup = os.path.join(temp_dir, "insights.json")
    if output_existed:
        shutil.copy2(INSIGHTS_PATH, output_backup)

    try:
        os.remove(DB_PATH)
        conn = sqlite3.connect(DB_PATH)
        cur = conn.cursor()
        cur.executescript("""
            CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT);
            CREATE TABLE products (id INTEGER PRIMARY KEY, title TEXT, category TEXT);
            CREATE TABLE purchases (id INTEGER PRIMARY KEY, user_id INTEGER, product_id INTEGER, purchase_date TEXT);
            CREATE TABLE reviews (id INTEGER PRIMARY KEY, user_id INTEGER, product_id INTEGER, rating INTEGER, review_text TEXT);
        """)
        cur.executemany("INSERT INTO users (id, name) VALUES (?, ?)", [
            (17, "Buyer One"), (29, "Buyer Two"), (41, "Reviewer Only"), (53, "Two Bad Items")
        ])
        products = [
            (701, f"Bad-{token}", f"BadCat-{token}"),
            (702, f"Target-Z-{token}", f"Shared-{token}"),
            (703, f"Target-A-{token}", f"Shared-{token}"),
            (704, f"TwoStar-{token}", f"Other-{token}"),
            (705, f"NotTarget-{token}", f"Other-{token}"),
            (706, f"UnpurchasedBad-{token}", f"Other-{token}"),
            (707, f"ReviewerPurchase-{token}", f"Other-{token}"),
            (708, f"Bad-X-{token}", f"Pair-{token}"),
            (709, f"Bad-Y-{token}", f"Pair-{token}"),
        ]
        cur.executemany("INSERT INTO products (id, title, category) VALUES (?, ?, ?)", products)
        cur.executemany(
            "INSERT INTO purchases (user_id, product_id, purchase_date) VALUES (?, ?, ?)",
            [
                (17, 701, "2025-01-01"), (17, 702, "2025-01-02"),
                (17, 703, "2025-01-03"), (17, 702, "2025-01-04"),
                (29, 704, "2025-02-01"), (29, 705, "2025-02-02"),
                (41, 707, "2025-03-01"),
                (53, 708, "2025-04-01"), (53, 709, "2025-04-02"),
            ],
        )
        cur.executemany(
            "INSERT INTO reviews (user_id, product_id, rating, review_text) VALUES (?, ?, ?, ?)",
            [
                (17, 701, 1, "bad"), (29, 704, 2, "not one star"),
                (41, 706, 1, "reviewed but not purchased"),
                (53, 708, 1, "bad x"), (53, 709, 1, "bad y"),
            ],
        )
        conn.commit()
        conn.close()

        expected = get_expected_insights()
        before_hash = hashlib.sha256(open(DB_PATH, "rb").read()).hexdigest()
        if os.path.lexists(INSIGHTS_PATH):
            os.remove(INSIGHTS_PATH)

        run_pipeline()
        actual = read_json_output()
        after_hash = hashlib.sha256(open(DB_PATH, "rb").read()).hexdigest()

        assert after_hash == before_hash, "The ETL pipeline modified the synthetic source database."
        assert set(actual.keys()) == set(expected.keys()), (
            f"Categories for unseen data do not match. Expected {expected}, actual {actual}."
        )
        for category, expected_titles in expected.items():
            assert isinstance(actual[category], list), f"Value for category '{category}' should be a list."
            assert actual[category] == expected_titles, (
                f"Titles for unseen category '{category}' do not match. "
                f"Expected {expected_titles}, actual {actual[category]}."
            )
    finally:
        if os.path.exists(DB_PATH):
            os.remove(DB_PATH)
        shutil.copy2(db_backup, DB_PATH)
        if os.path.lexists(INSIGHTS_PATH):
            os.remove(INSIGHTS_PATH)
        if output_existed:
            shutil.copy2(output_backup, INSIGHTS_PATH)
        shutil.rmtree(temp_dir)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
