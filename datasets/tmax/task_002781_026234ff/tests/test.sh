#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import string
import subprocess
import pytest

FILTER_BIN = "/home/user/filter"
FILTER_SOURCE = "/home/user/filter.c"
ORACLE_BIN = "/app/query_oracle"
CLEAN_CORPUS_DIR = "/app/corpus/clean"
EVIL_CORPUS_DIR = "/app/corpus/evil"
RNG = random.SystemRandom()


def ident(prefix="obj"):
    return prefix + "_" + "".join(RNG.choice(string.ascii_lowercase) for _ in range(12))


def mixed_case(word):
    return "".join(ch.upper() if RNG.randrange(2) else ch.lower() for ch in word)


def run_program(binary, sql):
    return subprocess.run(
        [binary],
        input=sql,
        capture_output=True,
        text=True,
        timeout=2,
    )


def assert_filter(sql, expected):
    result = run_program(FILTER_BIN, sql)
    assert result.returncode == 0, (
        f"filter exited with {result.returncode} for query {sql!r}; "
        f"stderr={result.stderr!r}"
    )
    assert result.stdout == expected + "\n", (
        f"query {sql!r}: expected exactly {expected!r} followed by a newline, "
        f"got stdout={result.stdout!r}, stderr={result.stderr!r}"
    )


