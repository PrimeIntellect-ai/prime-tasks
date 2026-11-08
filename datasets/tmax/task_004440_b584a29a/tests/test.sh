#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import ast
import csv
import glob
import json
import os
import re
import secrets
import shutil
import stat
import subprocess
import sys
import tempfile

import pytest

HOME = "/home/user"
CONFIG_DIR = "/home/user/data/configs"
METADATA = "/home/user/data/metadata.csv"
REPORT = "/home/user/report.json"
STATE = {}


def snapshot_inputs():
    return {
        "metadata": open(METADATA, "rb").read(),
        "configs": {
            os.path.basename(path): open(path, "rb").read()
            for path in glob.glob(os.path.join(CONFIG_DIR, "*.jsonl"))
        },
    }


ORIGINAL = snapshot_inputs()


def restore_inputs():
    os.makedirs(CONFIG_DIR, exist_ok=True)
    for entry in os.listdir(CONFIG_DIR):
        path = os.path.join(CONFIG_DIR, entry)
        if os.path.isdir(path) and not os.path.islink(path):
            shutil.rmtree(path)
        else:
            os.unlink(path)
    for name, content in ORIGINAL["configs"].items():
        with open(os.path.join(CONFIG_DIR, name), "wb") as f:
            f.write(content)
    with open(METADATA, "wb") as f:
        f.write(ORIGINAL["metadata"])


def make_instrumentation(directory, marker):
    code = r'''
import os

_marker = os.environ.get("PIPELINE_PARALLEL_MARKER")
def _mark(label, count=1):
    if not _marker:
        return
    try:
        with open(_marker, "a") as f:
            f.write("%s:%s\n" % (label, count))
    except Exception:
        pass

def _count(value):
    try:
        return len(value)
    except Exception:
        return 1

try:
    import concurrent.futures as _cf
    _Thread = _cf.ThreadPoolExecutor
    _Process = _cf.ProcessPoolExecutor

    class TrackedThreadPoolExecutor(_Thread):
        def submit(self, *args, **kwargs):
            _mark("EXECUTOR_SUBMIT", 1)
            return super().submit(*args, **kwargs)
        def map(self, fn, *iterables, **kwargs):
            if iterables:
                _mark("EXECUTOR_MAP", _count(iterables[0]))
            return super().map(fn, *iterables, **kwargs)

    class TrackedProcessPoolExecutor(_Process):
        def submit(self, *args, **kwargs):
            _mark("EXECUTOR_SUBMIT", 1)
            return super().submit(*args, **kwargs)
        def map(self, fn, *iterables, **kwargs):
            if iterables:
                _mark("EXECUTOR_MAP", _count(iterables[0]))
            return super().map(fn, *iterables, **kwargs)

    _cf.ThreadPoolExecutor = TrackedThreadPoolExecutor
    _cf.ProcessPoolExecutor = TrackedProcessPoolExecutor
except Exception:
    pass

try:
    import multiprocessing.pool as _mp_pool
    for _name in ("map", "starmap", "map_async", "starmap_async"):
        _old = getattr(_mp_pool.Pool, _name)
        def _wrapper(self, func, iterable, *args, __old=_old, __name=_name, **kwargs):
            _mark("POOL_" + __name.upper(), _count(iterable))
            return __old(self, func, iterable, *args, **kwargs)
        setattr(_mp_pool.Pool, _name, _wrapper)

    for _name in ("apply", "apply_async"):
        _old = getattr(_mp_pool.Pool, _name)
        def _wrapper(self, *args, __old=_old, __name=_name, **kwargs):
            _mark("POOL_" + __name.upper(), 1)
            return __old(self, *args, **kwargs)
        setattr(_mp_pool.Pool, _name, _wrapper)
except Exception:
    pass

try:
    import multiprocessing.process as _mp_process
    _start = _mp_process.BaseProcess.start
    def _tracked_start(self, *args, **kwargs):
        _mark("PROCESS_START", 1)
        return _start(self, *args, **kwargs)
    _mp_process.BaseProcess.start = _tracked_start
except Exception:
    pass
'''
    with open(os.path.join(directory, "sitecustomize.py"), "w") as f:
        f.write(code)


