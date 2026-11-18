#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/test_final_state.py
import json
import os
import shutil
import sqlite3
import subprocess
import tempfile

DB_PATH = "/home/user/graph_data.db"
RESULTS_PATH = "/home/user/motif_results.json"


def assert_database_contents():
    assert os.path.isfile(DB_PATH), f"Database file {DB_PATH} does not exist."
    conn = sqlite3.connect(DB_PATH)
    try:
        schema = {
            row[0]: row[1]
            for row in conn.execute(
                "SELECT name, sql FROM sqlite_master WHERE type='table' AND name IN ('nodes','relations')"
            )
        }
        assert set(schema) == {"nodes", "relations"}, "Required tables are missing."

        node_columns = [(r[1], r[2].upper()) for r in conn.execute("PRAGMA table_info(nodes)")]
        relation_columns = [(r[1], r[2].upper()) for r in conn.execute("PRAGMA table_info(relations)")]
        assert node_columns == [("id", "INT"), ("label", "TEXT"), ("property", "TEXT")], "The nodes schema was changed."
        assert relation_columns == [("src", "INT"), ("dst", "INT"), ("type", "TEXT")], "The relations schema was changed."

        nodes = conn.execute("SELECT id, label, property FROM nodes ORDER BY id").fetchall()
        expected_nodes = [
            (i, f"Node_{i}", "target" if i in {10, 20, 30, 40, 50, 60} else "background")
            for i in range(1, 1001)
        ]
        assert nodes == expected_nodes, "The original nodes data was modified."

        relations = conn.execute("SELECT src, dst, type FROM relations").fetchall()
        assert 2800 <= len(relations) <= 3010, "The original relations data was deleted or replaced."
        assert len(relations) == len(set(relations)), "Duplicate relations were introduced."
        assert all(
            isinstance(src, int) and isinstance(dst, int)
            and 1 <= src <= 1000 and 1 <= dst <= 1000
            and src != dst and edge_type == "interaction"
            for src, dst, edge_type in relations
        ), "The relations data no longer has the generated dataset's structure."

        required_edges = {
            (10, 20, "interaction"), (20, 30, "interaction"), (10, 30, "interaction"),
            (10, 40, "interaction"), (40, 50, "interaction"), (10, 50, "interaction"),
            (20, 40, "interaction"), (40, 30, "interaction"),
            (50, 60, "interaction"), (60, 10, "interaction"),
        }
        assert required_edges.issubset(set(relations)), "Required original relations were removed."
        return tuple(nodes), tuple(sorted(relations))
    finally:
        conn.close()


def user_indexes(conn):
    return conn.execute(
        "SELECT name, tbl_name FROM sqlite_master "
        "WHERE type='index' AND name NOT LIKE 'sqlite_autoindex%'"
    ).fetchall()


def index_columns(conn, name):
    escaped = name.replace("'", "''")
    return tuple(row[2] for row in conn.execute(f"PRAGMA index_info('{escaped}')") ORDER BY row[0])


def assert_indexes_created():
    conn = sqlite3.connect(DB_PATH)
    try:
        indexes = user_indexes(conn)
        assert len(indexes) > 0, "No indexes were created on the database."
        tables_with_indexes = {table for _, table in indexes}
        assert "nodes" in tables_with_indexes or "relations" in tables_with_indexes, \
            "Indexes must be created on 'nodes' or 'relations' tables."

        node_indexes = [index_columns(conn, name) for name, table in indexes if table == "nodes"]
        relation_indexes = [index_columns(conn, name) for name, table in indexes if table == "relations"]
        assert any(len(cols) >= 2 and set(cols[:2]) == {"id", "property"} for cols in node_indexes), \
            "Create a composite index on nodes using id and property."
        assert any(len(cols) >= 2 and cols[:2] == ("src", "dst") for cols in relation_indexes), \
            "Create a composite index on relations beginning with src, dst."
    finally:
        conn.close()


