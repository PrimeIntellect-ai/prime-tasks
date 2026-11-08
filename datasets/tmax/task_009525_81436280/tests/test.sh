#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import collections
import csv
import io
import json
import os
import pathlib
import subprocess

SOURCE = "/home/user/audit_path.c"
EXECUTABLE = "/home/user/audit_path"
PATH_OUTPUT = "/home/user/shortest_path.txt"
WEIGHT_OUTPUT = "/home/user/total_weight.txt"
ACCESS_LOG = "/home/user/access_logs.jsonl"


def test_c_program_exists():
    """Verify that the C source file and compiled executable exist."""
    assert os.path.exists(SOURCE), f"Missing C source file: {SOURCE}"
    assert os.path.isfile(SOURCE), f"Path is not a file: {SOURCE}"

    assert os.path.exists(EXECUTABLE), f"Missing compiled executable: {EXECUTABLE}"
    assert os.path.isfile(EXECUTABLE), f"Path is not a file: {EXECUTABLE}"
    assert os.access(EXECUTABLE, os.X_OK), f"File is not executable: {EXECUTABLE}"
    with open(EXECUTABLE, "rb") as f:
        assert f.read(4) == b"\x7fELF", "audit_path is not a compiled Linux executable"


def test_shortest_path_output():
    """Verify the shortest path output file contains the correct path."""
    assert os.path.exists(PATH_OUTPUT), f"Missing output file: {PATH_OUTPUT}"
    assert os.path.isfile(PATH_OUTPUT), f"Path is not a file: {PATH_OUTPUT}"

    with open(PATH_OUTPUT, "r") as f:
        content = f.read().strip()

    expected_path = "ENTRY_PORTAL,PROXY_B,CACHE_SERVER,DB_RELAY,SECURE_VAULT"
    assert content == expected_path, f"Incorrect shortest path. Expected '{expected_path}', got '{content}'"


def test_total_weight_output():
    """Verify the total weight output file contains the correct weight."""
    assert os.path.exists(WEIGHT_OUTPUT), f"Missing output file: {WEIGHT_OUTPUT}"
    assert os.path.isfile(WEIGHT_OUTPUT), f"Path is not a file: {WEIGHT_OUTPUT}"

    with open(WEIGHT_OUTPUT, "r") as f:
        content = f.read().strip()

    expected_weight = "28"
    assert content == expected_weight, f"Incorrect total weight. Expected '{expected_weight}', got '{content}'"


def parse_edge_file(path):
    try:
        text = pathlib.Path(path).read_text()
    except (OSError, UnicodeError):
        return None
    lines = [line.strip() for line in text.splitlines() if line.strip()]
    if not lines:
        return None

    records = []
    try:
        for line in lines:
            obj = json.loads(line)
            records.append((str(obj["source"]), str(obj["target"]), int(obj["weight"])))
        return records, "json", False
    except Exception:
        records = []

    for delimiter, mode in [("\t", "tsv"), (",", "csv"), (None, "space")]:
        parsed = []
        had_header = False
        try:
            for index, line in enumerate(lines):
                if delimiter is None:
                    row = line.split()
                else:
                    row = next(csv.reader([line], delimiter=delimiter))
                row = [item.strip() for item in row]
                if index == 0 and len(row) >= 3 and row[0].lower() == "source" and row[1].lower() == "target":
                    had_header = True
                    continue
                if len(row) < 3:
                    raise ValueError()
                parsed.append((row[0], row[1], int(row[2])))
            if parsed:
                return parsed, mode, had_header
        except Exception:
            pass
    return None


def encode_edges(edges, mode, header):
    if mode == "json":
        return "".join(json.dumps({"source": s, "target": t, "weight": w, "status": "active"}) + "\n" for s, t, w in edges)
    delimiter = {"csv": ",", "tsv": "\t", "space": " "}[mode]
    out = io.StringIO()
    if mode == "space":
        if header:
            out.write("source target weight\n")
        for s, t, w in edges:
            out.write(f"{s} {t} {w}\n")
    else:
        writer = csv.writer(out, delimiter=delimiter, lineterminator="\n")
        if header:
            writer.writerow(["source", "target", "weight"])
        writer.writerows(edges)
    return out.getvalue()


def find_filtered_artifact():
    with open(ACCESS_LOG) as f:
        active = collections.Counter(
            (str(obj["source"]), str(obj["target"]), int(obj["weight"]))
            for obj in (json.loads(line) for line in f if line.strip())
            if obj.get("status") == "active"
        )

    excluded = {SOURCE, EXECUTABLE, PATH_OUTPUT, WEIGHT_OUTPUT, ACCESS_LOG}
    for path in pathlib.Path("/home/user").rglob("*"):
        if not path.is_file() or str(path) in excluded:
            continue
        parsed = parse_edge_file(path)
        if parsed and collections.Counter(parsed[0]) == active:
            return str(path), parsed[1], parsed[2]
    return "/home/user/filtered_edges.csv", "csv", False


def assert_hidden_result(binary, input_path, input_data):
    for output in (PATH_OUTPUT, WEIGHT_OUTPUT):
        try:
            os.remove(output)
        except FileNotFoundError:
            pass

    subprocess.run(
        [binary, input_path],
        cwd="/home/user",
        input=input_data,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
        check=True,
    )
    assert os.path.isfile(PATH_OUTPUT), f"{binary} did not create shortest_path.txt when executed"
    assert os.path.isfile(WEIGHT_OUTPUT), f"{binary} did not create total_weight.txt when executed"
    assert pathlib.Path(PATH_OUTPUT).read_text().strip() == "ENTRY_PORTAL,TEST_B,TEST_C,SECURE_VAULT"
    assert pathlib.Path(WEIGHT_OUTPUT).read_text().strip() == "9"


def test_program_executes_and_computes_a_new_filtered_graph():
    input_path, mode, header = find_filtered_artifact()
    hidden_active = [
        ("ENTRY_PORTAL", "TEST_A", 7),
        ("ENTRY_PORTAL", "TEST_B", 2),
        ("TEST_A", "SECURE_VAULT", 20),
        ("TEST_B", "TEST_C", 3),
        ("TEST_C", "SECURE_VAULT", 4),
        ("TEST_B", "SECURE_VAULT", 30),
    ]
    input_data = encode_edges(hidden_active, mode, header)
    pathlib.Path(input_path).write_text(input_data)

    # The raw export contains tempting stale shortcuts. Programs that consume the
    # unfiltered export, or treat stale edges as active, therefore produce the wrong answer.
    raw_records = [
        {"source": s, "target": t, "weight": w, "status": "active"}
        for s, t, w in hidden_active
    ] + [
        {"source": "ENTRY_PORTAL", "target": "SECURE_VAULT", "weight": 1, "status": "stale"},
        {"source": "TEST_B", "target": "SECURE_VAULT", "weight": 1, "status": "stale"},
    ]
    pathlib.Path(ACCESS_LOG).write_text("".join(json.dumps(record) + "\n" for record in raw_records))

    rebuilt = "/tmp/audit_path_rebuilt"
    compile_result = subprocess.run(
        ["gcc", "-std=c11", "-O2", SOURCE, "-o", rebuilt],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )
    assert compile_result.returncode == 0, f"C source does not compile cleanly:\n{compile_result.stderr}"

    # Exercise both the submitted executable and a fresh build of the submitted source.
    assert_hidden_result(EXECUTABLE, input_path, input_data)
    assert_hidden_result(rebuilt, input_path, input_data)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
