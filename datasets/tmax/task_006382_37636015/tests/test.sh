#!/bin/bash
mkdir -p /logs/verifier
status=0

# Restore the supplied inputs so the first execution is checked against the
# task's original dataset and template rather than any pre-created artifacts.
mkdir -p /home/user/remote_staging /home/user/templates
cat > /home/user/remote_staging/raw_data.csv <<'EOF'
ID,Name,Email,Score,Department
1, Alice Smith , ALICE@example.com , 85 , Engineering
2,Bob Jones,bob.jones@example.com,,Sales
3, Charlie Brown, CHARLIE@Example.com, 92,Engineering
4, David , david@example.com, 78 , HR
5, Eve , EVE@test.com , , HR
6, Frank , frank@test.com, 82, Sales
EOF
cat > /home/user/templates/report.tmpl <<'EOF'
# Daily Data Report

Total valid records processed: __TOTAL_RECORDS__

## Average Scores by Department
__DEPT_STATS__

End of Report.
EOF
chmod 644 /home/user/remote_staging/raw_data.csv /home/user/templates/report.tmpl

rm -rf /home/user/local_processing /home/user/db /home/user/reports
rm -f /home/user/cron.conf

# The submitted artifact must actually generate all outputs from a clean state.
timeout 30s runuser -u user -- /home/user/pipeline.sh || status=1

cat > /tmp/test_final_state.py <<'TEST_EOF'
import os
import sqlite3
import re
import stat


def test_pipeline_script_exists_and_executable():
    path = "/home/user/pipeline.sh"
    assert os.path.isfile(path), f"Pipeline script {path} does not exist."
    st = os.stat(path)
    assert bool(st.st_mode & stat.S_IXUSR), f"Pipeline script {path} is not executable."


def test_working_data_copied():
    path = "/home/user/local_processing/working_data.csv"
    assert os.path.isfile(path), f"Working data file {path} does not exist."
    with open(path, "rb") as actual, open("/home/user/remote_staging/raw_data.csv", "rb") as source:
        assert actual.read() == source.read(), "working_data.csv is not an exact copy of the supplied raw CSV."


def test_cleaned_data_correct():
    path = "/home/user/local_processing/cleaned_data.csv"
    assert os.path.isfile(path), f"Cleaned data file {path} does not exist."

    with open(path, 'r') as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(lines) == 5, f"Expected 5 lines (1 header + 4 data rows) in cleaned_data.csv, found {len(lines)}."
    assert lines[0] == "ID,Name,Email,Score,Department", "Header is missing or incorrect in cleaned_data.csv."

    for line in lines[1:]:
        parts = line.split(',')
        assert len(parts) == 5, "Each row must have exactly 5 columns."
        for part in parts:
            assert part == part.strip(), f"Found leading/trailing spaces in field '{part}'."
        email = parts[2]
        assert email == email.lower(), f"Email '{email}' is not strictly lowercase."
        score = parts[3]
        assert score != "", "Score field is completely empty in a row."

    assert lines == [
        "ID,Name,Email,Score,Department",
        "1,Alice Smith,alice@example.com,85,Engineering",
        "3,Charlie Brown,charlie@example.com,92,Engineering",
        "4,David,david@example.com,78,HR",
        "6,Frank,frank@test.com,82,Sales",
    ], "cleaned_data.csv does not exactly derive from the supplied rows."


def test_database_and_table():
    db_path = "/home/user/db/analytics.sqlite"
    assert os.path.isfile(db_path), f"Database file {db_path} does not exist."

    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    cursor.execute("SELECT count(*) FROM employee_stats;")
    count = cursor.fetchone()[0]
    assert count == 4, f"Expected 4 records in employee_stats, found {count}."

    cursor.execute("SELECT email FROM employee_stats WHERE id=1;")
    email = cursor.fetchone()[0]
    assert email == "alice@example.com", f"Expected 'alice@example.com' for id=1, found '{email}'."

    cursor.execute("PRAGMA table_info(employee_stats)")
    schema = [(r[1], r[2].upper()) for r in cursor.fetchall()]
    assert schema == [
        ("id", "INTEGER"), ("name", "TEXT"), ("email", "TEXT"),
        ("score", "INTEGER"), ("department", "TEXT")
    ], f"Incorrect employee_stats schema: {schema}"

    cursor.execute("SELECT id,name,email,score,department FROM employee_stats ORDER BY id")
    assert cursor.fetchall() == [
        (1, "Alice Smith", "alice@example.com", 85, "Engineering"),
        (3, "Charlie Brown", "charlie@example.com", 92, "Engineering"),
        (4, "David", "david@example.com", 78, "HR"),
        (6, "Frank", "frank@test.com", 82, "Sales"),
    ], "Database rows do not exactly match the cleaned CSV."
    conn.close()


def test_final_report():
    path = "/home/user/reports/final_report.md"
    assert os.path.isfile(path), f"Report file {path} does not exist."

    with open(path, 'r') as f:
        content = f.read()

    assert "Total valid records processed: 4" in content, "Report does not contain the correct total record count."
    assert re.search(r"Engineering:\s*88\.5", content), "Report does not contain correct Engineering average (88.5)."
    assert re.search(r"HR:\s*78(?:\.0)?", content), "Report does not contain correct HR average (78 or 78.0)."
    assert re.search(r"Sales:\s*82(?:\.0)?", content), "Report does not contain correct Sales average (82 or 82.0)."
    assert "__TOTAL_RECORDS__" not in content and "__DEPT_STATS__" not in content
    pattern = (r"\A# Daily Data Report\n\nTotal valid records processed: 4\n\n"
               r"## Average Scores by Department\nEngineering: 88\.5\n"
               r"HR: 78(?:\.0)?\nSales: 82(?:\.0)?\n\nEnd of Report\.\n?\Z")
    assert re.fullmatch(pattern, content), "Report was not correctly generated from the supplied template in sorted order."


