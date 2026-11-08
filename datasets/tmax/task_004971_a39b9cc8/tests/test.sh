#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/test_final_state.py
import csv
import heapq
import os
import secrets
import subprocess

CPP_PATH = "/home/user/audit.cpp"
EXE_PATH = "/home/user/audit"
GRAPH_PATH = "/home/user/system_graph.csv"
REPORT_PATH = "/home/user/compliance_report.txt"
COMPILED_PATH = "/tmp/audit_from_source"


def expected_report(rows):
    graph = {}
    for source, target, latency, data_tags in rows:
        if "PII" in data_tags:
            graph.setdefault(source, []).append((target, int(latency)))

    distances = {"Web": 0}
    previous = {}
    queue = [(0, "Web")]
    while queue:
        distance, node = heapq.heappop(queue)
        if distance != distances.get(node):
            continue
        if node == "ProfileDB":
            break
        for target, weight in graph.get(node, []):
            candidate = distance + weight
            if candidate < distances.get(target, float("inf")):
                distances[target] = candidate
                previous[target] = node
                heapq.heappush(queue, (candidate, target))

    assert "ProfileDB" in distances, "Verifier generated a graph without a path"
    path = ["ProfileDB"]
    while path[-1] != "Web":
        path.append(previous[path[-1]])
    path.reverse()
    return f"Violation Path: {'->'.join(path)}, Total Latency: {distances['ProfileDB']}"


def write_graph(rows):
    with open(GRAPH_PATH, "w", newline="") as graph_file:
        writer = csv.writer(graph_file, lineterminator="\n")
        writer.writerow(["source", "target", "latency", "data_tags"])
        writer.writerows(rows)


def exercise(executable, rows):
    write_graph(rows)
    if os.path.lexists(REPORT_PATH):
        os.remove(REPORT_PATH)
    result = subprocess.run(
        [executable], cwd="/home/user", stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, text=True, timeout=10
    )
    assert result.returncode == 0, (
        f"{executable} exited with {result.returncode}: {result.stderr}"
    )
    assert os.path.isfile(REPORT_PATH), (
        f"{executable} did not generate {REPORT_PATH}"
    )
    with open(REPORT_PATH, "r") as report_file:
        actual = report_file.read().strip()
    expected = expected_report(rows)
    assert actual == expected, (
        f"Incorrect result from {executable}. Expected '{expected}', got '{actual}'."
    )


def main():
    # Preserve all assertions made by the original verifier.
    assert os.path.isfile(CPP_PATH), f"C++ source code file {CPP_PATH} does not exist."
    assert os.path.isfile(EXE_PATH), f"Executable file {EXE_PATH} does not exist."
    assert os.access(EXE_PATH, os.X_OK), f"File {EXE_PATH} is not executable."
    assert os.path.isfile(REPORT_PATH), f"Compliance report file {REPORT_PATH} does not exist."

    expected_initial = "Violation Path: Web->Proxy->ProfileDB, Total Latency: 13"
    with open(REPORT_PATH, "r") as report_file:
        initial_content = report_file.read().strip()
    assert initial_content == expected_initial, (
        f"Content of {REPORT_PATH} is incorrect. Expected '{expected_initial}', "
        f"got '{initial_content}'."
    )

    # A compiled C++ executable should be an ELF binary, not an arbitrary script.
    with open(EXE_PATH, "rb") as executable_file:
        assert executable_file.read(4) == b"\x7fELF", (
            f"{EXE_PATH} is not a compiled ELF executable"
        )

    compile_result = subprocess.run(
        ["g++", "-std=c++17", CPP_PATH, "-o", COMPILED_PATH],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30
    )
    assert compile_result.returncode == 0, (
        f"audit.cpp does not compile: {compile_result.stderr}"
    )

    token = lambda prefix: prefix + secrets.token_hex(5)
    a, b, c, dead = token("SvcA_"), token("SvcB_"), token("SvcC_"), token("Dead_")
    case_one = [
        ("Web", a, "17", "PII"),
        (a, "ProfileDB", "18", "PII"),
        ("Web", b, "3", "PII"),
        (b, c, "4", "XPIIY"),
        (c, "ProfileDB", "5", "PII_RESTRICTED"),
        ("Web", "ProfileDB", "1", "Public"),
        ("Web", dead, "1", "Sensitive"),
        (dead, "ProfileDB", "1", "PII"),
        (b, "ProfileDB", "25", "PII"),
        (c, b, "2", "PII"),
    ]

    lower, preferred, other = token("Lower_"), token("Preferred_"), token("Other_")
    case_two = [
        ("Web", lower, "1", "pii"),
        (lower, "ProfileDB", "1", "PII"),
        ("Web", preferred, "5", "PII"),
        (preferred, "ProfileDB", "6", "ContainsPIIData"),
        ("Web", other, "2", "PII"),
        (other, "ProfileDB", "30", "PII"),
        ("Web", "ProfileDB", "20", "PII"),
        (preferred, other, "50", "PII"),
        (other, preferred, "1", "Public"),
    ]

    with open(GRAPH_PATH, "rb") as graph_file:
        original_graph = graph_file.read()
    with open(REPORT_PATH, "rb") as report_file:
        original_report = report_file.read()

    try:
        for executable in (EXE_PATH, COMPILED_PATH):
            exercise(executable, case_one)
            exercise(executable, case_two)
    finally:
        with open(GRAPH_PATH, "wb") as graph_file:
            graph_file.write(original_graph)
        with open(REPORT_PATH, "wb") as report_file:
            report_file.write(original_report)


if __name__ == "__main__":
    main()
PY_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
