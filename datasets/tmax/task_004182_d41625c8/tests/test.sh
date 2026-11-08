#!/bin/bash
set -e
mkdir -p /logs/verifier

mkdir -p /tmp/etl_instrument
cat << 'PY_EOF' > /tmp/etl_instrument/sitecustomize.py
import os
import threading

TRACE = "/tmp/etl_parallel_trace"

def _mark(kind):
    try:
        line = "%s:%s:%s\n" % (kind, os.getpid(), threading.get_ident())
        fd = os.open(TRACE, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o666)
        try:
            os.write(fd, line.encode("ascii"))
        finally:
            os.close(fd)
    except Exception:
        pass

try:
    import difflib
    _original_ratio = difflib.SequenceMatcher.ratio
    def _instrumented_ratio(self):
        _mark("ratio")
        return _original_ratio(self)
    difflib.SequenceMatcher.ratio = _instrumented_ratio
except Exception:
    pass

try:
    import multiprocessing.process
    _original_start = multiprocessing.process.BaseProcess.start
    def _instrumented_start(self, *args, **kwargs):
        _mark("dispatch")
        return _original_start(self, *args, **kwargs)
    multiprocessing.process.BaseProcess.start = _instrumented_start
except Exception:
    pass

try:
    import multiprocessing.pool
    for _name in ("apply", "apply_async", "map", "map_async", "starmap", "starmap_async", "imap", "imap_unordered"):
        _original = getattr(multiprocessing.pool.Pool, _name)
        def _make_wrapper(original):
            def _wrapper(self, *args, **kwargs):
                _mark("dispatch")
                return original(self, *args, **kwargs)
            return _wrapper
        setattr(multiprocessing.pool.Pool, _name, _make_wrapper(_original))
except Exception:
    pass

try:
    import concurrent.futures
    for _class in (concurrent.futures.ThreadPoolExecutor, concurrent.futures.ProcessPoolExecutor):
        _original_submit = _class.submit
        def _make_submit(original):
            def _submit(self, *args, **kwargs):
                _mark("dispatch")
                return original(self, *args, **kwargs)
            return _submit
        _class.submit = _make_submit(_original_submit)
except Exception:
    pass
PY_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import csv
import difflib
import json
import math
import os
import sqlite3
import subprocess
from collections import Counter

import pytest

DB_PATH = "/home/user/etl_results.db"
JSON_PATH = "/home/user/summary.json"
RAW_DATA_PATH = "/home/user/raw_products.csv"
PIPELINE_PATH = "/home/user/pipeline.py"
TRACE_PATH = "/tmp/etl_parallel_trace"
LANGUAGES = ("en", "fr", "es")


def read_raw_long_products():
    rows = []
    products = {lang: [] for lang in LANGUAGES}
    with open(RAW_DATA_PATH, "r", encoding="utf-8", newline="") as f:
        reader = csv.DictReader(f)
        for row in reader:
            vendor = row["vendor_id"]
            for lang in LANGUAGES:
                name = row.get("name_" + lang)
                if name is not None and name != "":
                    description = row.get("desc_" + lang)
                    rows.append((vendor, lang, name, description))
                    products[lang].append((vendor, name))
    return rows, products


def expected_pairs():
    _, products = read_raw_long_products()
    result = {lang: {} for lang in LANGUAGES}
    for lang in LANGUAGES:
        items = products[lang]
        for i in range(len(items)):
            for j in range(i + 1, len(items)):
                v1, n1 = items[i]
                v2, n2 = items[j]
                if v1 > v2:
                    v1, v2 = v2, v1
                    n1, n2 = n2, n1
                score = difflib.SequenceMatcher(None, n1, n2).ratio()
                if score >= 0.85:
                    result[lang][(v1, v2)] = score
    return result


