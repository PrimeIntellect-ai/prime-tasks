#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import csv
import os
import re
import secrets
import shutil
import subprocess
import tempfile
from datetime import datetime, timedelta

import pytest

LOG_DIR = "/home/user/config_logs"
OUTPUT_CSV = "/home/user/anomalies.csv"


def compute_expected_anomalies(log_dir):
    anomalies = []
    pattern = re.compile(r"\[(.*?)\]\s+.*current_load=([0-9.]+)")

    if not os.path.exists(log_dir):
        return anomalies

    for filename in os.listdir(log_dir):
        if not filename.endswith(".log"):
            continue
        server = filename[:-4]
        filepath = os.path.join(log_dir, filename)

        data = {}
        with open(filepath, "r") as f:
            for line in f:
                match = pattern.search(line)
                if match:
                    dt = datetime.strptime(match.group(1), "%Y-%m-%d %H:%M:%S")
                    dt = dt.replace(second=0, microsecond=0)
                    load = float(match.group(2))
                    data[dt] = load

        if not data:
            continue

        sorted_dts = sorted(data.keys())
        min_dt = sorted_dts[0]
        max_dt = sorted_dts[-1]

        current_dt = min_dt
        last_load = data[min_dt]
        prev_load = None

        while current_dt <= max_dt:
            if current_dt in data:
                current_load = data[current_dt]
                last_load = current_load
            else:
                current_load = last_load

            if prev_load is not None:
                increase = current_load - prev_load
                if increase > 45.0:
                    anomalies.append({
                        "Timestamp": current_dt.strftime("%Y-%m-%d %H:%M:%S"),
                        "Server": server,
                        "Increase": round(increase, 1),
                    })
            prev_load = current_load
            current_dt += timedelta(minutes=1)

    anomalies.sort(key=lambda x: (x["Timestamp"], x["Server"]))
    return anomalies


def read_and_check_csv(expected):
    assert os.path.exists(OUTPUT_CSV), f"Output file {OUTPUT_CSV} does not exist."
    assert os.path.isfile(OUTPUT_CSV), f"{OUTPUT_CSV} is not a file."

    actual = []
    with open(OUTPUT_CSV, "r", newline="") as f:
        reader = csv.DictReader(f)
        assert reader.fieldnames == ["Timestamp", "Server", "Increase"], \
            f"CSV header is incorrect. Expected ['Timestamp', 'Server', 'Increase'], got {reader.fieldnames}"
        for row in reader:
            try:
                row["Increase"] = float(row["Increase"])
            except (TypeError, ValueError):
                pytest.fail(f"Invalid Increase value in CSV: {row.get('Increase')}")
            actual.append(row)

    formatted_expected = [dict(item, Increase=float(item["Increase"])) for item in expected]
    assert len(actual) == len(formatted_expected), \
        f"Expected {len(formatted_expected)} anomalies, but found {len(actual)}."

    for i, (observed, wanted) in enumerate(zip(actual, formatted_expected)):
        assert observed["Timestamp"] == wanted["Timestamp"], \
            f"Row {i+1}: Expected Timestamp {wanted['Timestamp']}, got {observed['Timestamp']}"
        assert observed["Server"] == wanted["Server"], \
            f"Row {i+1}: Expected Server {wanted['Server']}, got {observed['Server']}"
        assert observed["Increase"] == wanted["Increase"], \
            f"Row {i+1}: Expected Increase {wanted['Increase']}, got {observed['Increase']}"


def test_output_csv_exists():
    assert os.path.exists(OUTPUT_CSV), f"Output file {OUTPUT_CSV} was not created."
    assert os.path.isfile(OUTPUT_CSV), f"{OUTPUT_CSV} is not a file."


def test_output_csv_content():
    expected_anomalies = compute_expected_anomalies(LOG_DIR)
    read_and_check_csv(expected_anomalies)


def script_uses_required_techniques(path):
    try:
        with open(path, "r", encoding="utf-8") as f:
            source = f.read()
        tree = ast.parse(source, filename=path)
    except (OSError, UnicodeError, SyntaxError):
        return False, "not a readable, valid Python program"

    imported_modules = set()
    regex_imported_names = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                imported_modules.add(alias.name)
                if alias.name == "re":
                    regex_imported_names.add(alias.asname or "re")
        elif isinstance(node, ast.ImportFrom):
            module = node.module or ""
            imported_modules.add(module)
            if module == "re":
                for alias in node.names:
                    if alias.name in {"compile", "search", "match", "fullmatch", "findall", "finditer"}:
                        regex_imported_names.add(alias.asname or alias.name)

    def dotted_name(node):
        parts = []
        while isinstance(node, ast.Attribute):
            parts.append(node.attr)
            node = node.value
        if isinstance(node, ast.Name):
            parts.append(node.id)
            return ".".join(reversed(parts))
        return ""

    regex_call = False
    parallel_constructor = False
    parallel_work_call = False
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        name = dotted_name(node.func)
        tail = name.rsplit(".", 1)[-1]
        if tail in {"compile", "search", "match", "fullmatch", "findall", "finditer"}:
            root = name.split(".", 1)[0]
            if root in regex_imported_names:
                regex_call = True
        if tail in {"Pool", "ThreadPool", "Process", "ThreadPoolExecutor", "ProcessPoolExecutor", "Parallel"}:
            parallel_constructor = True
        if tail in {"map", "imap", "imap_unordered", "starmap", "submit", "start"}:
            parallel_work_call = True

    parallel_import = any(
        module == "multiprocessing"
        or module.startswith("multiprocessing.")
        or module == "concurrent.futures"
        or module.startswith("concurrent.futures.")
        or module == "joblib"
        or module.startswith("joblib.")
        for module in imported_modules
    )

    if not regex_call:
        return False, "does not import and call a regular-expression parsing function"
    if not (parallel_import and parallel_constructor and parallel_work_call):
        return False, "does not construct and use a multiprocessing or parallel executor"
    return True, ""