def get_expected_motifs():
    conn = sqlite3.connect(DB_PATH)
    try:
        rows = conn.execute("""
            SELECT r1.src, r1.dst, r2.dst
            FROM relations r1
            JOIN relations r2 ON r1.dst = r2.src
            JOIN relations r3 ON r1.src = r3.src AND r2.dst = r3.dst
            JOIN nodes n1 ON r1.src = n1.id
            JOIN nodes n2 ON r1.dst = n2.id
            JOIN nodes n3 ON r2.dst = n3.id
            WHERE n1.property = 'target'
              AND n2.property = 'target'
              AND n3.property = 'target'
        """).fetchall()
        return sorted([list(row) for row in rows])
    finally:
        conn.close()


def script_commands(path):
    ext = os.path.splitext(path)[1].lower()
    if ext == ".py":
        return [["python3", path]]
    if ext == ".sh":
        return [["bash", path]]
    if ext == ".rb":
        return [["ruby", path]] if shutil.which("ruby") else []
    if ext == ".pl":
        return [["perl", path]] if shutil.which("perl") else []

    try:
        with open(path, "rb") as f:
            first = f.readline(256).decode("utf-8", "ignore").lower()
    except OSError:
        return []
    if first.startswith("#!"):
        if "python" in first:
            return [["python3", path]]
        if "bash" in first or first.rstrip().endswith("/sh"):
            return [["bash", path]]
        if "ruby" in first and shutil.which("ruby"):
            return [["ruby", path]]
        if "perl" in first and shutil.which("perl"):
            return [["perl", path]]
    return []


def find_scripts():
    scripts = []
    for root, dirs, files in os.walk("/home/user"):
        dirs[:] = [d for d in dirs if d not in {"__pycache__", ".cache"}]
        for filename in files:
            path = os.path.join(root, filename)
            if path in {DB_PATH, RESULTS_PATH} or not os.path.isfile(path):
                continue
            commands = script_commands(path)
            if commands:
                scripts.append((path, commands))
    return sorted(scripts)


def load_results():
    assert os.path.isfile(RESULTS_PATH), f"Results file {RESULTS_PATH} does not exist."
    try:
        with open(RESULTS_PATH, "r", encoding="utf-8") as f:
            result = json.load(f)
    except json.JSONDecodeError as exc:
        raise AssertionError(f"File {RESULTS_PATH} is not valid JSON: {exc}")
    assert isinstance(result, list), "Output must be a JSON array."
    return result


def main():
    original_signature = assert_database_contents()
    assert_indexes_created()
    expected = get_expected_motifs()

    scripts = find_scripts()
    assert scripts, "No Python, Bash, Ruby, or Perl solution script was found under /home/user."

    fd, backup_path = tempfile.mkstemp(prefix="graph_data_backup_", suffix=".db")
    os.close(fd)
    shutil.copyfile(DB_PATH, backup_path)
    success = False
    errors = []
    try:
        for path, commands in scripts:
            for command in commands:
                if os.path.exists(RESULTS_PATH):
                    os.remove(RESULTS_PATH)
                try:
                    proc = subprocess.run(
                        command, cwd=os.path.dirname(path) or "/home/user",
                        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                        text=True, timeout=30
                    )
                    unchanged = assert_database_contents() == original_signature
                    if proc.returncode == 0 and unchanged and os.path.exists(RESULTS_PATH):
                        student_results = load_results()
                        if student_results == expected:
                            assert_indexes_created()
                            success = True
                            break
                    errors.append(f"{path} did not generate the correct result without modifying source data")
                except Exception as exc:
                    errors.append(f"{path}: {exc}")
                finally:
                    if not success:
                        shutil.copyfile(backup_path, DB_PATH)
            if success:
                break
    finally:
        if os.path.exists(backup_path):
            os.remove(backup_path)

    assert success, "No submitted script produced the required output when executed. " + "; ".join(errors[:5])
    student_results = load_results()
    assert student_results == expected, f"Expected motifs {expected}, but got {student_results}."


if __name__ == "__main__":
    main()
PY_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
