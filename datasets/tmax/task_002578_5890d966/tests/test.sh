#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import shutil
import stat
import subprocess
from pathlib import Path

import pytest


def compute_expected(classifications_text, edges):
    classifications = {}
    for raw_line in classifications_text.splitlines():
        line = raw_line.strip()
        if line and ":" in line:
            node, cls = line.split(":", 1)
            classifications[node] = cls

    sensitive = [node for node, cls in classifications.items() if cls == "Sensitive"]
    public = {node for node, cls in classifications.items() if cls == "Public"}

    adjacency = {}
    all_nodes = set(classifications)
    for src, target in edges:
        adjacency.setdefault(src, []).append(target)
        all_nodes.add(src)
        all_nodes.add(target)

    found = []
    queue = [[node] for node in sensitive]
    while queue:
        path = queue.pop(0)
        current = path[-1]
        if current in public:
            found.append(path)
            continue
        for nxt in adjacency.get(current, []):
            if nxt not in path:
                queue.append(path + [nxt])

    if not found:
        return "COMPLIANT: No paths found"

    shortest_edges = min(len(path) - 1 for path in found)
    candidates = [
        " -> ".join(path)
        for path in found
        if len(path) - 1 == shortest_edges
    ]
    return "VIOLATION: " + min(candidates)


def get_expected_output():
    classifications_path = "/home/user/node_classifications.txt"
    edges_path = "/home/user/raw_schema_edges.csv"

    if not os.path.exists(classifications_path) or not os.path.exists(edges_path):
        return None

    classifications_text = Path(classifications_path).read_text()
    active_edges = []
    with open(edges_path, "r") as handle:
        for raw_line in handle:
            parts = raw_line.strip().split(",")
            if len(parts) == 3 and parts[2] == "Active":
                active_edges.append((parts[0], parts[1]))

    return compute_expected(classifications_text, active_edges)


def run_tool(executable, classifications_text, edges):
    classification_path = Path("/tmp/verifier_node_classifications.txt")
    classification_path.write_text(classifications_text)
    stdin_text = "".join(f"{src},{target}\n" for src, target in edges)
    result = subprocess.run(
        [str(executable), str(classification_path)],
        input=stdin_text,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )
    assert result.returncode == 0, (
        f"{executable} exited with {result.returncode}. stderr: {result.stderr}"
    )
    return result.stdout.strip()


def test_cpp_source_exists():
    path = "/home/user/audit_paths.cpp"
    assert os.path.isfile(path), f"C++ source code is missing at {path}"


def test_cpp_executable_exists():
    path = "/home/user/audit_paths"
    assert os.path.isfile(path), f"Compiled C++ executable is missing at {path}"
    assert os.access(path, os.X_OK), f"File at {path} is not executable"
    with open(path, "rb") as handle:
        assert handle.read(4) == b"\x7fELF", f"File at {path} is not a compiled executable"


def test_bash_script_exists_and_executable():
    path = "/home/user/audit_pipeline.sh"
    assert os.path.isfile(path), f"Bash script is missing at {path}"
    assert os.access(path, os.X_OK), f"Bash script at {path} is not executable"


def test_audit_report_content():
    path = "/home/user/audit_report.txt"
    assert os.path.isfile(path), f"Audit report is missing at {path}. Did you run the pipeline?"

    with open(path, "r") as handle:
        actual_content = handle.read().strip()

    expected_content = get_expected_output()
    assert expected_content is not None, "Setup files are missing, cannot compute expected output."
    assert actual_content == expected_content, (
        "Audit report content does not match expected output.\n"
        f"Expected: '{expected_content}'\n"
        f"Actual:   '{actual_content}'"
    )


def test_cpp_source_and_submitted_executable_compute_paths():
    rebuilt = Path("/tmp/verifier_audit_paths")
    compile_result = subprocess.run(
        ["g++", "-std=c++17", "/home/user/audit_paths.cpp", "-o", str(rebuilt)],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )
    assert compile_result.returncode == 0, (
        f"audit_paths.cpp does not compile with g++ -std=c++17: {compile_result.stderr}"
    )

    cases = [
        (
            "Zed:Sensitive\nAlpha:Sensitive\nA:Internal\nB:Internal\nZ:Internal\nPub:Public\n",
            [
                ("Zed", "B"),
                ("B", "Pub"),
                ("Alpha", "Z"),
                ("Z", "Pub"),
                ("Alpha", "A"),
                ("A", "Alpha"),
                ("A", "Pub"),
            ],
        ),
        (
            "Secret:Sensitive\nMiddle:Internal\nOutside:Public\nOther:Internal\n",
            [("Secret", "Middle"), ("Other", "Outside")],
        ),
        (
            "S:Sensitive\nP:Public\nM:Internal\n",
            [("S", "M"), ("M", "P"), ("S", "P")],
        ),
    ]

    for executable in (Path("/home/user/audit_paths"), rebuilt):
        for classifications_text, edges in cases:
            expected = compute_expected(classifications_text, edges)
            actual = run_tool(executable, classifications_text, edges)
            assert actual == expected, (
                f"{executable} produced the wrong result.\n"
                f"Expected: '{expected}'\nActual:   '{actual}'"
            )


def _restore_regular_file(path, data, mode):
    if os.path.lexists(path):
        if os.path.isdir(path) and not os.path.islink(path):
            shutil.rmtree(path)
        else:
            os.unlink(path)
    with open(path, "wb") as handle:
        handle.write(data)
    os.chmod(path, stat.S_IMODE(mode))


def test_pipeline_filters_active_edges_and_runs_tool():
    classifications_path = "/home/user/node_classifications.txt"
    edges_path = "/home/user/raw_schema_edges.csv"
    report_path = "/home/user/audit_report.txt"

    backups = {}
    for path in (classifications_path, edges_path, report_path):
        backups[path] = (Path(path).read_bytes(), os.stat(path).st_mode)

    classifications_text = (
        "S1:Sensitive\n"
        "S0:Sensitive\n"
        "I:Internal\n"
        "A:Internal\n"
        "P:Public\n"
        "X:Internal\n"
    )
    raw_rows = [
        ("S1", "P", "Inactive"),
        ("S1", "I", "Active"),
        ("I", "P", "Active"),
        ("S0", "A", "Active"),
        ("A", "P", "Active"),
        ("S0", "P", "NotActive"),
        ("X", "P", "Active"),
    ]
    active_edges = [(src, target) for src, target, status in raw_rows if status == "Active"]
    expected = compute_expected(classifications_text, active_edges)

    try:
        Path(classifications_path).write_text(classifications_text)
        Path(edges_path).write_text(
            "".join(f"{src},{target},{status}\n" for src, target, status in raw_rows)
        )
        Path(report_path).write_text("SENTINEL: pipeline did not generate this report\n")

        result = subprocess.run(
            ["/home/user/audit_pipeline.sh"],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=10,
        )
        assert result.returncode == 0, (
            f"audit_pipeline.sh exited with {result.returncode}. stderr: {result.stderr}"
        )
        assert os.path.isfile(report_path), "The pipeline did not create audit_report.txt"
        actual = Path(report_path).read_text().strip()
        assert actual == expected, (
            "The pipeline did not correctly filter Active rows and invoke audit_paths.\n"
            f"Expected: '{expected}'\nActual:   '{actual}'"
        )
    finally:
        for path, (data, mode) in backups.items():
            _restore_regular_file(path, data, mode)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
