#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/test_final_state.py
import csv
import math
import os
import random
import subprocess
import uuid

DATA_PATH = "/home/user/data.csv"
OUTPUT_PATH = "/home/user/top3.txt"

with open(DATA_PATH, "rb") as f:
    original_data = f.read()


def output_lines():
    assert os.path.isfile(OUTPUT_PATH), f"File {OUTPUT_PATH} is missing. The Go program did not create the output file."
    with open(OUTPUT_PATH, "r") as f:
        return [line.strip() for line in f if line.strip()]


def find_go_programs():
    roots = [p for p in ("/home/user", "/tmp", "/workspace") if os.path.isdir(p)]
    ignored = {".git", ".cache", "vendor", "pkg", "bin"}
    by_dir = {}
    for root in roots:
        for current, dirs, files in os.walk(root):
            dirs[:] = [d for d in dirs if d not in ignored and not d.startswith("go-build")]
            go_files = [
                os.path.join(current, name)
                for name in files
                if name.endswith(".go") and not name.endswith("_test.go")
            ]
            if go_files:
                by_dir[current] = sorted(go_files)
    return [by_dir[d] for d in sorted(by_dir)]


def run_program(files):
    if os.path.exists(OUTPUT_PATH):
        os.remove(OUTPUT_PATH)
    result = subprocess.run(
        ["go", "run", *files],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        "The submitted Go program failed when executed.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(OUTPUT_PATH), "The executed Go program did not create /home/user/top3.txt."


def restore_original():
    with open(DATA_PATH, "wb") as f:
        f.write(original_data)


def choose_program():
    candidates = find_go_programs()
    assert candidates, "No Go source program was found."
    errors = []
    for files in candidates:
        try:
            restore_original()
            run_program(files)
            if output_lines() == ["D", "A", "B"]:
                return files
            errors.append(f"{files}: produced {output_lines()!r}")
        except Exception as exc:
            errors.append(f"{files}: {exc}")
    raise AssertionError("No submitted Go program produced the required result when executed.\n" + "\n".join(errors))


def reduced(features):
    values = [0.0 if value == "" else float(value) for value in features]
    result = []
    for i in (0, 2, 4):
        value = values[i] + values[i + 1]
        result.append(max(-10.0, min(10.0, value)))
    return result


def expected_top3(rows):
    vectors = {row[0]: reduced(row[1:]) for row in rows}
    target = vectors["TARGET"]
    ranked = []
    for item_id, vector in vectors.items():
        if item_id == "TARGET":
            continue
        distance = math.sqrt(sum((a - b) ** 2 for a, b in zip(target, vector)))
        ranked.append((distance, item_id))
    ranked.sort(key=lambda item: item[0])
    for left, right in zip(ranked, ranked[1:]):
        assert abs(left[0] - right[0]) > 1e-9, "Generated test unexpectedly contained tied distances."
    return [item_id for _, item_id in ranked[:3]]


def make_case(rng):
    def number(low=-18.0, high=18.0):
        return format(rng.uniform(low, high), ".12g")

    rows = [["TARGET", number(-6, 6), number(-6, 6), "14", "3", "-13", "-4"]]
    for _ in range(9):
        item_id = "ITEM_" + uuid.uuid4().hex[:12]
        features = ["" if rng.random() < 0.18 else number() for _ in range(6)]
        rows.append([item_id, *features])

    rows[1][1] = ""
    rows[2][1], rows[2][2] = "25", "9"
    rows[3][5], rows[3][6] = "-28", "-7"
    return rows


def write_rows(rows):
    with open(DATA_PATH, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["ID", "f1", "f2", "f3", "f4", "f5", "f6"])
        writer.writerows(rows)


def test_top3_txt_exists_and_content():
    file_path = "/home/user/top3.txt"
    assert os.path.isfile(file_path), f"File {file_path} is missing. The Go program did not create the output file."

    with open(file_path, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = ["D", "A", "B"]

    assert len(lines) == 3, f"Expected exactly 3 IDs in {file_path}, but found {len(lines)}."

    for i, expected in enumerate(expected_lines):
        assert lines[i] == expected, f"Expected line {i+1} to be '{expected}', but got '{lines[i]}'. Check your distance calculations and sorting."


def test_data_csv_untouched():
    file_path = "/home/user/data.csv"
    assert os.path.isfile(file_path), f"File {file_path} is missing. The input data should not be deleted."


program = None
try:
    program = choose_program()
    rng = random.SystemRandom()
    for _ in range(3):
        rows = make_case(rng)
        expected = expected_top3(rows)
        write_rows(rows)
        run_program(program)
        actual = output_lines()
        assert len(actual) == 3, f"Expected exactly 3 IDs, but found {len(actual)}."
        assert actual == expected, f"Go program returned {actual!r}; expected {expected!r} for a generated input."

    restore_original()
    run_program(program)
    test_top3_txt_exists_and_content()
    test_data_csv_untouched()
finally:
    restore_original()
PY_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
