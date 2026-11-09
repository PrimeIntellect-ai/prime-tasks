#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import shutil
import subprocess
import tempfile
from dataclasses import dataclass

import pytest

SCRIPT_PATH = "/home/user/query_validator.py"
CLEAN_CORPUS_DIR = "/app/corpus/clean/"
EVIL_CORPUS_DIR = "/app/corpus/evil/"


def test_script_exists():
    """Ensure the user created the query_validator.py script."""
    assert os.path.isfile(SCRIPT_PATH), f"The script {SCRIPT_PATH} does not exist."


def test_clean_corpus():
    """Ensure all clean queries are accepted with exactly 'CLEAN' and exit code 0."""
    assert os.path.isfile(SCRIPT_PATH), f"The script {SCRIPT_PATH} does not exist."
    clean_files = [f for f in os.listdir(CLEAN_CORPUS_DIR) if os.path.isfile(os.path.join(CLEAN_CORPUS_DIR, f))]

    failed_files = []

    for f in clean_files:
        path = os.path.join(CLEAN_CORPUS_DIR, f)
        result = subprocess.run(["python3", SCRIPT_PATH, path], capture_output=True, text=True)
        output = result.stdout.strip()

        if result.returncode != 0 or output != "CLEAN":
            failed_files.append((f, result.returncode, output))

    if failed_files:
        error_msg = f"{len(failed_files)} of {len(clean_files)} clean modified (rejected or failed). Offending files: "
        error_msg += ", ".join([f"{f} (code: {c}, out: {o})" for f, c, o in failed_files])
        pytest.fail(error_msg)


def test_evil_corpus():
    """Ensure all evil queries are rejected with exactly 'EVIL' and exit code 1."""
    assert os.path.isfile(SCRIPT_PATH), f"The script {SCRIPT_PATH} does not exist."
    evil_files = [f for f in os.listdir(EVIL_CORPUS_DIR) if os.path.isfile(os.path.join(EVIL_CORPUS_DIR, f))]

    failed_files = []

    for f in evil_files:
        path = os.path.join(EVIL_CORPUS_DIR, f)
        result = subprocess.run(["python3", SCRIPT_PATH, path], capture_output=True, text=True)
        output = result.stdout.strip()

        if result.returncode != 1 or output != "EVIL":
            failed_files.append((f, result.returncode, output))

    if failed_files:
        error_msg = f"{len(failed_files)} of {len(evil_files)} evil bypassed (accepted or failed incorrectly). Offending files: "
        error_msg += ", ".join([f"{f} (code: {c}, out: {o})" for f, c, o in failed_files])
        pytest.fail(error_msg)


@dataclass
class QueryModel:
    sql: str
    tables: frozenset
    has_department_id_match: bool = False
    limit: object = None


def expected_result(model):
    """Evaluate the stakeholder rules from the generated query's semantic model."""
    evil_join = {"employees", "departments"}.issubset(model.tables) and not model.has_department_id_match
    evil_logs = "logs" in model.tables and (model.limit is None or model.limit > 1000)
    return ("EVIL", 1) if evil_join or evil_logs else ("CLEAN", 0)


def test_generated_queries_are_classified_by_semantics():
    """Exercise randomized paths and queries whose answers come from a semantic model."""
    assert os.path.isfile(SCRIPT_PATH), f"The script {SCRIPT_PATH} does not exist."
    rng = random.SystemRandom()

    def word(value):
        return value.upper() if rng.choice([True, False]) else value.lower()

    def gap():
        return rng.choice([" ", "  ", "\n", "\t"])

    def alias():
        return "a" + secrets.token_hex(2)

    models = []
    for i in range(6):
        ws = gap()
        models.append(QueryModel(
            f"{word('select')}{ws}*{ws}{word('from')}{ws}{word('other_table')};",
            frozenset({"other_table"}),
        ))

        safe_limit = 1000 if i == 0 else rng.randint(1, 999)
        models.append(QueryModel(
            f"{word('select')}{ws}*{ws}{word('from')}{ws}{word('logs')}{ws}{word('limit')}{ws}{safe_limit};",
            frozenset({"logs"}), limit=safe_limit,
        ))

        high_limit = rng.randint(1001, 9000)
        models.append(QueryModel(
            f"{word('select')}{ws}*{ws}{word('from')}{ws}{word('logs')}{ws}{word('limit')}{ws}{high_limit};",
            frozenset({"logs"}), limit=high_limit,
        ))
        models.append(QueryModel(
            f"{word('select')}{ws}*{ws}{word('from')}{ws}{word('logs')};",
            frozenset({"logs"}), limit=None,
        ))

        e, d = alias(), alias()
        models.append(QueryModel(
            f"{word('select')} * {word('from')} {word('employees')} {e} "
            f"{word('join')} {word('departments')} {d} {word('on')} "
            f"{e}.department_id{ws}={ws}{d}.department_id;",
            frozenset({"employees", "departments"}), has_department_id_match=True,
        ))

        e, d = alias(), alias()
        models.append(QueryModel(
            f"{word('select')} * {word('from')} {word('employees')} {e}, "
            f"{word('departments')} {d} {word('where')} "
            f"{d}.department_id{ws}={ws}{e}.department_id;",
            frozenset({"employees", "departments"}), has_department_id_match=True,
        ))

        e, d = alias(), alias()
        bad_style = i % 3
        if bad_style == 0:
            sql = f"{word('select')} * {word('from')} {word('employees')} {e}, {word('departments')} {d};"
        elif bad_style == 1:
            sql = f"{word('select')} * {word('from')} {word('employees')} {e} {word('cross')} {word('join')} {word('departments')} {d};"
        else:
            sql = (f"{word('select')} * {word('from')} {word('employees')} {e} "
                   f"{word('join')} {word('departments')} {d} {word('on')} "
                   f"{e}.employee_id{ws}={ws}{d}.department_id;")
        models.append(QueryModel(
            sql,
            frozenset({"employees", "departments"}), has_department_id_match=False,
        ))

    rng.shuffle(models)
    query_dir = tempfile.mkdtemp(prefix=secrets.token_hex(8) + "_", dir="/tmp")
    failures = []
    try:
        for model in models:
            filename = secrets.token_hex(12) + ".sql"
            path = os.path.join(query_dir, filename)
            with open(path, "w", encoding="utf-8") as handle:
                handle.write(model.sql)

            expected_output, expected_code = expected_result(model)
            try:
                result = subprocess.run(
                    ["python3", SCRIPT_PATH, path],
                    capture_output=True,
                    text=True,
                    timeout=10,
                )
                output = result.stdout.strip()
                if result.returncode != expected_code or output != expected_output:
                    failures.append((model.sql, expected_code, expected_output, result.returncode, output))
            except subprocess.TimeoutExpired:
                failures.append((model.sql, expected_code, expected_output, "timeout", ""))
    finally:
        shutil.rmtree(query_dir, ignore_errors=True)

    if failures:
        details = "\n".join(
            f"SQL: {sql!r}; expected code/out {ec}/{eo}, got {ac}/{ao!r}"
            for sql, ec, eo, ac, ao in failures[:10]
        )
        pytest.fail(f"{len(failures)} generated semantic cases failed:\n{details}")
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
