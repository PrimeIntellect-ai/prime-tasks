#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/verify_math_app.py
import ast
import importlib.machinery
import json
import math
import os
import re
import secrets
import shutil
import sqlite3
import subprocess
import sys
import tempfile

APP = "/home/user/math_app"
SETUP_PY = os.path.join(APP, "setup.py")
MIGRATE_PY = os.path.join(APP, "migrate.py")
RUN_PY = os.path.join(APP, "run.py")
DATA_DB = os.path.join(APP, "data.db")
FINAL_JSON = "/home/user/final_data.json"


def run(cmd, timeout=120):
    return subprocess.run(
        cmd, cwd=APP, text=True, stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT, timeout=timeout, check=True
    )


def load_json(path):
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def assert_run_uses_mathcore():
    with open(RUN_PY, "r", encoding="utf-8") as f:
        tree = ast.parse(f.read(), filename=RUN_PY)

    module_aliases = set()
    direct_aliases = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for name in node.names:
                if name.name == "mathcore":
                    module_aliases.add(name.asname or "mathcore")
        elif isinstance(node, ast.ImportFrom) and node.module == "mathcore":
            for name in node.names:
                if name.name == "fast_sqrt":
                    direct_aliases.add(name.asname or "fast_sqrt")

    used = False
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        if isinstance(node.func, ast.Name) and node.func.id in direct_aliases:
            used = True
        if (isinstance(node.func, ast.Attribute)
                and node.func.attr == "fast_sqrt"
                and isinstance(node.func.value, ast.Name)
                and node.func.value.id in module_aliases):
            used = True
    assert used, "run.py must import mathcore and call mathcore.fast_sqrt()."


def verify_original_final_state():
    # Preserve the original setup.py assertion.
    assert os.path.isfile(SETUP_PY), f"{SETUP_PY} is missing."
    with open(SETUP_PY, "r", encoding="utf-8") as f:
        setup_content = f.read()
    assert re.search(r"libraries\s*=\s*\[\s*['\"]m['\"]\s*\]", setup_content), \
        "setup.py does not link the extension against libraries=['m']."

    assert os.path.isfile(MIGRATE_PY), f"{MIGRATE_PY} is missing."
    assert os.path.isfile(RUN_PY), f"{RUN_PY} is missing."

    # Preserve the original database column assertions.
    assert os.path.isfile(DATA_DB), f"{DATA_DB} is missing."
    with sqlite3.connect(DATA_DB) as conn:
        columns = {row[1]: row[2].upper()
                   for row in conn.execute("PRAGMA table_info(calculations)")}
    for name in ("id", "input_val", "result", "algo_version"):
        assert name in columns, f"Column {name!r} missing in calculations table."

    # Preserve the original final JSON assertions.
    assert os.path.isfile(FINAL_JSON), f"{FINAL_JSON} is missing."
    data = load_json(FINAL_JSON)
    assert isinstance(data, list), "JSON root must be a list."
    assert len(data) == 5, f"Expected 5 rows in JSON, got {len(data)}."
    for i, result in enumerate((3.14, 2.71)):
        row = data[i]
        assert row.get("input_val") == 0.0
        assert row.get("result") == result
        assert row.get("algo_version") == "1.0"
    for i, (value, result) in enumerate(zip((16.0, 64.0, 144.0),
                                             (4.0, 8.0, 12.0)), start=2):
        row = data[i]
        assert row.get("input_val") == value
        assert row.get("result") == result
        assert row.get("algo_version") == "2.0"


def verify_artifacts_by_execution():
    assert_run_uses_mathcore()

    backup_dir = tempfile.mkdtemp(prefix="mathapp-verifier-")
    db_backup = os.path.join(backup_dir, "data.db")
    json_backup = os.path.join(backup_dir, "final_data.json")
    shutil.copy2(DATA_DB, db_backup)
    shutil.copy2(FINAL_JSON, json_backup)

    try:
        # Force a genuine fresh extension build rather than accepting a stale artifact.
        shutil.rmtree(os.path.join(APP, "build"), ignore_errors=True)
        for name in os.listdir(APP):
            if name.startswith("mathcore") and any(
                    name.endswith(s) for s in importlib.machinery.EXTENSION_SUFFIXES):
                os.remove(os.path.join(APP, name))
        run([sys.executable, "setup.py", "build_ext", "--inplace"])

        probe = 2.0 + secrets.randbelow(100000) / 1000.0
        code = (
            "import json, mathcore; "
            "print(json.dumps({'file': mathcore.__file__, "
            f"'value': mathcore.fast_sqrt({probe!r})}}))"
        )
        built = json.loads(run([sys.executable, "-c", code]).stdout.strip().splitlines()[-1])
        assert any(built["file"].endswith(s)
                   for s in importlib.machinery.EXTENSION_SUFFIXES), \
            "mathcore was not imported from a compiled extension."
        assert math.isclose(built["value"], math.sqrt(probe), rel_tol=1e-12)

        # Recreate an unpredictable legacy database and execute the submitted migration.
        legacy = [
            (7, secrets.randbelow(1000000) / 10007.0),
            (31, secrets.randbelow(1000000) / 7919.0),
        ]
        os.remove(DATA_DB)
        with sqlite3.connect(DATA_DB) as conn:
            conn.execute("CREATE TABLE calculations (id INTEGER, result REAL)")
            conn.executemany("INSERT INTO calculations VALUES (?, ?)", legacy)
        if os.path.exists(FINAL_JSON):
            os.remove(FINAL_JSON)

        run([sys.executable, MIGRATE_PY])
        with sqlite3.connect(DATA_DB) as conn:
            info = conn.execute("PRAGMA table_info(calculations)").fetchall()
            migrated = conn.execute(
                "SELECT id, input_val, result, algo_version FROM calculations ORDER BY id"
            ).fetchall()
        assert [(r[1], r[2].upper(), r[5]) for r in info] == [
            ("id", "INTEGER", 1),
            ("input_val", "REAL", 0),
            ("result", "REAL", 0),
            ("algo_version", "TEXT", 0),
        ], "Migration did not create the required schema and primary key."
        assert migrated == [(i, 0.0, value, "1.0") for i, value in legacy], \
            "Migration did not preserve and correctly map arbitrary legacy rows."

        # Execute run.py and derive expected output from the seeded DB and math.sqrt.
        run([sys.executable, RUN_PY])
        expected = [
            {"id": i, "input_val": 0.0, "result": value, "algo_version": "1.0"}
            for i, value in legacy
        ]
        next_id = max(i for i, _ in legacy) + 1
        expected += [
            {"id": next_id + offset, "input_val": value,
             "result": math.sqrt(value), "algo_version": "2.0"}
            for offset, value in enumerate((16.0, 64.0, 144.0))
        ]

        with sqlite3.connect(DATA_DB) as conn:
            names = [d[0] for d in conn.execute(
                "SELECT id, input_val, result, algo_version FROM calculations ORDER BY id"
            ).description]
            rows = conn.execute(
                "SELECT id, input_val, result, algo_version FROM calculations ORDER BY id"
            ).fetchall()
        db_data = [dict(zip(names, row)) for row in rows]
        assert db_data == expected, "run.py did not insert the required calculations."
        assert load_json(FINAL_JSON) == expected, \
            "run.py did not dump the ordered database contents to final_data.json."
    finally:
        shutil.copy2(db_backup, DATA_DB)
        shutil.copy2(json_backup, FINAL_JSON)
        shutil.rmtree(backup_dir, ignore_errors=True)


verify_original_final_state()
verify_artifacts_by_execution()
PY_EOF

if python3 /tmp/verify_math_app.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