def test_cron_conf():
    path = "/home/user/cron.conf"
    assert os.path.isfile(path), f"Cron config file {path} does not exist."

    with open(path, 'r') as f:
        content = f.read().strip()

    assert "30 3 * * * /home/user/pipeline.sh" in content, "cron.conf does not contain the correct schedule."
TEST_EOF

python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1 || status=1

# Exercise the pipeline again with verifier-generated inputs and a distinct
# template. This prevents fixed outputs from satisfying the checks.
if python3 - <<'PY'
import json
import secrets
from pathlib import Path

token = secrets.token_hex(5)
alpha = "Alpha" + token
zeta = "Zeta" + token
raw = f"""ID,Name,Email,Score,Department
101, Ada {token} , ADA.{token}@EXAMPLE.COM , 80 , {zeta}
102, Ben {token} , BEN.{token}@EXAMPLE.COM ,   , {alpha}
103, Cara {token} , CARA.{token}@Example.Com, 90,{zeta}
104, Dan {token} , DAN.{token}@TEST.COM, 75 , {alpha}
105, Eve {token} , EVE.{token}@TEST.COM, , {alpha}
106, Finn {token} , FINN.{token}@TEST.COM , 76, {alpha}
"""
template = f"""BEGIN-{token}
Count=__TOTAL_RECORDS__
STATS-BEGIN
__DEPT_STATS__
STATS-END
END-{token}
"""
Path("/home/user/remote_staging/raw_data.csv").write_text(raw)
Path("/home/user/templates/report.tmpl").write_text(template)
expected = {
    "token": token,
    "alpha": alpha,
    "zeta": zeta,
    "cleaned": [
        "ID,Name,Email,Score,Department",
        f"101,Ada {token},ada.{token}@example.com,80,{zeta}",
        f"103,Cara {token},cara.{token}@example.com,90,{zeta}",
        f"104,Dan {token},dan.{token}@test.com,75,{alpha}",
        f"106,Finn {token},finn.{token}@test.com,76,{alpha}",
    ],
}
Path("/tmp/dynamic_expected.json").write_text(json.dumps(expected))
PY
then
    chmod 644 /home/user/remote_staging/raw_data.csv /home/user/templates/report.tmpl
    rm -rf /home/user/local_processing /home/user/db /home/user/reports
    rm -f /home/user/cron.conf
    timeout 30s runuser -u user -- /home/user/pipeline.sh || status=1
else
    status=1
fi

cat > /tmp/test_dynamic_pipeline.py <<'PYTEST'
import json
import re
import sqlite3
from pathlib import Path

exp = json.loads(Path("/tmp/dynamic_expected.json").read_text())


def test_dynamic_transfer_and_cleaning():
    source = Path("/home/user/remote_staging/raw_data.csv")
    working = Path("/home/user/local_processing/working_data.csv")
    cleaned = Path("/home/user/local_processing/cleaned_data.csv")
    assert working.is_file() and working.read_bytes() == source.read_bytes()
    assert cleaned.is_file()
    assert cleaned.read_text().splitlines() == exp["cleaned"]


def test_dynamic_database_contents_and_schema():
    db = Path("/home/user/db/analytics.sqlite")
    assert db.is_file()
    conn = sqlite3.connect(db)
    schema = [(r[1], r[2].upper()) for r in conn.execute("PRAGMA table_info(employee_stats)")]
    assert schema == [
        ("id", "INTEGER"), ("name", "TEXT"), ("email", "TEXT"),
        ("score", "INTEGER"), ("department", "TEXT")
    ]
    rows = conn.execute(
        "SELECT id,name,email,score,department FROM employee_stats ORDER BY id"
    ).fetchall()
    t, a, z = exp["token"], exp["alpha"], exp["zeta"]
    assert rows == [
        (101, f"Ada {t}", f"ada.{t}@example.com", 80, z),
        (103, f"Cara {t}", f"cara.{t}@example.com", 90, z),
        (104, f"Dan {t}", f"dan.{t}@test.com", 75, a),
        (106, f"Finn {t}", f"finn.{t}@test.com", 76, a),
    ]
    conn.close()


def test_dynamic_template_report_and_cron():
    report = Path("/home/user/reports/final_report.md")
    assert report.is_file()
    content = report.read_text()
    t, a, z = map(re.escape, (exp["token"], exp["alpha"], exp["zeta"]))
    pattern = (rf"\ABEGIN-{t}\nCount=4\nSTATS-BEGIN\n"
               rf"{a}: 75\.5\n{z}: 85(?:\.0)?\n"
               rf"STATS-END\nEND-{t}\n?\Z")
    assert re.fullmatch(pattern, content), content
    assert "__TOTAL_RECORDS__" not in content and "__DEPT_STATS__" not in content
    cron = Path("/home/user/cron.conf")
    assert cron.is_file()
    assert "30 3 * * * /home/user/pipeline.sh" in cron.read_text().strip()
PYTEST

python3 -m pytest /tmp/test_dynamic_pipeline.py -x --tb=short 2>&1 || status=1

if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
