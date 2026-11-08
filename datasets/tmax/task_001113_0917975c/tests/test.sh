#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import io
import multiprocessing
import os
import re
import shutil
import signal
import subprocess
import tempfile
import time

OUTPUT_PATH = "/home/user/clean_long_survey.csv"
METADATA_PATH = "/home/user/metadata.csv"
SURVEY_DIR = "/home/user/survey_data"
SURVEY_FILES = ["survey_NA.csv", "survey_EU.csv", "survey_APAC.csv"]
QUESTIONS = ["q1_satisfaction", "q2_workload", "q3_culture", "q4_management"]
HEADER = ["emp_id", "hire_year", "office_city", "question", "score"]


def is_valid_emp_id(emp_id):
    return bool(re.match(r"^EMP\d{5}$", emp_id))


def is_valid_score(score_str):
    try:
        score = int(score_str)
        return 1 <= score <= 10
    except (ValueError, TypeError):
        return False


def get_expected_data():
    metadata = {}
    with open(METADATA_PATH, "r", newline="") as f:
        for row in csv.DictReader(f):
            metadata[row["emp_id"]] = {
                "hire_year": row["hire_year"],
                "office_city": row["office_city"],
            }

    expected_rows = []
    for filename in SURVEY_FILES:
        filepath = os.path.join(SURVEY_DIR, filename)
        with open(filepath, "r", newline="") as f:
            for row in csv.DictReader(f):
                emp_id = row["emp_id"]
                if not is_valid_emp_id(emp_id):
                    continue
                if not all(is_valid_score(row[q]) for q in QUESTIONS):
                    continue
                if emp_id not in metadata:
                    continue
                for q in QUESTIONS:
                    expected_rows.append({
                        "emp_id": emp_id,
                        "hire_year": metadata[emp_id]["hire_year"],
                        "office_city": metadata[emp_id]["office_city"],
                        "question": q,
                        "score": str(int(row[q])),
                    })

    expected_rows.sort(key=lambda x: (x["emp_id"], x["question"]))
    return expected_rows


def script_candidates():
    excluded = {
        os.path.realpath(OUTPUT_PATH),
        os.path.realpath(METADATA_PATH),
    }
    candidates = []
    for root, dirs, files in os.walk("/home/user"):
        dirs[:] = [d for d in dirs if not d.startswith(".") and os.path.join(root, d) != SURVEY_DIR]
        for name in files:
            path = os.path.join(root, name)
            if os.path.realpath(path) in excluded or name.endswith(".csv"):
                continue
            try:
                with open(path, "rb") as f:
                    data = f.read(1024 * 1024)
                text = data.decode("utf-8")
            except (OSError, UnicodeDecodeError):
                continue

            first = text.splitlines()[0] if text.splitlines() else ""
            lower = name.lower()
            if lower.endswith(".py") or "python" in first:
                candidates.append((path, ["python3", path]))
            elif lower.endswith((".sh", ".bash")) or first.startswith("#!/bin/sh") or first.startswith("#!/bin/bash"):
                candidates.append((path, ["bash", path]))
            elif first.startswith("#!"):
                candidates.append((path, [path]))
            elif "." not in name:
                try:
                    compile(text, path, "exec")
                    candidates.append((path, ["python3", path]))
                except SyntaxError:
                    pass
    candidates.sort(key=lambda item: item[0])
    return candidates


def fifo_writer(fifo_path, marker_path, all_markers, payload):
    fd = os.open(fifo_path, os.O_WRONLY)
    try:
        with open(marker_path, "w") as marker:
            marker.write("opened")
        deadline = time.time() + 6
        while time.time() < deadline and not all(os.path.exists(p) for p in all_markers):
            time.sleep(0.02)
        if all(os.path.exists(p) for p in all_markers):
            os.write(fd, payload.encode("utf-8"))
    finally:
        os.close(fd)


