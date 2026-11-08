#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import re
import sqlite3
import stat
import subprocess
from collections import Counter

import pytest

SCRIPT = "/home/user/find_conflicts.sh"
DB = "/home/user/graph.db"
OUTPUT = "/home/user/conflicts.csv"
PLAN = "/home/user/plan.txt"
DATA = "/home/user/data"


def read_source(name):
    with open(os.path.join(DATA, name), newline="", encoding="utf-8") as f:
        return list(csv.DictReader(f))


# Read the supplied inputs before executing the submission.
SOURCE = {
    "persons": read_source("persons.csv"),
    "companies": read_source("companies.csv"),
    "board_members": read_source("board_members.csv"),
    "investments": read_source("investments.csv"),
}


def expected_conflicts():
    persons = {row["id"]: row["name"] for row in SOURCE["persons"]}
    companies = {row["id"]: row["name"] for row in SOURCE["companies"]}
    memberships = set(
        (row["person_id"], row["company_id"])
        for row in SOURCE["board_members"]
    )
    people_by_company = {}
    for person_id, company_id in memberships:
        people_by_company.setdefault(company_id, set()).add(person_id)

    result = []
    # Each investment CSV row participates in the relational join, including
    # separate rows for the same company pair if their amounts differ.
    for investment in SOURCE["investments"]:
        investor = investment["investor_company_id"]
        target = investment["target_company_id"]
        people = people_by_company.get(investor, set()) & people_by_company.get(target, set())
        for person_id in people:
            result.append([
                persons[person_id],
                companies[investor],
                companies[target],
            ])
    return sorted(result)


EXPECTED = expected_conflicts()


@pytest.fixture(scope="session", autouse=True)
def execute_submission():
    assert os.path.isfile(SCRIPT), f"Script {SCRIPT} does not exist."
    assert os.access(SCRIPT, os.X_OK), f"Script {SCRIPT} is not executable."

    for path in (DB, OUTPUT, PLAN):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    # Interpose sqlite3 while the script runs so the verifier can confirm that
    # EXPLAIN QUERY PLAN was actually submitted to sqlite3 rather than merely
    # fabricating plan.txt.
    sqlite_path = "/usr/bin/sqlite3"
    real_sqlite = "/usr/bin/sqlite3.verifier-real"
    invocation_log = "/tmp/sqlite3-verifier-invocations"
    try:
        os.remove(invocation_log)
    except FileNotFoundError:
        pass

    os.replace(sqlite_path, real_sqlite)
    wrapper = r'''#!/bin/bash
set -e
input=$(mktemp)
trap 'rm -f "$input"' EXIT
cat > "$input"
{
  printf '\n--- SQLITE3 INVOCATION ---\n'
  printf 'ARG: %s\n' "$@"
  printf '%s\n' '--- STDIN ---'
  cat "$input"
} >> /tmp/sqlite3-verifier-invocations
exec /usr/bin/sqlite3.verifier-real "$@" < "$input"
'''
    try:
        with open(sqlite_path, "w", encoding="utf-8") as f:
            f.write(wrapper)
        os.chmod(sqlite_path, stat.S_IRUSR | stat.S_IWUSR | stat.S_IXUSR |
                              stat.S_IRGRP | stat.S_IXGRP |
                              stat.S_IROTH | stat.S_IXOTH)
        completed = subprocess.run(
            [SCRIPT],
            cwd="/home/user",
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=60,
        )
    finally:
        try:
            os.remove(sqlite_path)
        except FileNotFoundError:
            pass
        os.replace(real_sqlite, sqlite_path)

    assert completed.returncode == 0, (
        f"find_conflicts.sh failed with exit status {completed.returncode}.\n"
        f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
    )
    assert os.path.isfile(invocation_log), "The script did not invoke sqlite3."
    with open(invocation_log, "r", encoding="utf-8", errors="replace") as f:
        sqlite_commands = f.read()
    assert re.search(r"\bEXPLAIN\s+QUERY\s+PLAN\b", sqlite_commands, re.I), (
        "The executed sqlite3 commands did not contain EXPLAIN QUERY PLAN."
    )


def test_script_exists_and_executable():
    assert os.path.isfile(SCRIPT), f"Script {SCRIPT} does not exist."
    assert os.access(SCRIPT, os.X_OK), f"Script {SCRIPT} is not executable."


def test_database_exists_and_contains_imported_data():
    assert os.path.isfile(DB), f"Database {DB} does not exist."

    expected_columns = {
        "persons": ["id", "name"],
        "companies": ["id", "name"],
        "board_members": ["person_id", "company_id"],
        "investments": ["investor_company_id", "target_company_id", "amount"],
    }
    con = sqlite3.connect(DB)
    try:
        for table, columns in expected_columns.items():
            actual_columns = [row[1] for row in con.execute(f'PRAGMA table_info("{table}")')]
            assert actual_columns == columns, (
                f"Table {table} has columns {actual_columns}, expected {columns}."
            )
            actual_rows = Counter(
                tuple("" if value is None else str(value) for value in row)
                for row in con.execute(
                    f'SELECT {", ".join(chr(34) + c + chr(34) for c in columns)} FROM "{table}"'
                )
            )
            source_rows = Counter(tuple(row[c] for c in columns) for row in SOURCE[table])
            assert actual_rows == source_rows, f"Table {table} was not imported completely and accurately."
    finally:
        con.close()


