#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import csv
import math
import os
import stat
import subprocess
import textwrap

import pandas as pd
from sklearn.decomposition import TruncatedSVD
from sklearn.feature_extraction.text import TfidfVectorizer

PIPELINE = "/home/user/pipeline.py"
DATA = "/home/user/data.csv"
OUTPUT = "/home/user/output.csv"


def check_pipeline_exists_and_code_constraints():
    assert os.path.isfile(PIPELINE), "/home/user/pipeline.py does not exist."
    mode = os.stat(PIPELINE, follow_symlinks=False).st_mode
    assert stat.S_ISREG(mode), "/home/user/pipeline.py must be a regular file."

    with open(PIPELINE, "r") as f:
        code = f.read()

    ast.parse(code, filename=PIPELINE)

    # Preserve the original source assertions.
    assert 'OPENBLAS_NUM_THREADS' in code, "OPENBLAS_NUM_THREADS not found in pipeline.py."
    assert '"1"' in code or "'1'" in code, "OPENBLAS_NUM_THREADS should be set to '1' in pipeline.py."

    openblas_pos = code.find('OPENBLAS_NUM_THREADS')

    np_pos = code.find('import numpy')
    if np_pos == -1:
        np_pos = code.find('from numpy')

    sk_pos = code.find('import sklearn')
    if sk_pos == -1:
        sk_pos = code.find('from sklearn')

    if np_pos != -1:
        assert openblas_pos < np_pos, "OPENBLAS_NUM_THREADS must be set before importing numpy."
    if sk_pos != -1:
        assert openblas_pos < sk_pos, "OPENBLAS_NUM_THREADS must be set before importing sklearn."


def make_sitecustomize(directory, log_path):
    hook = r'''
import builtins
import os
import random
import sys

_log_path = os.environ["PIPELINE_AUDIT_LOG"]
_original_import = builtins.__import__
_env_recorded = False
_numpy_patched = False


def _write(line):
    with open(_log_path, "a", encoding="utf-8") as f:
        f.write(line + "\n")


def _caller_filename():
    try:
        return os.path.realpath(sys._getframe(2).f_code.co_filename)
    except Exception:
        return "<unknown>"


_original_random_seed = random.seed

def _random_seed(*args, **kwargs):
    value = args[0] if args else kwargs.get("a")
    _write("seed:random:%r:%s" % (value, _caller_filename()))
    return _original_random_seed(*args, **kwargs)

random.seed = _random_seed


def _patch_numpy_seed():
    global _numpy_patched
    if _numpy_patched:
        return
    numpy = sys.modules.get("numpy")
    if numpy is None or not hasattr(numpy, "random"):
        return
    original = numpy.random.seed
    if getattr(original, "_pipeline_audit_wrapper", False):
        _numpy_patched = True
        return

    def wrapped(*args, **kwargs):
        value = args[0] if args else kwargs.get("seed")
        _write("seed:numpy:%r:%s" % (value, _caller_filename()))
        return original(*args, **kwargs)

    wrapped._pipeline_audit_wrapper = True
    numpy.random.seed = wrapped
    _numpy_patched = True


def _tracked_import(name, globals=None, locals=None, fromlist=(), level=0):
    global _env_recorded
    root = name.split(".", 1)[0]
    if root in {"numpy", "pandas", "sklearn", "scipy"} and not _env_recorded:
        _write("openblas:%s" % os.environ.get("OPENBLAS_NUM_THREADS", "<unset>"))
        _env_recorded = True
    result = _original_import(name, globals, locals, fromlist, level)
    if root in {"numpy", "pandas", "sklearn", "scipy"}:
        _patch_numpy_seed()
    return result

builtins.__import__ = _tracked_import
'''
    with open(os.path.join(directory, "sitecustomize.py"), "w", encoding="utf-8") as f:
        f.write(textwrap.dedent(hook))


def run_pipeline(tmp_path, run_number):
    hook_dir = tmp_path / f"hook_{run_number}"
    hook_dir.mkdir()
    log_path = tmp_path / f"audit_{run_number}.log"
    make_sitecustomize(str(hook_dir), str(log_path))

    if os.path.lexists(OUTPUT):
        os.remove(OUTPUT)

    env = os.environ.copy()
    env["OPENBLAS_NUM_THREADS"] = "7"
    env["PIPELINE_AUDIT_LOG"] = str(log_path)
    env["PYTHONPATH"] = str(hook_dir) + (os.pathsep + env["PYTHONPATH"] if env.get("PYTHONPATH") else "")

    result = subprocess.run(
        ["python3", PIPELINE],
        cwd="/home/user",
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=60,
    )
    assert result.returncode == 0, f"pipeline.py failed:\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
    assert os.path.isfile(OUTPUT), "/home/user/output.csv does not exist after running pipeline.py."

    lines = log_path.read_text(encoding="utf-8").splitlines() if log_path.exists() else []
    openblas = [line for line in lines if line.startswith("openblas:")]
    assert openblas, "pipeline.py did not import the required numerical libraries."
    assert openblas[0] == "openblas:1", "OPENBLAS_NUM_THREADS was not actually set to '1' before the first numerical-library import."

    expected_file = os.path.realpath(PIPELINE)
    random_seeded = any(line == f"seed:random:42:{expected_file}" for line in lines)
    numpy_seeded = any(line == f"seed:numpy:42:{expected_file}" for line in lines)
    assert random_seeded, "pipeline.py did not actually call standard random.seed(42)."
    assert numpy_seeded, "pipeline.py did not actually call numpy.random.seed(42)."

    with open(OUTPUT, "rb") as f:
        return f.read()