def run_command(command, timeout):
    proc = subprocess.Popen(
        command,
        cwd="/home/user",
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    try:
        return proc.wait(timeout=timeout)
    except subprocess.TimeoutExpired:
        os.killpg(proc.pid, signal.SIGKILL)
        proc.wait()
        return None


def read_actual_output():
    if not os.path.isfile(OUTPUT_PATH):
        return None, None
    with open(OUTPUT_PATH, "r", newline="") as f:
        reader = csv.DictReader(f)
        return reader.fieldnames, list(reader)


def expected_from_payloads(payloads):
    metadata = {}
    with open(METADATA_PATH, "r", newline="") as f:
        for row in csv.DictReader(f):
            metadata[row["emp_id"]] = row

    rows = []
    for payload in payloads.values():
        for row in csv.DictReader(io.StringIO(payload)):
            emp_id = row["emp_id"]
            if not is_valid_emp_id(emp_id):
                continue
            if not all(is_valid_score(row[q]) for q in QUESTIONS):
                continue
            if emp_id not in metadata:
                continue
            for q in QUESTIONS:
                rows.append({
                    "emp_id": emp_id,
                    "hire_year": metadata[emp_id]["hire_year"],
                    "office_city": metadata[emp_id]["office_city"],
                    "question": q,
                    "score": str(int(row[q])),
                })
    rows.sort(key=lambda x: (x["emp_id"], x["question"]))
    return rows


def exercise_candidate(command):
    payloads = {
        "survey_NA.csv": (
            "emp_id,q1_satisfaction,q2_workload,q3_culture,q4_management\n"
            "EMP00001,2,3,4,5\n"
            "EMP00004,1,0,3,4\n"
        ),
        "survey_EU.csv": (
            "emp_id,q1_satisfaction,q2_workload,q3_culture,q4_management\n"
            "EMP00005,10,9,8,7\n"
            "EMP00BAD,5,5,5,5\n"
        ),
        "survey_APAC.csv": (
            "emp_id,q1_satisfaction,q2_workload,q3_culture,q4_management\n"
            "EMP00003,6,5,4,3\n"
            "EMP00008,4,4,4,4\n"
        ),
    }
    expected = expected_from_payloads(payloads)
    backup = tempfile.mkdtemp(prefix="survey_backup_")
    backup_dir = os.path.join(backup, "survey_data")
    marker_dir = tempfile.mkdtemp(prefix="survey_markers_")
    writers = []

    os.rename(SURVEY_DIR, backup_dir)
    os.mkdir(SURVEY_DIR)
    try:
        markers = [os.path.join(marker_dir, str(i)) for i in range(len(SURVEY_FILES))]
        for filename in SURVEY_FILES:
            os.mkfifo(os.path.join(SURVEY_DIR, filename), 0o666)
        for i, filename in enumerate(SURVEY_FILES):
            process = multiprocessing.Process(
                target=fifo_writer,
                args=(os.path.join(SURVEY_DIR, filename), markers[i], markers, payloads[filename]),
            )
            process.start()
            writers.append(process)

        rc = run_command(command, 5)
        for process in writers:
            process.join(timeout=0.5)
        opened_together = all(os.path.exists(p) for p in markers)
        fieldnames, actual = read_actual_output()
        return rc == 0 and opened_together and fieldnames == HEADER and actual == expected
    finally:
        for process in writers:
            if process.is_alive():
                process.terminate()
            process.join(timeout=1)
        shutil.rmtree(SURVEY_DIR, ignore_errors=True)
        os.rename(backup_dir, SURVEY_DIR)
        shutil.rmtree(backup, ignore_errors=True)
        shutil.rmtree(marker_dir, ignore_errors=True)


def test_script_exists_and_processes_regions_in_parallel():
    candidates = script_candidates()
    assert candidates, "No processing script was written under /home/user."

    successful = None
    for path, command in candidates:
        if exercise_candidate(command):
            successful = (path, command)
            break

    assert successful is not None, (
        "No submitted script both processed changed survey inputs correctly and opened all three "
        "regional survey files concurrently."
    )

    path, command = successful
    rc = run_command(command, 15)
    assert rc == 0, f"The processing script {path} failed when rerun on the original inputs."


def test_output_file_exists():
    assert os.path.isfile(OUTPUT_PATH), f"The output file {OUTPUT_PATH} does not exist."


def test_output_file_header():
    with open(OUTPUT_PATH, "r", newline="") as f:
        reader = csv.reader(f)
        header = next(reader, None)
    expected_header = ["emp_id", "hire_year", "office_city", "question", "score"]
    assert header == expected_header, f"Expected header {expected_header}, but got {header}"


def test_output_file_contents_and_sorting():
    expected_data = get_expected_data()

    actual_data = []
    with open(OUTPUT_PATH, "r", newline="") as f:
        reader = csv.DictReader(f)
        for row in reader:
            actual_data.append(row)

    assert len(actual_data) == len(expected_data), f"Expected {len(expected_data)} rows, but got {len(actual_data)} rows."

    for i, (actual, expected) in enumerate(zip(actual_data, expected_data)):
        assert actual == expected, f"Row {i+1} mismatch. Expected {expected}, but got {actual}. Check sorting and data validation."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
