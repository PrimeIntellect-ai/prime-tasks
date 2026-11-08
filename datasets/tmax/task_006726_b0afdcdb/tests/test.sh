#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PY' > /tmp/test_final_state.py
import csv
import os
import random
import subprocess
import uuid

HOME = "/home/user"


def run(command):
    return subprocess.run(
        command,
        cwd=HOME,
        check=True,
        timeout=20,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )


def read_matches():
    path = os.path.join(HOME, "matches.txt")
    assert os.path.isfile(path), (
        f"File {path} is missing. The C program must write results to this file."
    )
    with open(path, "r", encoding="utf-8") as f:
        return [line.strip() for line in f.read().strip().splitlines() if line.strip()]


def run_pipeline():
    run(["bash", os.path.join(HOME, "etl.sh")])
    run([os.path.join(HOME, "pattern_match_exe")])


def test_complete_pipeline():
    c_path = os.path.join(HOME, "pattern_match.c")
    sh_path = os.path.join(HOME, "etl.sh")
    exe_path = os.path.join(HOME, "pattern_match_exe")

    assert os.path.isfile(c_path), f"C source file {c_path} is missing."
    assert os.path.isfile(sh_path), f"Shell script {sh_path} is missing."
    assert os.path.isfile(exe_path), (
        f"Executable {exe_path} is missing. Did you compile your C program to this path?"
    )
    assert os.access(exe_path, os.X_OK), f"File {exe_path} is not executable."

    # Recompile the submitted source so the tested executable must come from it.
    run(["gcc", "-std=c11", "-Wall", "-Wextra", c_path, "-o", exe_path])
    assert os.path.isfile(exe_path) and os.access(exe_path, os.X_OK)

    # Execute the submitted ETL and matcher on the supplied data, then retain the
    # original exact output assertion.
    run_pipeline()
    expected_original = [
        "Alice cites Bob",
        "Alice cites Dave",
        "Charlie cites Bob",
        "Charlie cites Frank",
        "Eve cites Frank",
    ]
    assert read_matches() == expected_original, (
        f"Content of {os.path.join(HOME, 'matches.txt')} is incorrect.\n"
        f"Expected:\n{expected_original}\nGot:\n{read_matches()}"
    )

    # Generate an unpredictable second graph, including duplicate manager pairs
    # and irrelevant edges, and derive its expected result from the graph data.
    tag = uuid.uuid4().hex[:10]
    users = [
        ("e1", f"Zara_{tag}", "Engineer"),
        ("e2", f"Amy_{tag}", "Engineer"),
        ("e3", f"Mina_{tag}", "Engineer"),
        ("m1", f"Carl_{tag}", "Manager"),
        ("m2", f"Ben_{tag}", "Manager"),
        ("m3", f"Yves_{tag}", "Manager"),
        ("x1", f"Other_{tag}", "Analyst"),
    ]
    documents = [
        ("de1", "e1", ["dm1a", "dm1b", "dm2"]),
        ("de2", "e2", ["dm2", "dx", "de1"]),
        ("de3", "e3", ["dm3", "missing"]),
        ("dm1a", "m1", []),
        ("dm1b", "m1", []),
        ("dm2", "m2", ["de1"]),
        ("dm3", "m3", []),
        ("dx", "x1", ["dm1a"]),
    ]

    random.SystemRandom().shuffle(users)
    random.SystemRandom().shuffle(documents)

    with open(os.path.join(HOME, "users.csv"), "w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f, lineterminator="\n")
        writer.writerow(["id", "name", "role"])
        writer.writerows(users)

    with open(os.path.join(HOME, "docs.txt"), "w", encoding="utf-8") as f:
        for index, (doc_id, author, cites) in enumerate(documents):
            if index:
                f.write("---\n")
            f.write(f"DOC: {doc_id}\n")
            f.write(f"AUTHOR: {author}\n")
            f.write(f"CITES: {', '.join(cites)}\n")

    user_by_id = {uid: (name, role) for uid, name, role in users}
    author_by_doc = {doc_id: author for doc_id, author, _ in documents}
    expected_pairs = set()
    for source_doc, source_author, citations in documents:
        source = user_by_id.get(source_author)
        if not source or source[1] != "Engineer":
            continue
        for cited_doc in citations:
            target_author = author_by_doc.get(cited_doc)
            target = user_by_id.get(target_author)
            if target and target[1] == "Manager":
                expected_pairs.add((source[0], target[0]))
    expected_dynamic = [f"{engineer} cites {manager}" for engineer, manager in sorted(expected_pairs)]

    # Run ETL first, then replace docs.txt with a decoy. The matcher is required
    # to consume the transformed data rather than bypassing the ETL stage.
    run(["bash", sh_path])
    with open(os.path.join(HOME, "docs.txt"), "w", encoding="utf-8") as f:
        f.write("DOC: decoy\nAUTHOR: x1\nCITES:\n")
    if os.path.exists(os.path.join(HOME, "matches.txt")):
        os.remove(os.path.join(HOME, "matches.txt"))
    run([exe_path])

    actual_dynamic = read_matches()
    assert actual_dynamic == expected_dynamic, (
        "The executed ETL/C pipeline produced incorrect results for a generated graph.\n"
        f"Expected:\n{expected_dynamic}\nGot:\n{actual_dynamic}"
    )
PY

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