def parallel_work_count(marker):
    counts = []
    try:
        with open(marker) as f:
            for line in f:
                match = re.fullmatch(r"[A-Z_]+:(\d+)\s*", line)
                if match:
                    counts.append(int(match.group(1)))
    except FileNotFoundError:
        return 0
    return max(max(counts, default=0), sum(1 for n in counts if n >= 1))


def run_script(script):
    if os.path.exists(REPORT):
        os.unlink(REPORT)
    with tempfile.TemporaryDirectory() as instrument_dir:
        marker = os.path.join(instrument_dir, "parallel.log")
        make_instrumentation(instrument_dir, marker)
        env = os.environ.copy()
        old_path = env.get("PYTHONPATH")
        env["PYTHONPATH"] = instrument_dir + (os.pathsep + old_path if old_path else "")
        env["PIPELINE_PARALLEL_MARKER"] = marker
        try:
            result = subprocess.run(
                [sys.executable, script], cwd=HOME, env=env,
                stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                text=True, timeout=30
            )
        except subprocess.TimeoutExpired:
            return False, None, 0, "timed out"
        work = parallel_work_count(marker)
    if result.returncode != 0:
        return False, None, work, result.stderr[-2000:]
    if not os.path.isfile(REPORT):
        return False, None, work, "report.json was not created by the script"
    try:
        with open(REPORT) as f:
            report = json.load(f)
    except Exception as exc:
        return False, None, work, str(exc)
    return True, report, work, ""


def valid_python_scripts():
    scripts = []
    for path in sorted(glob.glob(os.path.join(HOME, "**", "*.py"), recursive=True)):
        if "/data/" in path or not os.path.isfile(path) or os.path.islink(path):
            continue
        try:
            mode = os.lstat(path).st_mode
            if not stat.S_ISREG(mode):
                continue
            with open(path, "r", encoding="utf-8") as f:
                ast.parse(f.read(), filename=path)
        except (OSError, UnicodeError, SyntaxError):
            continue
        scripts.append(path)
    return scripts


def is_original_report(report):
    return (
        isinstance(report, dict)
        and report.get("most_drifted_server") == "srv1"
        and report.get("owner_email") == "alice@example.com"
        and isinstance(report.get("min_rolling_score"), (int, float))
        and abs(report["min_rolling_score"] - 0.6389) < 1e-4
    )


def test_python_pipeline_exists_and_runs_on_original_inputs():
    scripts = valid_python_scripts()
    assert scripts, "No regular, syntactically valid Python pipeline was created under /home/user."
    diagnostics = []
    for script in scripts:
        restore_inputs()
        ok, report, work, error = run_script(script)
        if ok and is_original_report(report) and work >= 2:
            STATE["script"] = script
            return
        diagnostics.append(f"{script}: ok={ok}, parallel_work={work}, error={error}")
    pytest.fail(
        "No Python script produced the required report by processing the original inputs "
        "with observable parallel work. " + " | ".join(diagnostics)
    )


def test_report_exists():
    path = "/home/user/report.json"
    assert os.path.isfile(path), f"The output file {path} was not created."


def test_report_content():
    path = "/home/user/report.json"
    assert os.path.isfile(path), f"The output file {path} was not created."

    with open(path, "r") as f:
        try:
            report = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {path} does not contain valid JSON.")

    expected_keys = {"most_drifted_server", "owner_email", "min_rolling_score"}
    missing_keys = expected_keys - set(report.keys())
    assert not missing_keys, f"The report JSON is missing required keys: {missing_keys}"

    assert report["most_drifted_server"] == "srv1", \
        f"Expected most_drifted_server to be 'srv1', got '{report['most_drifted_server']}'"

    assert report["owner_email"] == "alice@example.com", \
        f"Expected owner_email to be 'alice@example.com', got '{report['owner_email']}'"

    expected_score = 0.6389
    actual_score = report["min_rolling_score"]

    assert isinstance(actual_score, (int, float)), \
        f"Expected min_rolling_score to be a number, got {type(actual_score)}"

    assert abs(actual_score - expected_score) < 1e-4, \
        f"Expected min_rolling_score to be approximately {expected_score}, got {actual_score}"


