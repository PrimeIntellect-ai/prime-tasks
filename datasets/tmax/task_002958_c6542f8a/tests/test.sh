#!/bin/bash
mkdir -p /logs/verifier
reward=0
BACKUP_DB="/tmp/original_dataset.db"

cleanup() {
    if [ -f "$BACKUP_DB" ]; then
        rm -f /home/user/dataset.db /home/user/dataset.db-wal /home/user/dataset.db-shm
        cp -p "$BACKUP_DB" /home/user/dataset.db
    fi
    echo "$reward" > /logs/verifier/reward.txt
}
trap cleanup EXIT
set -e

ANALYZER=/home/user/analyzer.go
GO_MOD=/home/user/go.mod
JSON_PATH=/home/user/top_researchers.json
DB_PATH=/home/user/dataset.db

[ -f "$ANALYZER" ]
[ -f "$GO_MOD" ]
[ -f "$DB_PATH" ]

cat > /tmp/check_analyzer.go <<'GO_EOF'
package main

import (
    "fmt"
    "go/ast"
    "go/parser"
    "go/token"
    "os"
    "regexp"
    "strconv"
    "strings"
)

func main() {
    if len(os.Args) != 2 {
        os.Exit(2)
    }
    fset := token.NewFileSet()
    f, err := parser.ParseFile(fset, os.Args[1], nil, 0)
    if err != nil {
        fmt.Fprintln(os.Stderr, err)
        os.Exit(1)
    }
    if f.Name.Name != "main" {
        fmt.Fprintln(os.Stderr, "analyzer.go must be package main")
        os.Exit(1)
    }

    hasMain := false
    importsSQL := false
    queryCalls := 0
    forbiddenCalls := 0
    var stringLiterals strings.Builder

    for _, imp := range f.Imports {
        p, _ := strconv.Unquote(imp.Path.Value)
        if p == "database/sql" {
            importsSQL = true
        }
    }

    ast.Inspect(f, func(n ast.Node) bool {
        switch x := n.(type) {
        case *ast.FuncDecl:
            if x.Recv == nil && x.Name.Name == "main" {
                hasMain = true
            }
        case *ast.BasicLit:
            if x.Kind == token.STRING {
                if s, err := strconv.Unquote(x.Value); err == nil {
                    stringLiterals.WriteString(s)
                    stringLiterals.WriteByte('\n')
                }
            }
        case *ast.CallExpr:
            if sel, ok := x.Fun.(*ast.SelectorExpr); ok {
                switch sel.Sel.Name {
                case "Query", "QueryContext", "QueryRow", "QueryRowContext":
                    queryCalls++
                case "Exec", "ExecContext":
                    forbiddenCalls++
                }
            }
        }
        return true
    })

    sqlText := stringLiterals.String()
    hasLimit := regexp.MustCompile(`(?i)\bLIMIT\b`).MatchString(sqlText)
    hasOffset := regexp.MustCompile(`(?i)\bOFFSET\b`).MatchString(sqlText)

    if !hasMain || !importsSQL {
        fmt.Fprintln(os.Stderr, "analyzer.go must be an executable database/sql Go program")
        os.Exit(1)
    }
    if queryCalls != 1 {
        fmt.Fprintf(os.Stderr, "expected exactly one query execution, found %d\n", queryCalls)
        os.Exit(1)
    }
    if forbiddenCalls != 0 {
        fmt.Fprintln(os.Stderr, "database mutation/Exec calls are not allowed")
        os.Exit(1)
    }
    if !hasLimit || !hasOffset {
        fmt.Fprintln(os.Stderr, "the SQL must implement LIMIT and OFFSET pagination")
        os.Exit(1)
    }
}
GO_EOF

go build -o /tmp/check_analyzer /tmp/check_analyzer.go
/tmp/check_analyzer "$ANALYZER"
runuser -u user -- sh -c 'cd /home/user && go list -m >/dev/null'

cp -p "$DB_PATH" "$BACKUP_DB"

python3 <<'PY_EOF'
import json
import os
import secrets
import sqlite3
import string

path = "/tmp/dynamic_dataset.db"
try:
    os.remove(path)
except FileNotFoundError:
    pass

rng = secrets.SystemRandom()
conn = sqlite3.connect(path)
cur = conn.cursor()
cur.executescript("""
CREATE TABLE researchers (
    id INTEGER PRIMARY KEY,
    full_name TEXT NOT NULL,
    institution TEXT
);
CREATE TABLE publications (
    id INTEGER PRIMARY KEY,
    title TEXT NOT NULL,
    year INTEGER
);
CREATE TABLE authorship (
    researcher_id INTEGER,
    publication_id INTEGER,
    author_order INTEGER,
    FOREIGN KEY(researcher_id) REFERENCES researchers(id),
    FOREIGN KEY(publication_id) REFERENCES publications(id)
);
CREATE TABLE references_tbl (
    source_pub_id INTEGER,
    target_pub_id INTEGER,
    FOREIGN KEY(source_pub_id) REFERENCES publications(id),
    FOREIGN KEY(target_pub_id) REFERENCES publications(id)
);
""")

pub_ids = []
next_pub = rng.randrange(10000, 50000)
for rid in range(1, 10):
    suffix = ''.join(rng.choice(string.ascii_uppercase) for _ in range(10))
    cur.execute("INSERT INTO researchers VALUES (?, ?, ?)",
                (rid, f"Researcher {suffix}", f"Institute {rid}"))
    for n in range(rng.randrange(1, 4)):
        next_pub += rng.randrange(2, 8)
        pub_ids.append(next_pub)
        cur.execute("INSERT INTO publications VALUES (?, ?, ?)",
                    (next_pub, f"Paper {rid}-{n}-{suffix}", 1980 + rid + n))
        cur.execute("INSERT INTO authorship VALUES (?, ?, ?)",
                    (rid, next_pub, 1))

