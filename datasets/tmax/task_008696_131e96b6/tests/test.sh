#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import csv
import math
import random
import secrets
import shutil
import subprocess
import tempfile
import pytest

DIAGNOSTICS_DIR = "/home/user/diagnostics"
VENV_PYTHON = os.path.join(DIAGNOSTICS_DIR, "venv", "bin", "python")


def run_checked(command, cwd, timeout=300):
    return subprocess.run(
        command,
        cwd=cwd,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=timeout,
        check=True,
    )


def test_pipeline_reexecutes_successfully():
    pipeline = os.path.join(DIAGNOSTICS_DIR, "run_pipeline.sh")
    assert os.path.isfile(pipeline), "run_pipeline.sh is missing"
    assert os.access(pipeline, os.X_OK), "run_pipeline.sh is not executable"
    try:
        run_checked([pipeline], DIAGNOSTICS_DIR, timeout=600)
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as exc:
        pytest.fail(f"run_pipeline.sh did not complete successfully: {exc}")


def test_extracted_metrics_csv_fixed():
    filepath = os.path.join(DIAGNOSTICS_DIR, "extracted_metrics.csv")
    assert os.path.isfile(filepath), f"File {filepath} is missing. Did the pipeline run successfully?"

    with open(filepath, "r") as f:
        reader = csv.DictReader(f)
        rows = list(reader)

    assert len(rows) == 4, f"Expected 4 rows in extracted_metrics.csv, got {len(rows)}"

    node_c = next((r for r in rows if r["Node"] == "NODE_C"), None)
    assert node_c is not None, "NODE_C is missing from extracted_metrics.csv"
    assert node_c["Latency"] == "0", f"NODE_C latency should be 0, got {node_c['Latency']}"


def test_health_scores_csv_fixed():
    filepath = os.path.join(DIAGNOSTICS_DIR, "health_scores.csv")
    assert os.path.isfile(filepath), f"File {filepath} is missing. Did the pipeline run successfully?"

    with open(filepath, "r") as f:
        reader = csv.DictReader(f)
        scores = {row["Node"]: float(row["Score"]) for row in reader}

    expected_scores = {
        "NODE_A": ((100 - 50) * 0.4) + ((100 - 60) * 0.4) + ((1000 / (5 + 1.0)) * 0.2),
        "NODE_B": ((100 - 80) * 0.4) + ((100 - 90) * 0.4) + ((1000 / (20 + 1.0)) * 0.2),
        "NODE_C": ((100 - 20) * 0.4) + ((100 - 20) * 0.4) + ((1000 / (0 + 1.0)) * 0.2),
        "NODE_D": ((100 - 10) * 0.4) + ((100 - 15) * 0.4) + ((1000 / (2 + 1.0)) * 0.2),
    }

    for node, expected in expected_scores.items():
        assert node in scores, f"{node} missing from health_scores.csv"
        actual = scores[node]
        assert math.isclose(actual, expected, rel_tol=1e-3), \
            f"{node} score incorrect. Expected ~{expected:.4f}, got {actual}"


def test_final_report_json_fixed():
    filepath = os.path.join(DIAGNOSTICS_DIR, "final_report.json")
    assert os.path.isfile(filepath), f"File {filepath} is missing. Did the pipeline run successfully?"

    with open(filepath, "r") as f:
        try:
            report = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{filepath} is not valid JSON")

    expected_nodes = ["NODE_A", "NODE_B", "NODE_C", "NODE_D"]
    for node in expected_nodes:
        assert node in report, f"{node} is missing from final_report.json"

        val = report[node]
        assert isinstance(val, (int, float)), f"Value for {node} is not a number"
        assert not math.isnan(val), f"Value for {node} is NaN, normalization failed"
        assert not math.isinf(val), f"Value for {node} is Infinity, normalization failed"

        assert math.isclose(val, 126.39, abs_tol=1.0), \
            f"{node} value incorrect. Expected ~126.39, got {val}. Is the adjacency matrix row-normalized correctly?"


def test_venv_dependencies_installed():
    venv_dir = os.path.join(DIAGNOSTICS_DIR, "venv")
    assert os.path.isdir(venv_dir), "Virtual environment directory 'venv' is missing."

    site_packages = None
    for root, dirs, files in os.walk(os.path.join(venv_dir, "lib")):
        if "site-packages" in dirs:
            site_packages = os.path.join(root, "site-packages")
            break

    if site_packages:
        installed_packages = os.listdir(site_packages)
        has_numpy = any(p.startswith("numpy") for p in installed_packages)
        has_networkx = any(p.startswith("networkx") for p in installed_packages)
        assert has_numpy, "numpy is not installed in the virtual environment."
        assert has_networkx, "networkx is not installed in the virtual environment."

    assert os.path.isfile(VENV_PYTHON), "The virtual environment Python executable is missing"
    probe = (
        "import importlib.metadata as m; import numpy as np; import networkx as nx; "
        "assert np.asarray([[1,2],[3,4]]).dot(np.asarray([1,1])).tolist()==[3,7]; "
        "assert m.version('numpy'); assert m.version('networkx'); print(nx.__version__)"
    )
    try:
        run_checked([VENV_PYTHON, "-c", probe], DIAGNOSTICS_DIR)
        run_checked([VENV_PYTHON, "-m", "pip", "check"], DIAGNOSTICS_DIR)
    except subprocess.CalledProcessError as exc:
        pytest.fail(f"Virtual-environment dependencies are not genuinely usable: {exc.stdout}")