def jaccard(left, right):
    left, right = set(left), set(right)
    union = left | right
    return len(left & right) / len(union) if union else 1.0


def expected_result(records, owners):
    by_server = {}
    for record in records:
        by_server.setdefault(record["server_id"], []).append(record)
    minima = {}
    for server, rows in by_server.items():
        rows.sort(key=lambda row: row["date"])
        scores = []
        previous = None
        rolling = []
        for row in rows:
            score = 1.0 if previous is None else jaccard(previous, row["packages"])
            scores.append(score)
            rolling.append(sum(scores[-3:]) / len(scores[-3:]))
            previous = row["packages"]
        minima[server] = min(rolling)
    winner = min(minima, key=minima.get)
    return {
        "most_drifted_server": winner,
        "owner_email": owners[winner],
        "min_rolling_score": round(minima[winner], 4),
    }


def test_pipeline_on_unseen_inputs_derived_at_verification_time():
    assert "script" in STATE
    token = secrets.token_hex(5)
    alpha, beta, gamma = [f"{name}_{token}" for name in ("alpha", "beta", "gamma")]
    owners = {
        alpha: f"alpha-{token}@example.test",
        beta: f"beta-{token}@example.test",
        gamma: f"gamma-{token}@example.test",
    }
    records = []
    alpha_packages = [["A", "B", "C"], ["A", "B", "C"], ["A"], ["A", "D"], ["D"]]
    beta_packages = [["X", "Y"]] * 5
    gamma_packages = [["M", "N"], ["M", "N", "O"], ["M", "N"], ["M", "N"], ["M", "N"]]
    for day in range(1, 6):
        date = f"2042-07-{day:02d}"
        records.extend([
            {"server_id": alpha, "date": date, "packages": alpha_packages[day - 1]},
            {"server_id": beta, "date": date, "packages": beta_packages[day - 1]},
            {"server_id": gamma, "date": date, "packages": gamma_packages[day - 1]},
        ])
    expected = expected_result(records, owners)

    try:
        os.makedirs(CONFIG_DIR, exist_ok=True)
        for entry in os.listdir(CONFIG_DIR):
            path = os.path.join(CONFIG_DIR, entry)
            if os.path.isdir(path) and not os.path.islink(path):
                shutil.rmtree(path)
            else:
                os.unlink(path)

        with open(METADATA, "w", newline="") as f:
            writer = csv.writer(f)
            writer.writerow(["server_id", "owner_email", "department"])
            for server in (gamma, alpha, beta):
                writer.writerow([server, owners[server], "Dynamic"])

        for day in range(1, 6):
            day_rows = [r for r in records if r["date"] == f"2042-07-{day:02d}"]
            lines = []
            for row in day_rows:
                encoded = json.dumps(row)
                if row["server_id"] == alpha and day == 1:
                    encoded = encoded.replace('"C"', '"C\\uZZZZ"')
                if row["server_id"] == alpha and day == 4:
                    encoded = encoded.replace('"D"', '"D\\uWWWW"')
                if row["server_id"] == beta and day == 5:
                    encoded = encoded.replace('"Y"', '"Y\\uQQQQ"')
                lines.append(encoded)
            with open(os.path.join(CONFIG_DIR, f"unseen_{day}_{token}.jsonl"), "w") as f:
                f.write("\n".join(lines) + "\n")

        ok, report, work, error = run_script(STATE["script"])
        assert ok, f"Pipeline failed on unseen malformed JSONL inputs: {error}"
        assert work >= 2, "The pipeline did not perform observable parallel work on the unseen files."
        assert set(expected) <= set(report), "The generated report is missing required keys."
        assert report["most_drifted_server"] == expected["most_drifted_server"]
        assert report["owner_email"] == expected["owner_email"]
        assert isinstance(report["min_rolling_score"], (int, float))
        assert abs(report["min_rolling_score"] - expected["min_rolling_score"]) < 1e-4
    finally:
        restore_inputs()
        run_script(STATE["script"])
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
