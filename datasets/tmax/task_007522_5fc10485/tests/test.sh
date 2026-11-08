#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import re
import subprocess

HOME = "/home/user"
SOURCE = os.path.join(HOME, "graph_analyzer.cpp")
LOG = os.path.join(HOME, "access_log.csv")
RESULTS = os.path.join(HOME, "results.txt")
BINARY = "/tmp/graph_analyzer_submission"


def expected_lines(log_path):
    user_roles = {}
    role_resources = {}

    with open(log_path, newline="") as f:
        for row in csv.DictReader(f):
            uid = int(row["user_id"].strip())
            role = row["role"].strip()
            resource = row["resource"].strip()
            user_roles[uid] = role
            role_resources.setdefault(role, set()).add(resource)

    prod_roles = {
        role for role, resources in role_resources.items()
        if "PROD_DB" in resources
    }
    prod_users = sorted(
        (uid for uid, role in user_roles.items() if role in prod_roles),
        reverse=True,
    )
    return [f"USER_ID: {uid}" for uid in prod_users[2:5]]


def run_and_check(csv_text):
    with open(LOG, "w") as f:
        f.write(csv_text)
    if os.path.exists(RESULTS):
        os.remove(RESULTS)

    subprocess.run([BINARY], cwd=HOME, check=True, timeout=10)
    assert os.path.isfile(RESULTS), "The compiled C++ program did not create results.txt"

    with open(RESULTS) as f:
        actual = [line.strip() for line in f if line.strip()]
    assert actual == expected_lines(LOG), (
        f"Program output was incorrect for verifier input. "
        f"Expected {expected_lines(LOG)}, got {actual}"
    )


def test_cpp_program_compiles_and_generates_results():
    assert os.path.isfile(SOURCE), f"File {SOURCE} is missing or is not a file."
    original_log = open(LOG, "rb").read()

    compile_result = subprocess.run(
        ["g++", "-std=c++17", "-O2", SOURCE, "-o", BINARY],
        cwd=HOME,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert compile_result.returncode == 0, (
        "graph_analyzer.cpp did not compile:\n" + compile_result.stderr
    )

    cases = [
        """user_id,role,resource
901,alpha,DEV_DB
714,alpha,PROD_DB
622,beta,STAGING_DB
511,beta,PROD_DB
408,gamma,PROD_DB
305,gamma,QA_DB
207,delta,PROD_DB
119,delta,DEV_DB
88,guest,DEV_DB
""",
        """user_id,role,resource
42,ops,PROD_DB
730,ops,ARCHIVE
615,reader,PROD_DB
509,reader,REPORTS
398,auditor,PROD_DB
287,auditor,STAGING_DB
176,developer,DEV_DB
65,owner,PROD_DB
954,owner,TEST_DB
843,blocked,QA_DB
""",
    ]

    try:
        for case in cases:
            run_and_check(case)
    finally:
        with open(LOG, "wb") as f:
            f.write(original_log)
        if os.path.exists(RESULTS):
            os.remove(RESULTS)
        subprocess.run([BINARY], cwd=HOME, check=True, timeout=10)


def test_results_file_correctness():
    log_path = "/home/user/access_log.csv"
    results_path = "/home/user/results.txt"

    assert os.path.exists(log_path), f"File {log_path} is missing."
    assert os.path.exists(results_path), f"File {results_path} is missing. Did you run the C++ program?"

    user_roles = {}
    role_resources = {}

    with open(log_path, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            uid = int(row['user_id'].strip())
            role = row['role'].strip()
            resource = row['resource'].strip()

            user_roles[uid] = role
            if role not in role_resources:
                role_resources[role] = set()
            role_resources[role].add(resource)

    prod_roles = {role for role, resources in role_resources.items() if 'PROD_DB' in resources}
    prod_users = [uid for uid, role in user_roles.items() if role in prod_roles]
    prod_users.sort(reverse=True)
    expected_uids = prod_users[2:5]
    expected_lines = [f"USER_ID: {uid}" for uid in expected_uids]

    with open(results_path, 'r') as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert actual_lines == expected_lines, (
        f"Contents of {results_path} do not match the expected output. "
        f"Expected: {expected_lines}, but got: {actual_lines}"
    )


def test_cypher_query_contents():
    query_path = "/home/user/query.cypher"
    assert os.path.exists(query_path), f"File {query_path} is missing."

    with open(query_path, 'r') as f:
        raw_content = f.read()
    content = raw_content.upper()

    required_keywords = [
        "MATCH",
        "SKIP 2",
        "LIMIT 3",
        "DESC",
        "PROD_DB",
        "HAS_ROLE",
        "CAN_ACCESS"
    ]

    for keyword in required_keywords:
        assert keyword in content, f"Expected keyword/phrase '{keyword}' missing in {query_path}"

    assert "//" not in raw_content and "/*" not in raw_content and "*/" not in raw_content, \
        "query.cypher must contain only the raw query, not comments"

    normalized = re.sub(r"\s+", " ", raw_content.strip())
    ident = r"[A-Za-z_][A-Za-z0-9_]*"
    rel = lambda name: rf"\[\s*(?:{ident}\s*)?:\s*{name}\s*\]"

    resource_filter = rf"(?:" \
        rf"\(\s*(?:{ident}\s*)?:\s*Resource\s*\{{\s*name\s*:\s*(['\"])PROD_DB\1\s*\}}\s*\)" \
        rf"|" \
        rf"\(\s*(?P<where_resource>{ident})\s*:\s*Resource\s*\)\s+WHERE\s+" \
        rf"(?P=where_resource)\s*\.\s*name\s*=\s*(['\"])PROD_DB\2" \
        rf")"

    pattern = re.compile(
        rf"MATCH\s+"
        rf"\(\s*(?P<user>{ident})\s*:\s*User\s*\)\s*-\s*{rel('HAS_ROLE')}\s*->\s*"
        rf"\(\s*(?:{ident}\s*)?:\s*Role\s*\)\s*-\s*{rel('CAN_ACCESS')}\s*->\s*"
        rf"{resource_filter}\s+"
        rf"RETURN\s+DISTINCT\s+(?P<return_user>{ident})\s*\.\s*id"
        rf"(?:\s+AS\s+(?P<alias>{ident}))?\s+"
        rf"ORDER\s+BY\s+(?P<order>(?:{ident}\s*\.\s*id)|{ident})\s+DESC\s+"
        rf"SKIP\s+2\s+LIMIT\s+3\s*;?",
        re.IGNORECASE,
    )

    match = pattern.fullmatch(normalized)
    assert match, (
        "query.cypher must be a single valid MATCH query following "
        "User-[:HAS_ROLE]->Role-[:CAN_ACCESS]->Resource, filtering PROD_DB, "
        "and returning the requested pagination"
    )

    user_var = match.group("user").lower()
    assert match.group("return_user").lower() == user_var, \
        "RETURN must use the User variable from MATCH"

    order_expr = re.sub(r"\s+", "", match.group("order")).lower()
    allowed_order = {f"{user_var}.id"}
    if match.group("alias"):
        allowed_order.add(match.group("alias").lower())
    assert order_expr in allowed_order, \
        "ORDER BY must sort the returned user id (or its alias)"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