def find_python_scripts():
    scripts = []
    for root, dirs, files in os.walk("/home/user"):
        dirs[:] = [d for d in dirs if not d.startswith(".") and d != "__pycache__"]
        for filename in files:
            path = os.path.join(root, filename)
            if (filename.endswith(".py") and os.path.isfile(path)
                    and not os.path.islink(path) and os.path.getsize(path) > 0):
                scripts.append(path)
    return sorted(scripts)


def write_dynamic_fixture():
    os.makedirs(LOG_DIR, exist_ok=True)
    for name in os.listdir(LOG_DIR):
        path = os.path.join(LOG_DIR, name)
        if os.path.isdir(path):
            shutil.rmtree(path)
        else:
            os.unlink(path)

    day_offset = secrets.randbelow(900)
    base_time = datetime(2021, 1, 1, 6 + secrets.randbelow(10), secrets.randbelow(20)) + timedelta(days=day_offset)
    first_id = 10000 + secrets.randbelow(40000)
    second_id = first_id + 50000
    quiet_id = second_id + 50000
    first_load = (80 + secrets.randbelow(120)) / 10.0
    second_load = (200 + secrets.randbelow(100)) / 10.0
    first_jump = (461 + secrets.randbelow(80)) / 10.0
    second_jump = (451 + secrets.randbelow(90)) / 10.0

    def stamp(offset):
        return (base_time + timedelta(minutes=offset)).strftime("%Y-%m-%d %H:%M:%S")

    fixtures = {
        f"server_{second_id}.log": [
            f"[{stamp(0)}] Config sync complete. current_load={second_load:.1f}\n",
            "this line is malformed and must be ignored\n",
            f"[{stamp(3)}]   Config sync complete.  current_load={second_load + 45.0:.1f}\n",
            f"[{stamp(4)}] Config sync complete. current_load={second_load + 45.0 + second_jump:.1f}\n",
        ],
        f"server_{first_id}.log": [
            f"[{stamp(0)}] Config sync complete. current_load={first_load:.1f}\n",
            f"[{stamp(1)}]  Config sync complete. current_load={first_load + 2.0:.1f}\n",
            f"[{stamp(4)}] Config sync complete.  current_load={first_load + 2.0 + first_jump:.1f}\n",
            f"[{stamp(5)}] Config sync complete. current_load={first_load + 1.0 + first_jump:.1f}\n",
        ],
        f"server_{quiet_id}.log": [
            f"[{stamp(0)}] Config sync complete. current_load=9.0\n",
            f"[{stamp(2)}] Config sync complete. current_load=30.0\n",
        ],
    }

    for filename, lines in fixtures.items():
        with open(os.path.join(LOG_DIR, filename), "w") as f:
            f.writelines(lines)


def test_python_script_is_implemented_and_executable():
    scripts = find_python_scripts()
    assert scripts, "No Python script was created under /home/user."

    backup_root = tempfile.mkdtemp(prefix="config-verifier-")
    backup_logs = os.path.join(backup_root, "config_logs")
    shutil.copytree(LOG_DIR, backup_logs)
    original_csv = None
    if os.path.isfile(OUTPUT_CSV):
        with open(OUTPUT_CSV, "rb") as f:
            original_csv = f.read()

    failures = []
    qualified = 0
    try:
        for script in scripts:
            valid, reason = script_uses_required_techniques(script)
            if not valid:
                failures.append(f"{script}: {reason}")
                continue
            qualified += 1
            try:
                write_dynamic_fixture()
                if os.path.lexists(OUTPUT_CSV):
                    if os.path.isdir(OUTPUT_CSV) and not os.path.islink(OUTPUT_CSV):
                        shutil.rmtree(OUTPUT_CSV)
                    else:
                        os.unlink(OUTPUT_CSV)
                expected = compute_expected_anomalies(LOG_DIR)
                result = subprocess.run(
                    ["python3", script],
                    cwd="/home/user",
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    text=True,
                    timeout=30,
                )
                assert result.returncode == 0, \
                    f"script exited {result.returncode}: {result.stderr[-1000:]}"
                read_and_check_csv(expected)
                return
            except (AssertionError, subprocess.TimeoutExpired, OSError) as exc:
                failures.append(f"{script}: {exc}")

        assert qualified > 0, "No Python script uses both regex parsing and parallel processing. " + "; ".join(failures)
        pytest.fail("No qualifying Python script correctly processed a fresh log fixture when executed. " + "; ".join(failures))
    finally:
        if os.path.exists(LOG_DIR):
            shutil.rmtree(LOG_DIR)
        shutil.copytree(backup_logs, LOG_DIR)
        if os.path.lexists(OUTPUT_CSV):
            if os.path.isdir(OUTPUT_CSV) and not os.path.islink(OUTPUT_CSV):
                shutil.rmtree(OUTPUT_CSV)
            else:
                os.unlink(OUTPUT_CSV)
        if original_csv is not None:
            with open(OUTPUT_CSV, "wb") as f:
                f.write(original_csv)
        shutil.rmtree(backup_root, ignore_errors=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
