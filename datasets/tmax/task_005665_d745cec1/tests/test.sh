#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import sqlite3
import subprocess
import tempfile

HOME = "/home/user"
SOURCE = os.path.join(HOME, "process_results.c")
EXECUTABLE = os.path.join(HOME, "process_results")
REPORT = os.path.join(HOME, "report.tsv")


def run_program(path, *args):
    return subprocess.run(
        [path, *args],
        cwd=HOME,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )


def read_report():
    assert os.path.isfile(REPORT), f"Missing report file: {REPORT}"
    with open(REPORT, "r", encoding="utf-8") as f:
        return f.read().splitlines()


def test_c_source_exists():
    assert os.path.isfile(SOURCE), f"Missing C source code file: {SOURCE}"


def test_executable_exists():
    assert os.path.isfile(EXECUTABLE), f"Missing executable file: {EXECUTABLE}"
    assert os.access(EXECUTABLE, os.X_OK), f"File {EXECUTABLE} is not executable"
    with open(EXECUTABLE, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"File {EXECUTABLE} is not a compiled executable"


def test_report_and_program_behavior():
    # Preserve the original assertion that the requested final report exists.
    assert os.path.isfile(REPORT), f"Missing report file: {REPORT}"

    # The executable must enforce exactly one author argument.
    no_arg = run_program(EXECUTABLE)
    assert no_arg.returncode != 0, "process_results must reject a missing author argument"
    two_args = run_program(EXECUTABLE, "Dr. Alan Turing", "extra")
    assert two_args.returncode != 0, "process_results must reject more than one argument"

    # Execute the submitted /home/user executable on the supplied dataset.
    if os.path.exists(REPORT):
        os.remove(REPORT)
    result = run_program(EXECUTABLE, "Dr. Alan Turing")
    assert result.returncode == 0, f"process_results failed: {result.stderr}"

    expected_lines = [
        "OriginalPaperID\tCitingPaperID\tCitingAbstract",
        "101\t201\tAn overview of modern artificial intelligence and its roots.",
        "101\t202\tThis paper reevaluates the concept of the Turing machine in the 21st century.",
        "102\t202\tThis paper reevaluates the concept of the Turing machine in the 21st century.",
        "102\t203\tA comprehensive history of computing from the 1930s to today.",
    ]
    actual_lines = read_report()
    assert len(actual_lines) == len(expected_lines), (
        f"Expected {len(expected_lines)} lines in report.tsv, but found {len(actual_lines)}"
    )
    for i, (actual, expected) in enumerate(zip(actual_lines, expected_lines)):
        assert actual == expected, (
            f"Mismatch at line {i + 1} in report.tsv.\nExpected: {expected}\nActual: {actual}"
        )

    # Compile the submitted C source independently so a dummy executable cannot
    # hide nonfunctional source code.
    fd, compiled = tempfile.mkstemp(prefix="process_results_test_", dir="/tmp")
    os.close(fd)
    os.unlink(compiled)
    build = subprocess.run(
        ["gcc", SOURCE, "-o", compiled],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert build.returncode == 0, f"C source did not compile with gcc: {build.stderr}"

    paths = [
        os.path.join(HOME, "papers.db"),
        os.path.join(HOME, "citations.txt"),
        os.path.join(HOME, "abstracts.txt"),
        REPORT,
    ]
    backups = {p: (open(p, "rb").read() if os.path.exists(p) else None) for p in paths}

    try:
        token = secrets.token_hex(6)
        author = f"Dr. Verification {token}"
        base = 10000 + secrets.randbelow(1000000)
        o1, o2 = base + 11, base + 29
        c1, c2, c3 = base + 103, base + 151, base + 197
        unrelated = base + 251
        abstracts = {
            c1: f"Dynamic abstract alpha {token}.",
            c2: f"Dynamic abstract beta {token}.",
            c3: f"Dynamic abstract gamma {token}.",
        }

        db_path = os.path.join(HOME, "papers.db")
        os.remove(db_path)
        con = sqlite3.connect(db_path)
        con.execute("CREATE TABLE papers(id INTEGER PRIMARY KEY, title TEXT, author TEXT)")
        con.executemany(
            "INSERT INTO papers(id, title, author) VALUES (?, ?, ?)",
            [
                (o2, "Second generated paper", author),
                (o1, "First generated paper", author),
                (c1, "Citing one", "Another Author"),
                (c2, "Citing two", "Another Author"),
                (c3, "Citing three", "Another Author"),
                (unrelated, "Unrelated paper", "Unrelated Author"),
            ],
        )
        con.commit()
        con.close()

        with open(os.path.join(HOME, "citations.txt"), "w", encoding="utf-8") as f:
            # Deliberately unsorted, with an unrelated edge.
            f.write(f"{o2} {c3}\n{o1} {c2}\n{unrelated} {c3}\n{o2} {c1}\n{o1} {c1}\n")

        with open(os.path.join(HOME, "abstracts.txt"), "w", encoding="utf-8") as f:
            f.write(f"{c3}|{abstracts[c3]}\n{c1}|{abstracts[c1]}\n{c2}|{abstracts[c2]}\n")

        if os.path.exists(REPORT):
            os.remove(REPORT)
        dynamic_run = run_program(compiled, author)
        assert dynamic_run.returncode == 0, f"Compiled program failed on generated data: {dynamic_run.stderr}"

        dynamic_expected = [
            "OriginalPaperID\tCitingPaperID\tCitingAbstract",
            f"{o1}\t{c1}\t{abstracts[c1]}",
            f"{o1}\t{c2}\t{abstracts[c2]}",
            f"{o2}\t{c1}\t{abstracts[c1]}",
            f"{o2}\t{c3}\t{abstracts[c3]}",
        ]
        assert read_report() == dynamic_expected, (
            "Program did not correctly query, cross-reference, retrieve, and sort generated data"
        )
    finally:
        if os.path.exists(compiled):
            os.remove(compiled)
        for path, data in backups.items():
            if data is None:
                if os.path.exists(path):
                    os.remove(path)
            else:
                with open(path, "wb") as f:
                    f.write(data)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