# Add unique coauthorships so publication counting and citation aggregation both matter.
for rid in range(2, 6):
    target = pub_ids[(rid * 3) % len(pub_ids)]
    cur.execute("INSERT INTO authorship VALUES (?, ?, ?)", (rid, target, 2))

for target in pub_ids:
    for _ in range(rng.randrange(0, 17)):
        source = rng.choice(pub_ids)
        cur.execute("INSERT INTO references_tbl VALUES (?, ?)", (source, target))

conn.commit()
query = """
SELECT r.id AS researcher_id,
       r.full_name,
       COUNT(DISTINCT a.publication_id) AS total_publications,
       COALESCE(SUM(c.citations), 0) AS total_citations
FROM researchers r
JOIN authorship a ON r.id = a.researcher_id
LEFT JOIN (
    SELECT target_pub_id, COUNT(*) AS citations
    FROM references_tbl
    GROUP BY target_pub_id
) c ON a.publication_id = c.target_pub_id
GROUP BY r.id, r.full_name
ORDER BY total_citations DESC, r.full_name ASC
LIMIT 5 OFFSET 0
"""
rows = conn.execute(query).fetchall()
expected = [{
    "researcher_id": row[0],
    "full_name": row[1],
    "total_publications": row[2],
    "total_citations": row[3],
} for row in rows]
conn.close()
with open("/tmp/dynamic_expected.json", "w") as f:
    json.dump(expected, f)
PY_EOF

rm -f "$DB_PATH" "$DB_PATH-wal" "$DB_PATH-shm" "$JSON_PATH"
mv /tmp/dynamic_dataset.db "$DB_PATH"
chown root:root "$DB_PATH"
chmod 0444 "$DB_PATH"
BEFORE_HASH=$(sha256sum "$DB_PATH" | awk '{print $1}')
timeout 120s runuser -u user -- sh -c 'cd /home/user && go run analyzer.go'
AFTER_HASH=$(sha256sum "$DB_PATH" | awk '{print $1}')
[ "$BEFORE_HASH" = "$AFTER_HASH" ]

python3 <<'PY_EOF'
import json
import os

output = "/home/user/top_researchers.json"
assert os.path.isfile(output), "analyzer.go did not create top_researchers.json"
with open("/tmp/dynamic_expected.json") as f:
    expected = json.load(f)
with open(output) as f:
    actual = json.load(f)
assert actual == expected, "analyzer.go produced incorrect results on the verification database"
PY_EOF

# Restore the supplied database and execute the program again so the original
# final-state assertions are retained and the requested final output is present.
rm -f "$DB_PATH" "$DB_PATH-wal" "$DB_PATH-shm" "$JSON_PATH"
cp -p "$BACKUP_DB" "$DB_PATH"
chown root:root "$DB_PATH"
chmod 0444 "$DB_PATH"
BEFORE_HASH=$(sha256sum "$DB_PATH" | awk '{print $1}')
timeout 120s runuser -u user -- sh -c 'cd /home/user && go run analyzer.go'
AFTER_HASH=$(sha256sum "$DB_PATH" | awk '{print $1}')
[ "$BEFORE_HASH" = "$AFTER_HASH" ]

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import sqlite3
import pytest

DB_PATH = "/home/user/dataset.db"
JSON_PATH = "/home/user/top_researchers.json"

def get_expected_results():
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    query = """
    SELECT 
        r.id AS researcher_id,
        r.full_name,
        COUNT(DISTINCT a.publication_id) AS total_publications,
        COALESCE(SUM(c.citations), 0) AS total_citations
    FROM researchers r
    JOIN authorship a ON r.id = a.researcher_id
    LEFT JOIN (
        SELECT target_pub_id, COUNT(*) as citations
        FROM references_tbl
        GROUP BY target_pub_id
    ) c ON a.publication_id = c.target_pub_id
    GROUP BY r.id, r.full_name
    ORDER BY total_citations DESC, r.full_name ASC
    LIMIT 5;
    """
    cursor.execute(query)
    rows = cursor.fetchall()
    conn.close()
    return [{
        "researcher_id": row[0],
        "full_name": row[1],
        "total_publications": row[2],
        "total_citations": row[3]
    } for row in rows]

def test_json_file_exists():
    assert os.path.isfile(JSON_PATH), f"The expected output file {JSON_PATH} does not exist."

def test_json_content_matches_expected():
    assert os.path.isfile(JSON_PATH), f"Cannot verify content because {JSON_PATH} is missing."
    with open(JSON_PATH, 'r') as f:
        try:
            actual_data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {JSON_PATH} does not contain valid JSON.")
    assert isinstance(actual_data, list), f"Expected the JSON output to be a list, but got {type(actual_data).__name__}."
    expected_data = get_expected_results()
    assert len(actual_data) == len(expected_data), f"Expected {len(expected_data)} records, but got {len(actual_data)}."
    for i, (actual, expected) in enumerate(zip(actual_data, expected_data)):
        assert isinstance(actual, dict), f"Expected record at index {i} to be a dictionary."
        assert actual.get("researcher_id") == expected["researcher_id"]
        assert actual.get("full_name") == expected["full_name"]
        assert actual.get("total_publications") == expected["total_publications"]
        assert actual.get("total_citations") == expected["total_citations"]
TEST_EOF

python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short
reward=1