def test_extract_script_on_unseen_input():
    source = os.path.join(DIAGNOSTICS_DIR, "extract.pl")
    assert os.path.isfile(source), "extract.pl is missing"
    token = secrets.token_hex(5).upper()
    nodes = [f"DYN_{token}_{i}" for i in range(5)]
    rng = random.SystemRandom()
    expected = []

    with tempfile.TemporaryDirectory() as tmp:
        shutil.copy2(source, os.path.join(tmp, "extract.pl"))
        with open(os.path.join(tmp, "raw_logs.txt"), "w") as f:
            for i, node in enumerate(nodes):
                cpu = rng.randrange(1, 100)
                mem = rng.randrange(1, 100)
                latency = "" if i in (1, 4) else str(rng.randrange(1, 500))
                f.write(f"2026-09-12 12:{i:02d}:00,{node},cpu={cpu},mem={mem},latency={latency}\n")
                expected.append({"Node": node, "CPU": str(cpu), "Memory": str(mem), "Latency": latency or "0"})
        try:
            run_checked(["perl", "extract.pl"], tmp)
        except subprocess.CalledProcessError as exc:
            pytest.fail(f"extract.pl failed on unseen input: {exc.stdout}")
        with open(os.path.join(tmp, "extracted_metrics.csv"), newline="") as f:
            reader = csv.DictReader(f)
            assert reader.fieldnames == ["Node", "CPU", "Memory", "Latency"]
            actual = list(reader)
        assert actual == expected, f"extract.pl produced incorrect dynamic output: {actual}"


def test_health_script_on_unseen_input():
    source = os.path.join(DIAGNOSTICS_DIR, "calculate_health.rb")
    assert os.path.isfile(source), "calculate_health.rb is missing"
    rng = random.SystemRandom()
    token = secrets.token_hex(5).upper()
    rows = []
    for i in range(6):
        rows.append((f"HEALTH_{token}_{i}", rng.randrange(0, 100), rng.randrange(0, 100), rng.randrange(0, 700)))

    with tempfile.TemporaryDirectory() as tmp:
        shutil.copy2(source, os.path.join(tmp, "calculate_health.rb"))
        with open(os.path.join(tmp, "extracted_metrics.csv"), "w", newline="") as f:
            writer = csv.writer(f)
            writer.writerow(["Node", "CPU", "Memory", "Latency"])
            writer.writerows(rows)
        try:
            run_checked(["ruby", "calculate_health.rb"], tmp)
        except subprocess.CalledProcessError as exc:
            pytest.fail(f"calculate_health.rb failed on unseen input: {exc.stdout}")
        with open(os.path.join(tmp, "health_scores.csv"), newline="") as f:
            actual_rows = list(csv.DictReader(f))

        assert [r["Node"] for r in actual_rows] == [r[0] for r in rows]
        for output, (node, cpu, mem, latency) in zip(actual_rows, rows):
            expected = ((100 - cpu) * 0.4) + ((100 - mem) * 0.4) + ((1000 / (latency + 1.0)) * 0.2)
            assert math.isclose(float(output["Score"]), round(expected, 4), abs_tol=0.000051), \
                f"Incorrect dynamic score for {node}"


def test_smoothing_script_on_unseen_input():
    source = os.path.join(DIAGNOSTICS_DIR, "topology_smoothing.py")
    assert os.path.isfile(source), "topology_smoothing.py is missing"
    assert os.path.isfile(VENV_PYTHON), "venv Python is missing"
    rng = random.SystemRandom()
    token = secrets.token_hex(5).upper()
    nodes = [f"TOPO_{token}_{i}" for i in range(7)]
    values = [round(rng.uniform(15.0, 350.0), 6) for _ in nodes]

    with tempfile.TemporaryDirectory() as tmp:
        shutil.copy2(source, os.path.join(tmp, "topology_smoothing.py"))
        with open(os.path.join(tmp, "health_scores.csv"), "w", newline="") as f:
            writer = csv.writer(f)
            writer.writerow(["Node", "Score"])
            writer.writerows(zip(nodes, values))
        try:
            run_checked([VENV_PYTHON, "topology_smoothing.py"], tmp)
        except subprocess.CalledProcessError as exc:
            pytest.fail(f"topology_smoothing.py failed on unseen input: {exc.stdout}")
        with open(os.path.join(tmp, "final_report.json")) as f:
            actual = json.load(f)

        expected_code = (
            "import json,numpy as np,sys; "
            "s=np.array(json.loads(sys.argv[1]),dtype=float); n=len(s); "
            "np.random.seed(42); A=np.random.rand(n,n); A=A/A.sum(axis=1,keepdims=True); "
            "exec('for _ in range(50):\\n s=A.dot(s)'); "
            "print(json.dumps([round(float(x),2) for x in s]))"
        )
        expected_result = run_checked(
            [VENV_PYTHON, "-c", expected_code, json.dumps(values)], tmp
        )
        expected_values = json.loads(expected_result.stdout.strip())
        assert set(actual) == set(nodes), "Dynamic final report has incorrect nodes"
        for node, expected in zip(nodes, expected_values):
            value = actual[node]
            assert isinstance(value, (int, float)) and math.isfinite(value)
            assert math.isclose(value, expected, abs_tol=1e-9), \
                f"Incorrect normalized smoothing result for {node}: expected {expected}, got {value}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