def check_original_output():
    expected_rows = [
        ["1", "10.5000", "19", "0.3015", "-0.3804"],
        ["2", "15.0000", "23", "0.3015", "-0.3804"],
        ["3", "20.0000", "31", "0.0000", "0.0000"],
        ["4", "12.5000", "26", "0.0000", "0.0000"],
        ["5", "9.9900", "36", "0.9070", "0.2529"]
    ]

    with open(OUTPUT, "r") as f:
        reader = csv.reader(f)
        header = next(reader)
        assert header == ["id", "price", "text_length", "emb_0", "emb_1"], "CSV header is incorrect. Expected: id, price, text_length, emb_0, emb_1"

        rows = list(reader)
        assert len(rows) == len(expected_rows), f"Incorrect number of rows in output.csv. Expected {len(expected_rows)}, got {len(rows)}."

        for i, (row, exp_row) in enumerate(zip(rows, expected_rows)):
            assert row[0] == exp_row[0], f"Row {i+1}: id mismatch."
            assert math.isclose(float(row[1]), float(exp_row[1]), abs_tol=1e-4), f"Row {i+1}: price mismatch."
            assert row[2] == exp_row[2], f"Row {i+1}: text_length mismatch."
            assert math.isclose(abs(float(row[3])), abs(float(exp_row[3])), abs_tol=1e-3), f"Row {i+1}: emb_0 magnitude mismatch. Expected ~{abs(float(exp_row[3]))}, got {abs(float(row[3]))}."
            assert math.isclose(abs(float(row[4])), abs(float(exp_row[4])), abs_tol=1e-3), f"Row {i+1}: emb_1 magnitude mismatch. Expected ~{abs(float(exp_row[4]))}, got {abs(float(row[4]))}."


def write_dynamic_data():
    rows = [
        [101, "copper river lantern", 3.25],
        [207, "lantern signal over quiet water", 18.75],
        [309, "violet engine maps distant stars", 7.5],
        [412, "copper engine and river maps", 22.125],
        [518, "quiet orchard beneath violet skies", 4.0],
        [623, "signal stars guide the orchard", 13.4],
        [777, "water wheels power a distant engine", 31.99],
    ]
    with open(DATA, "w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(["id", "text", "price"])
        writer.writerows(rows)


def check_dynamic_output():
    source = pd.read_csv(DATA)
    matrix = TfidfVectorizer().fit_transform(source["text"])
    embedding = TruncatedSVD(n_components=2, random_state=42).fit_transform(matrix)

    with open(OUTPUT, newline="", encoding="utf-8") as f:
        reader = csv.reader(f)
        header = next(reader)
        rows = list(reader)

    assert header == ["id", "price", "text_length", "emb_0", "emb_1"]
    assert len(rows) == len(source)

    for i, row in enumerate(rows):
        assert row[0] == str(source.iloc[i]["id"])
        assert math.isclose(float(row[1]), float(source.iloc[i]["price"]), abs_tol=1e-4)
        assert int(row[2]) == len(source.iloc[i]["text"])
        assert math.isclose(abs(float(row[3])), abs(round(float(embedding[i, 0]), 4)), abs_tol=1e-3)
        assert math.isclose(abs(float(row[4])), abs(round(float(embedding[i, 1]), 4)), abs_tol=1e-3)


def test_pipeline_end_to_end_and_reproducible(tmp_path):
    check_pipeline_exists_and_code_constraints()

    with open(DATA, "rb") as f:
        original_data = f.read()
    initial_output = None
    if os.path.isfile(OUTPUT):
        with open(OUTPUT, "rb") as f:
            initial_output = f.read()
    restored_output = initial_output

    try:
        first_original = run_pipeline(tmp_path, 1)
        check_original_output()
        second_original = run_pipeline(tmp_path, 2)
        assert first_original == second_original, "Two runs on the original input produced different output.csv bytes."
        restored_output = second_original

        write_dynamic_data()
        first_dynamic = run_pipeline(tmp_path, 3)
        check_dynamic_output()
        second_dynamic = run_pipeline(tmp_path, 4)
        check_dynamic_output()
        assert first_dynamic == second_dynamic, "Two runs on the dynamic input produced different output.csv bytes."
    finally:
        with open(DATA, "wb") as f:
            f.write(original_data)
        if restored_output is None:
            if os.path.lexists(OUTPUT):
                os.remove(OUTPUT)
        else:
            with open(OUTPUT, "wb") as f:
                f.write(restored_output)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