def test_conflicts_csv_output():
    assert os.path.isfile(OUTPUT), f"Output file {OUTPUT} does not exist."
    with open(OUTPUT, "r", encoding="utf-8", newline="") as f:
        reader = csv.reader(f)
        try:
            header = next(reader)
        except StopIteration:
            pytest.fail("conflicts.csv is empty.")
        rows = list(reader)

    expected_header = ["person_name", "investor_company_name", "target_company_name"]
    assert header == expected_header, f"Header {header} does not match expected {expected_header}."
    assert rows == sorted(rows), (
        "conflicts.csv is not sorted alphabetically by person_name, "
        "investor_company_name, target_company_name."
    )

    known_conflicts = [
        ["Person_10", "Company_E", "Company_J"],
        ["Person_88", "Company_Z33", "Company_L"],
    ]
    for conflict in known_conflicts:
        assert conflict in rows, f"Expected conflict {conflict} not found in conflicts.csv."

    assert rows == EXPECTED, (
        "conflicts.csv is not the complete and exact conflict set derived from the input CSVs."
    )


def relation_indexes(con, table):
    return {
        row[1].upper()
        for row in con.execute(f'PRAGMA index_list("{table}")')
        if row[1]
    }


def classify_searches(plan_text, board_indexes, investment_indexes):
    board = 0
    investments = 0
    for raw_line in plan_text.upper().splitlines():
        if "SEARCH" not in raw_line or "INDEX" not in raw_line:
            continue
        if "BOARD_MEMBERS" in raw_line or any(name in raw_line for name in board_indexes):
            board += 1
        if "INVESTMENTS" in raw_line or any(name in raw_line for name in investment_indexes):
            investments += 1
    return board, investments


def test_query_plan_output_and_actual_index_strategy():
    assert os.path.isfile(PLAN), f"Query plan file {PLAN} does not exist."
    with open(PLAN, "r", encoding="utf-8", errors="replace") as f:
        plan_content = f.read().upper()

    # Preserve the original basic plan assertions, strengthened to require both
    # relation types rather than accepting either one.
    assert "SEARCH" in plan_content and "INDEX" in plan_content, (
        "Query plan does not seem to use index lookups (SEARCH ... USING INDEX)."
    )

    con = sqlite3.connect(DB)
    try:
        board_indexes = relation_indexes(con, "board_members")
        investment_indexes = relation_indexes(con, "investments")
        assert board_indexes, "No index was created for board_members."
        assert investment_indexes, "No index was created for investments."

        board_searches, investment_searches = classify_searches(
            plan_content, board_indexes, investment_indexes
        )
        assert board_searches >= 2, (
            "plan.txt does not show indexed SEARCH access for both board_members joins."
        )
        assert investment_searches >= 1, (
            "plan.txt does not show indexed SEARCH access for the investments join."
        )

        scan_board = plan_content.count("SCAN TABLE BOARD_MEMBERS") + plan_content.count("SCAN BOARD_MEMBERS")
        scan_investments = plan_content.count("SCAN TABLE INVESTMENTS") + plan_content.count("SCAN INVESTMENTS")
        assert scan_board == 0, "Query plan uses a full SCAN of board_members."
        assert scan_investments == 0, "Query plan uses a full SCAN of investments."

        # Independently exercise the installed schema with the required graph
        # query. This prevents a textual plan from passing when the database's
        # real indexes cannot provide the required relation-table lookups.
        canonical_query = """
            SELECT p.name, ca.name, cb.name
            FROM persons AS p
            JOIN board_members AS bm_a ON bm_a.person_id = p.id
            JOIN investments AS inv ON inv.investor_company_id = bm_a.company_id
            JOIN board_members AS bm_b
              ON bm_b.person_id = p.id
             AND bm_b.company_id = inv.target_company_id
            JOIN companies AS ca ON ca.id = inv.investor_company_id
            JOIN companies AS cb ON cb.id = inv.target_company_id
            ORDER BY p.name, ca.name, cb.name
        """
        actual_details = [row[3].upper() for row in con.execute("EXPLAIN QUERY PLAN " + canonical_query)]
        assert not any(re.search(r"\bSCAN\s+BM_A\b|\bSCAN\s+BM_B\b", d) for d in actual_details), (
            "The actual schema causes a full scan of board_members."
        )
        assert not any(re.search(r"\bSCAN\s+INV\b", d) for d in actual_details), (
            "The actual schema causes a full scan of investments."
        )
        assert sum(bool(re.search(r"\bSEARCH\s+BM_A\b|\bSEARCH\s+BM_B\b", d)) for d in actual_details) >= 2, (
            "The actual schema does not provide indexed searches for both board_members joins."
        )
        assert any(re.search(r"\bSEARCH\s+INV\b", d) for d in actual_details), (
            "The actual schema does not provide an indexed search for investments."
        )
    finally:
        con.close()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