def test_filter_artifacts_exist_and_are_correct_types():
    assert os.path.exists(FILTER_SOURCE), f"Missing required source: {FILTER_SOURCE}"
    assert os.path.isfile(FILTER_SOURCE), f"Expected {FILTER_SOURCE} to be a file"
    assert os.path.getsize(FILTER_SOURCE) > 0, f"Expected nonempty C source: {FILTER_SOURCE}"

    assert os.path.exists(FILTER_BIN), f"Missing required executable: {FILTER_BIN}"
    assert os.path.isfile(FILTER_BIN), f"Expected {FILTER_BIN} to be a file"
    assert os.access(FILTER_BIN, os.X_OK), f"Expected {FILTER_BIN} to be executable"
    with open(FILTER_BIN, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"Expected {FILTER_BIN} to be a compiled ELF executable"


def run_filter_on_file(file_path):
    try:
        with open(file_path, "r") as f:
            result = subprocess.run(
                [FILTER_BIN], stdin=f, capture_output=True, text=True, timeout=2
            )
        if result.returncode != 0:
            return f"ERROR: exit {result.returncode}: {result.stderr}"
        return result.stdout.strip()
    except Exception as e:
        return f"ERROR: {str(e)}"


def test_clean_corpus_accepted():
    if not os.path.exists(CLEAN_CORPUS_DIR):
        pytest.fail(f"Clean corpus directory missing: {CLEAN_CORPUS_DIR}")
    files = [f for f in os.listdir(CLEAN_CORPUS_DIR)
             if os.path.isfile(os.path.join(CLEAN_CORPUS_DIR, f))]
    if not files:
        pytest.fail(f"No files found in clean corpus directory: {CLEAN_CORPUS_DIR}")

    failed_files = []
    for filename in files:
        output = run_filter_on_file(os.path.join(CLEAN_CORPUS_DIR, filename))
        if output != "ACCEPT":
            failed_files.append((filename, output))
    if failed_files:
        pytest.fail(f"{len(failed_files)} of {len(files)} clean files rejected: {failed_files[:10]}")


def test_evil_corpus_rejected():
    if not os.path.exists(EVIL_CORPUS_DIR):
        pytest.fail(f"Evil corpus directory missing: {EVIL_CORPUS_DIR}")
    files = [f for f in os.listdir(EVIL_CORPUS_DIR)
             if os.path.isfile(os.path.join(EVIL_CORPUS_DIR, f))]
    if not files:
        pytest.fail(f"No files found in evil corpus directory: {EVIL_CORPUS_DIR}")

    failed_files = []
    for filename in files:
        output = run_filter_on_file(os.path.join(EVIL_CORPUS_DIR, filename))
        if output != "REJECT":
            failed_files.append((filename, output))
    if failed_files:
        pytest.fail(f"{len(failed_files)} of {len(files)} evil files bypassed: {failed_files[:10]}")


def test_randomized_cartesian_bombs_and_safe_exceptions():
    separators = [" ", "  ", "\t", "\n", "\n    "]
    for _ in range(16):
        left, right = ident("left"), ident("right")
        a, b = ident("a"), ident("b")
        cross = mixed_case("cross") + RNG.choice(separators) + mixed_case("join")
        select = mixed_case("select")
        from_kw = mixed_case("from")

        # Explicit and implicit Cartesian products without WHERE or LIMIT are bombs.
        assert_filter(f"{select} *\n{from_kw} {left} {a}\n{cross}\n{right} {b};", "REJECT")
        assert_filter(f"{select} * {from_kw}\n  {left} {a} ,\n  {right} {b};", "REJECT")

        # The same join forms are permitted when bounded by WHERE or LIMIT.
        assert_filter(
            f"{select} * {from_kw} {left} {a} {cross} {right} {b}\n"
            f"{mixed_case('where')} {a}.id = {b}.id;",
            "ACCEPT",
        )
        assert_filter(
            f"{select} * {from_kw} {left} {a} {cross} {right} {b}\n"
            f"{mixed_case('limit')} {RNG.randint(1, 100)};",
            "ACCEPT",
        )
        assert_filter(
            f"{select} * {from_kw} {left} {a}, {right} {b}\n"
            f"{mixed_case('where')} {a}.key = {b}.key;",
            "ACCEPT",
        )
        assert_filter(
            f"{select} * {from_kw} {left} {a}, {right} {b}\n"
            f"{mixed_case('limit')} {RNG.randint(1, 100)};",
            "ACCEPT",
        )


def recursive_query(depth):
    query = f"SELECT {RNG.randint(1, 999)} AS n"
    for level in range(depth):
        cte = ident(f"cte{level}")
        alias = ident(f"sub{level}")
        query = (
            f"{mixed_case('with')}\n  {mixed_case('recursive')} {cte}(n) AS "
            f"(SELECT 1)\nSELECT * FROM (\n{query}\n) {alias}"
        )
    return query + ";"


def test_recursive_cte_depth_boundary_with_random_formatting():
    for depth in (1, 2, 3):
        assert_filter(recursive_query(depth), "ACCEPT")
    for depth in (4, 5, 6):
        assert_filter(recursive_query(depth), "REJECT")


def test_valid_complex_queries_and_non_join_commas_are_accepted():
    t1, t2 = ident("events"), ident("users")
    valid_queries = [
        f"""SELECT e.user_id, e.value,
ROW_NUMBER() OVER (PARTITION BY e.user_id ORDER BY e.created_at, e.value) AS rn
FROM {t1} e INNER JOIN {t2} u ON e.user_id = u.id
WHERE e.value > 0;""",
        f"SELECT COALESCE(x.a, x.b), x.c FROM {t1} x LIMIT 25;",
        f"""WITH RECURSIVE first_cte(n) AS (SELECT 1),
second_cte(n) AS (SELECT n + 1 FROM first_cte WHERE n < 5)
SELECT n FROM second_cte;""",
        "MATCH (p:Person)-[:KNOWS]->(q:Person) RETURN p, q;",
        f"SELECT a.id, b.id FROM {t1} a LEFT OUTER JOIN {t2} b ON a.id = b.id;",
    ]
    for query in valid_queries:
        assert_filter(query, "ACCEPT")


def test_oracle_standard_unsafe_syntax_is_still_rejected():
    assert os.path.isfile(ORACLE_BIN) and os.access(ORACLE_BIN, os.X_OK)
    unsafe_queries = [
        f"DROP TABLE {ident('table')};",
        f"DELETE FROM {ident('table')} WHERE id = {RNG.randint(1, 9999)};",
    ]
    for query in unsafe_queries:
        oracle = run_program(ORACLE_BIN, query)
        assert oracle.returncode == 0
        assert oracle.stdout == "UNSAFE\n", "test input must be rejected by the shipped oracle"
        assert_filter(query, "REJECT")
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
