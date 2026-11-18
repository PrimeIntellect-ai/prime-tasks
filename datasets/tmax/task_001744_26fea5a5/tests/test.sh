#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib.util
import os
import secrets
import shutil
import sqlite3
import subprocess
import tempfile

import pytest

BASE = "/home/user/ticket_4092"
RUN_SH = os.path.join(BASE, "run.sh")
ANALYZE = os.path.join(BASE, "analyze.py")
CALC = os.path.join(BASE, "libs", "calc.py")
DB = os.path.join(BASE, "records.db")
INPUT = os.path.join(BASE, "input_files.txt")
RESULT = os.path.join(BASE, "result.txt")
WRONG_CALC = "/tmp/wrong_path/calc.py"


def execute_pipeline():
    if os.path.exists(RESULT):
        os.remove(RESULT)
    proc = subprocess.run(
        [RUN_SH],
        cwd=BASE,
        env={**os.environ, "CALC_LIB_PATH": "/tmp/wrong_path"},
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )
    assert proc.returncode == 0, (
        f"run.sh failed with exit code {proc.returncode}\n"
        f"stdout:\n{proc.stdout}\nstderr:\n{proc.stderr}"
    )
    assert os.path.isfile(RESULT), f"Expected output file {RESULT} is missing after running run.sh"


def expected_from_current_inputs():
    with open(INPUT, "r") as f:
        filenames = [line.strip() for line in f if line.strip()]

    conn = sqlite3.connect(DB)
    try:
        cursor = conn.cursor()
        values = []
        for filename in filenames:
            cursor.execute("SELECT value FROM measurements WHERE filename = ?", (filename,))
            row = cursor.fetchone()
            if row:
                values.append(row[0])
    finally:
        conn.close()

    expected_m_avg = []
    window_size = 3
    if len(values) >= window_size:
        for i in range(len(values) - window_size + 1):
            expected_m_avg.append(sum(values[i:i + window_size]) / window_size)
    return ",".join(f"{x:.2f}" for x in expected_m_avg) + "\n"


def test_required_artifacts_and_execute_run_sh():
    assert os.path.isfile(RUN_SH), f"Required script {RUN_SH} is missing"
    assert os.access(RUN_SH, os.X_OK), f"Required script {RUN_SH} is not executable"
    assert os.path.isfile(ANALYZE), f"Required script {ANALYZE} is missing"
    assert os.path.isfile(CALC), f"Required math library {CALC} is missing"
    execute_pipeline()


def test_result_file_exists():
    result_file = "/home/user/ticket_4092/result.txt"
    assert os.path.isfile(result_file), f"Expected output file {result_file} is missing. Did you run the script?"


def test_result_file_content():
    db_path = "/home/user/ticket_4092/records.db"
    input_list = "/home/user/ticket_4092/input_files.txt"
    result_file = "/home/user/ticket_4092/result.txt"

    assert os.path.isfile(db_path), f"Database {db_path} is missing."
    assert os.path.isfile(input_list), f"Input list {input_list} is missing."

    expected_output = expected_from_current_inputs()
    with open(result_file, "r") as f:
        actual_output = f.read()

    assert actual_output == expected_output, (
        f"The content of {result_file} is incorrect.\n"
        f"Expected: {expected_output!r}\nActual:   {actual_output!r}\n"
        "Ensure the environment variable, file parsing logic, and moving average logic are fixed."
    )


def test_library_and_pipeline_on_derived_inputs():
    # Test the submitted library directly, including the final valid window.
    sample = [secrets.randbelow(80) - 20 for _ in range(7)]
    spec = importlib.util.spec_from_file_location("submitted_calc", CALC)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    actual = module.moving_average(sample, 3)
    expected = [sum(sample[i:i + 3]) / 3 for i in range(len(sample) - 3 + 1)]
    assert actual == pytest.approx(expected), "libs/calc.py does not return every valid 3-item window"

    token = secrets.token_hex(6)
    filenames = [
        f"alpha {token}.csv",
        f"beta_{token}.csv",
        f"gamma report {token}.csv",
        f"delta {token}.csv",
        f"epsilon_{token}.csv",
        f"zeta final {token}.csv",
    ]
    values = [(secrets.randbelow(400) - 100) / 4.0 for _ in filenames]
    expected_output = ",".join(
        f"{sum(values[i:i + 3]) / 3:.2f}" for i in range(len(values) - 3 + 1)
    ) + "\n"

    with tempfile.TemporaryDirectory() as backup:
        shutil.copy2(DB, os.path.join(backup, "records.db"))
        shutil.copy2(INPUT, os.path.join(backup, "input_files.txt"))
        wrong_existed = os.path.exists(WRONG_CALC)
        if wrong_existed:
            shutil.copy2(WRONG_CALC, os.path.join(backup, "wrong_calc.py"))

        try:
            for suffix in ("", "-wal", "-shm", "-journal"):
                path = DB + suffix
                if os.path.exists(path):
                    os.remove(path)

            conn = sqlite3.connect(DB)
            try:
                conn.execute("CREATE TABLE measurements (id INTEGER PRIMARY KEY, filename TEXT, value REAL)")
                conn.executemany(
                    "INSERT INTO measurements (filename, value) VALUES (?, ?)",
                    list(zip(filenames, values)),
                )
                conn.commit()
            finally:
                conn.close()

            with open(INPUT, "w") as f:
                f.write("\n".join(filenames) + "\n")

            os.makedirs(os.path.dirname(WRONG_CALC), exist_ok=True)
            with open(WRONG_CALC, "w") as f:
                f.write("raise RuntimeError('the wrong math library was loaded')\n")

            execute_pipeline()
            with open(RESULT, "r") as f:
                actual_output = f.read()
            assert actual_output == expected_output, (
                "run.sh/analyze.py failed on derived filenames containing spaces or omitted a moving-average window.\n"
                f"Expected: {expected_output!r}\nActual:   {actual_output!r}"
            )
        finally:
            for suffix in ("", "-wal", "-shm", "-journal"):
                path = DB + suffix
                if os.path.exists(path):
                    os.remove(path)
            shutil.copy2(os.path.join(backup, "records.db"), DB)
            shutil.copy2(os.path.join(backup, "input_files.txt"), INPUT)
            if wrong_existed:
                shutil.copy2(os.path.join(backup, "wrong_calc.py"), WRONG_CALC)
            elif os.path.exists(WRONG_CALC):
                os.remove(WRONG_CALC)
            # Leave result.txt in the required final state for the original dataset.
            execute_pipeline()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
