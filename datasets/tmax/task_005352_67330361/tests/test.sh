#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import re
import secrets
import shutil
import subprocess
import tempfile

HOME = "/home/user"
SOURCE = f"{HOME}/graph_etl.cpp"
SCRIPT = f"{HOME}/run_pipeline.sh"
CSV_PATH = f"{HOME}/org_data.csv"


def test_00_pipeline_is_actually_run_and_regenerates_outputs():
    assert os.path.isfile(SOURCE), f"{SOURCE} does not exist."
    assert os.path.isfile(SCRIPT), f"{SCRIPT} does not exist."
    assert os.access(SCRIPT, os.X_OK), f"{SCRIPT} is not executable."

    with open(SCRIPT, "r", encoding="utf-8") as f:
        script_text = f.read()
    assert re.search(r"(^|[\s;/])g\+\+([\s]|$)", script_text), "run_pipeline.sh does not invoke g++."
    assert re.search(r"(^|[\s;/])jq([\s]|$)", script_text), "run_pipeline.sh does not invoke jq."
    assert "graph_etl" in script_text, "run_pipeline.sh does not run the graph_etl program."

    for path in (f"{HOME}/reports.json", f"{HOME}/final_report.txt", f"{HOME}/graph_etl"):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    result = subprocess.run(
        [SCRIPT], cwd=HOME, text=True, stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT, timeout=45
    )
    assert result.returncode == 0, f"run_pipeline.sh failed:\n{result.stdout}"
    assert os.path.isfile(f"{HOME}/graph_etl"), "run_pipeline.sh did not create graph_etl."
    assert os.access(f"{HOME}/graph_etl", os.X_OK), "The generated graph_etl is not executable."


def test_graph_etl_cpp_exists():
    assert os.path.isfile("/home/user/graph_etl.cpp"), "/home/user/graph_etl.cpp does not exist."


def test_run_pipeline_sh_exists_and_executable():
    script_path = "/home/user/run_pipeline.sh"
    assert os.path.isfile(script_path), f"{script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"{script_path} is not executable."


def test_reports_json_content():
    json_path = "/home/user/reports.json"
    assert os.path.isfile(json_path), f"{json_path} does not exist."

    with open(json_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"{json_path} does not contain valid JSON."

    expected_data = [
        {"emp_id": 10, "name": "Judy", "salary": 115000},
        {"emp_id": 5, "name": "Eve", "salary": 110000},
        {"emp_id": 8, "name": "Heidi", "salary": 105000}
    ]

    assert data == expected_data, f"Content of {json_path} does not match expected output. Got: {data}"


def test_final_report_txt_content():
    txt_path = "/home/user/final_report.txt"
    assert os.path.isfile(txt_path), f"{txt_path} does not exist."

    with open(txt_path, "r") as f:
        lines = [line.strip().replace('"', '') for line in f if line.strip()]

    expected_lines = ["Judy", "Eve", "Heidi"]

    assert lines == expected_lines, f"Content of {txt_path} does not match expected output. Got: {lines}"


def test_compiled_tool_on_runtime_generated_graph_and_arguments():
    binary = "/tmp/graph_etl_verified"
    build = subprocess.run(
        ["g++", "-std=c++17", SOURCE, "-o", binary],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=45
    )
    assert build.returncode == 0, f"graph_etl.cpp does not compile as C++17:\n{build.stdout}"

    rng = random.Random(secrets.randbits(64))
    count = 35
    ids = rng.sample(range(1000, 9000), count)
    employees = []
    children = {emp_id: [] for emp_id in ids}

    for i, emp_id in enumerate(ids):
        if i == 0:
            manager = None
        else:
            # This produces a connected hierarchy with both deep and broad branches.
            manager_index = rng.randrange(max(1, i // 2 + 1))
            manager = ids[manager_index]
            children[manager].append(emp_id)
        employees.append({
            "emp_id": emp_id,
            "mgr_id": manager,
            "name": f"Employee_{rng.randrange(100000, 999999)}_{i}",
            "salary": rng.choice([72000, 88000, 100000, 107500, 115000, 125000, 140000, 155000])
        })

    by_id = {e["emp_id"]: e for e in employees}
    rows = employees[:]
    rng.shuffle(rows)

    def expected(manager_id, minimum, limit, offset):
        found = []
        stack = list(children.get(manager_id, []))
        while stack:
            current = stack.pop()
            found.append(by_id[current])
            stack.extend(children.get(current, []))
        found = [e for e in found if e["salary"] >= minimum]
        found.sort(key=lambda e: (-e["salary"], e["emp_id"]))
        found = found[offset:offset + limit]
        return [
            {"emp_id": e["emp_id"], "name": e["name"], "salary": e["salary"]}
            for e in found
        ]

    queries = [
        (ids[0], 100000, 7, 0),
        (ids[0], 88000, 5, 3),
        (ids[1], 72000, 9, 1),
        (ids[2], 115000, 4, 0),
        (ids[-1], 72000, 3, 0),
    ]
    for _ in range(6):
        queries.append((
            ids[rng.randrange(0, count // 2)],
            rng.choice([72000, 90000, 100000, 107500, 120000, 150000]),
            rng.randrange(1, 9),
            rng.randrange(0, 5),
        ))

    with open(CSV_PATH, "rb") as f:
        original_csv = f.read()

    try:
        with open(CSV_PATH, "w", encoding="utf-8", newline="") as f:
            f.write("emp_id,mgr_id,name,salary\n")
            for e in rows:
                manager = "NULL" if e["mgr_id"] is None else str(e["mgr_id"])
                f.write(f'{e["emp_id"]},{manager},{e["name"]},{e["salary"]}\n')

        with tempfile.TemporaryDirectory() as tmpdir:
            for index, (manager, minimum, limit, offset) in enumerate(queries):
                output = os.path.join(tmpdir, f"result_{index}.json")
                run = subprocess.run([
                    binary,
                    "--manager-id", str(manager),
                    "--min-salary", str(minimum),
                    "--limit", str(limit),
                    "--offset", str(offset),
                    "--output", output,
                ], cwd=HOME, text=True, stdout=subprocess.PIPE,
                   stderr=subprocess.STDOUT, timeout=10)
                assert run.returncode == 0, f"graph_etl failed for query {index}:\n{run.stdout}"
                assert os.path.isfile(output), f"graph_etl did not create output for query {index}."
                with open(output, "r", encoding="utf-8") as f:
                    try:
                        actual = json.load(f)
                    except json.JSONDecodeError as exc:
                        assert False, f"Output for query {index} is not valid JSON: {exc}"

                wanted = expected(manager, minimum, limit, offset)
                assert actual == wanted, f"Wrong output for runtime query {index}. Got {actual}, expected {wanted}."
                assert isinstance(actual, list)
                for item in actual:
                    assert set(item.keys()) == {"emp_id", "name", "salary"}, "Each object must have exactly the required keys."
                    assert type(item["emp_id"]) is int
                    assert type(item["name"]) is str
                    assert type(item["salary"]) is int
    finally:
        with open(CSV_PATH, "wb") as f:
            f.write(original_csv)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