@pytest.fixture(scope="session", autouse=True)
def execute_pipeline():
    assert os.path.isfile(PIPELINE_PATH), f"Pipeline not found at {PIPELINE_PATH}"

    with open(PIPELINE_PATH, "r", encoding="utf-8") as f:
        source = f.read()
    try:
        tree = ast.parse(source, filename=PIPELINE_PATH)
    except SyntaxError as exc:
        pytest.fail(f"pipeline.py is not valid Python: {exc}")

    has_parallel_import = False
    has_executemany = False
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            if any(alias.name in ("multiprocessing", "concurrent.futures") or alias.name.startswith("concurrent.futures") for alias in node.names):
                has_parallel_import = True
        elif isinstance(node, ast.ImportFrom):
            if node.module in ("multiprocessing", "concurrent.futures", "concurrent"):
                has_parallel_import = True
        elif isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute):
            if node.func.attr == "executemany":
                has_executemany = True

    assert has_parallel_import, "pipeline.py must use multiprocessing or concurrent.futures"
    assert has_executemany, "pipeline.py must bulk-load rows with sqlite3 executemany"

    for path in (DB_PATH, JSON_PATH, TRACE_PATH):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    env = os.environ.copy()
    old_pythonpath = env.get("PYTHONPATH")
    env["PYTHONPATH"] = "/tmp/etl_instrument" + ((":" + old_pythonpath) if old_pythonpath else "")
    try:
        completed = subprocess.run(
            ["python3", PIPELINE_PATH],
            cwd="/home/user",
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=120,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("pipeline.py did not finish within 120 seconds")

    assert completed.returncode == 0, (
        "pipeline.py failed when executed.\n"
        f"stdout:\n{completed.stdout}\n"
        f"stderr:\n{completed.stderr}"
    )

    assert os.path.exists(TRACE_PATH), "No parallel similarity work was observed"
    dispatches = []
    ratios = []
    with open(TRACE_PATH, "r", encoding="ascii", errors="replace") as f:
        for line in f:
            parts = line.strip().split(":")
            if len(parts) != 3:
                continue
            identity = (parts[1], parts[2])
            if parts[0] == "dispatch":
                dispatches.append(identity)
            elif parts[0] == "ratio":
                ratios.append(identity)

    assert dispatches, "The pipeline did not dispatch work through multiprocessing or concurrent.futures"
    root_identity = dispatches[0]
    worker_ratio_count = sum(identity != root_identity for identity in ratios)
    _, products = read_raw_long_products()
    required_comparisons = sum(len(items) * (len(items) - 1) // 2 for items in products.values())
    assert worker_ratio_count >= required_comparisons, (
        "All within-language SequenceMatcher.ratio comparisons must be performed by parallel workers; "
        f"observed {worker_ratio_count}, expected at least {required_comparisons}"
    )


def test_db_exists():
    assert os.path.exists(DB_PATH), f"Database not found at {DB_PATH}"


def test_json_exists():
    assert os.path.exists(JSON_PATH), f"Summary JSON not found at {JSON_PATH}"


def test_long_products_table():
    conn = sqlite3.connect(DB_PATH)
    try:
        c = conn.cursor()
        c.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='long_products'")
        assert c.fetchone() is not None, "Table 'long_products' does not exist in the database."

        c.execute("PRAGMA table_info(long_products)")
        schema = [(row[1], row[2].upper()) for row in c.fetchall()]
        assert schema == [
            ("vendor_id", "TEXT"),
            ("language", "TEXT"),
            ("product_name", "TEXT"),
            ("description", "TEXT"),
        ], f"Incorrect long_products schema: {schema}"

        c.execute("SELECT COUNT(*) FROM long_products")
        long_count = c.fetchone()[0]
        assert long_count == 300, f"Expected 300 long products, got {long_count}"

        c.execute("SELECT vendor_id, language, product_name, description FROM long_products")
        actual = Counter(c.fetchall())
        expected = Counter(read_raw_long_products()[0])
        assert actual == expected, "long_products does not exactly match the wide-to-long transformation"
    finally:
        conn.close()


def test_similar_pairs_table_and_json():
    conn = sqlite3.connect(DB_PATH)
    try:
        c = conn.cursor()
        c.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='similar_pairs'")
        assert c.fetchone() is not None, "Table 'similar_pairs' does not exist in the database."

        c.execute("PRAGMA table_info(similar_pairs)")
        schema = [(row[1], row[2].upper()) for row in c.fetchall()]
        assert schema == [
            ("vendor_id_1", "TEXT"),
            ("vendor_id_2", "TEXT"),
            ("language", "TEXT"),
            ("similarity_score", "REAL"),
        ], f"Incorrect similar_pairs schema: {schema}"

        with open(JSON_PATH, "r", encoding="utf-8") as f:
            try:
                summary = json.load(f)
            except json.JSONDecodeError:
                pytest.fail("Summary JSON is not valid JSON.")

        assert isinstance(summary, dict), "Summary JSON must be an object"
        assert set(summary) == set(LANGUAGES), "Summary JSON must contain exactly en, fr, and es"
        for lang in LANGUAGES:
            c.execute("SELECT COUNT(*) FROM similar_pairs WHERE language=?", (lang,))
            db_count = c.fetchone()[0]
            json_count = summary.get(lang)
            assert json_count is not None, f"Language '{lang}' missing from JSON summary."
            assert isinstance(json_count, int) and not isinstance(json_count, bool), f"Count for {lang} must be an integer"
            assert json_count == db_count, f"Mismatch in {lang} pairs: JSON says {json_count}, DB says {db_count}"
    finally:
        conn.close()


def test_similar_pairs_correctness():
    assert os.path.exists(RAW_DATA_PATH), f"Raw data file not found at {RAW_DATA_PATH}"
    expected = expected_pairs()

    conn = sqlite3.connect(DB_PATH)
    try:
        c = conn.cursor()
        c.execute("SELECT vendor_id_1, vendor_id_2, language, similarity_score FROM similar_pairs")
        all_rows = c.fetchall()

        assert all(row[2] in LANGUAGES for row in all_rows), "similar_pairs contains an unsupported language"
        assert all(row[0] < row[1] for row in all_rows), "Every pair must satisfy vendor_id_1 < vendor_id_2"

        keys = [(row[0], row[1], row[2]) for row in all_rows]
        assert len(keys) == len(set(keys)), "similar_pairs contains duplicate pair rows"

        expected_total = sum(len(expected[lang]) for lang in LANGUAGES)
        assert len(all_rows) == expected_total, f"Expected {expected_total} pair rows, got {len(all_rows)}"

        for lang in LANGUAGES:
            c.execute("SELECT vendor_id_1, vendor_id_2 FROM similar_pairs WHERE language=?", (lang,))
            db_pairs = set()
            for row in c.fetchall():
                v1, v2 = row[0], row[1]
                if v1 > v2:
                    v1, v2 = v2, v1
                db_pairs.add((v1, v2))
            expected_pair_set = set(expected[lang])
            assert db_pairs == expected_pair_set, (
                f"Mismatch in similar pairs for language '{lang}'. "
                f"Expected {len(expected_pair_set)} pairs, got {len(db_pairs)} pairs. "
                f"Expected pairs: {expected_pair_set}, DB pairs: {db_pairs}"
            )

        for v1, v2, lang, score in all_rows:
            assert isinstance(score, (int, float)) and not isinstance(score, bool), "similarity_score must be numeric"
            expected_score = expected[lang][(v1, v2)]
            assert math.isclose(float(score), expected_score, rel_tol=0.0, abs_tol=1e-12), (
                f"Incorrect similarity_score for {(v1, v2, lang)}: expected {expected_score}, got {score}"
            )
            assert float(score) >= 0.85, "similar_pairs contains a score below the threshold"
    finally:
        conn.close()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
