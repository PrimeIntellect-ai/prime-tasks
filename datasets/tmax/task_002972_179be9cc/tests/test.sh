#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import subprocess

import numpy as np
import pandas as pd
import pytest
from pandas.testing import assert_frame_equal

HOME = "/home/user"
EXPECTED_JOIN = None
EXPECTED_SCORES = None


def build_expected_inputs():
    np.random.seed(42)
    ids = np.arange(1, 101)
    np.random.shuffle(ids)

    a = pd.DataFrame({
        "id": ids,
        "f1": np.random.randn(100) * 5,
        "f2": np.random.randn(100) * 2,
        "f3": np.random.randn(100) * 10,
    })
    b = pd.DataFrame({
        "id": ids[:90],
        "f4": np.random.randn(90) * 3,
        "f5": np.random.randn(90) * 7,
    })
    c = pd.DataFrame({
        "id": ids[10:],
        "f6": np.random.randn(90) * 4,
        "f7": np.random.randn(90) * 6,
        "f8": np.random.randn(90) * 1,
    })
    return a, b, c


def assert_numeric_frame(actual, expected, atol=1e-10):
    assert list(actual.columns) == list(expected.columns)
    assert actual.shape == expected.shape
    assert_frame_equal(
        actual.reset_index(drop=True),
        expected.reset_index(drop=True),
        check_dtype=False,
        check_exact=False,
        rtol=1e-10,
        atol=atol,
    )


def run_as_user(command, timeout=300):
    return subprocess.run(
        ["runuser", "-u", "user", "--", "bash", "-c", command],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=timeout,
    )


@pytest.fixture(scope="session", autouse=True)
def execute_pipeline_and_compute_reference():
    global EXPECTED_JOIN, EXPECTED_SCORES

    required = [
        "join_data.py", "pca_py.py", "pca_r.R",
        "test_accuracy.py", "run_pipeline.sh",
    ]
    for name in required:
        path = os.path.join(HOME, name)
        assert os.path.isfile(path), f"Missing required script {path}"
        assert os.path.getsize(path) > 0, f"Required script is empty: {path}"

    expected_a, expected_b, expected_c = build_expected_inputs()
    for name, expected in [
        ("data_A.csv", expected_a),
        ("data_B.csv", expected_b),
        ("data_C.csv", expected_c),
    ]:
        actual = pd.read_csv(os.path.join(HOME, name))
        assert_numeric_frame(actual, expected)

    EXPECTED_JOIN = (
        expected_a.merge(expected_b, on="id", how="inner")
        .merge(expected_c, on="id", how="inner")
        .sort_values("id")
        .reset_index(drop=True)
    )
    x = EXPECTED_JOIN.drop(columns=["id"]).to_numpy(dtype=float)
    x = x - x.mean(axis=0)
    u, singular_values, _ = np.linalg.svd(x, full_matrices=False)
    EXPECTED_SCORES = u[:, :2] * singular_values[:2]

    for name in [
        "joined_data.csv", "pca_python.csv", "pca_r.csv",
        "accuracy_report.txt",
    ]:
        path = os.path.join(HOME, name)
        if os.path.exists(path):
            os.remove(path)

    result = run_as_user("cd /home/user && bash ./run_pipeline.sh")
    assert result.returncode == 0, "run_pipeline.sh failed:\n" + result.stdout


def test_joined_data_exists_and_format():
    """Test that joined_data.csv exists, has the correct header, and correct row count."""
    file_path = "/home/user/joined_data.csv"
    assert os.path.isfile(file_path), f"Missing {file_path}"

    with open(file_path, 'r', newline='') as f:
        reader = csv.reader(f)
        header = next(reader, None)
        assert header is not None, f"{file_path} is empty"
        assert "id" in header, f"'id' column missing in {file_path}"
        rows = list(reader)
        assert len(rows) == 80, f"Expected 80 data rows in {file_path}, found {len(rows)}"


def test_joined_data_values_and_sorting():
    actual = pd.read_csv("/home/user/joined_data.csv")
    assert list(actual.columns) == ["id", "f1", "f2", "f3", "f4", "f5", "f6", "f7", "f8"]
    assert actual["id"].is_monotonic_increasing, "joined_data.csv is not sorted by id ascending"
    assert actual["id"].is_unique, "joined_data.csv contains duplicate ids"
    assert_numeric_frame(actual, EXPECTED_JOIN)


def test_pca_python_exists_and_format():
    """Test that pca_python.csv exists and has correct dimensions."""
    file_path = "/home/user/pca_python.csv"
    assert os.path.isfile(file_path), f"Missing {file_path}"

    with open(file_path, 'r', newline='') as f:
        reader = csv.reader(f)
        header = next(reader, None)
        assert header is not None, f"{file_path} is empty"
        assert header == ["PC1", "PC2"], f"Header in {file_path} should be exactly ['PC1', 'PC2']"
        rows = list(reader)
        assert len(rows) == 80, f"Expected 80 data rows in {file_path}, found {len(rows)}"


def test_pca_r_exists_and_format():
    """Test that pca_r.csv exists and has correct dimensions."""
    file_path = "/home/user/pca_r.csv"
    assert os.path.isfile(file_path), f"Missing {file_path}"

    with open(file_path, 'r', newline='') as f:
        reader = csv.reader(f)
        header = next(reader, None)
        assert header is not None, f"{file_path} is empty"
        assert header == ["PC1", "PC2"], f"Header in {file_path} should be exactly ['PC1', 'PC2']"
        rows = list(reader)
        assert len(rows) == 80, f"Expected 80 data rows in {file_path}, found {len(rows)}"


def assert_pca_matches_reference(path):
    frame = pd.read_csv(path)
    assert list(frame.columns) == ["PC1", "PC2"]
    scores = frame.to_numpy(dtype=float)
    assert scores.shape == EXPECTED_SCORES.shape
    assert np.isfinite(scores).all(), f"Non-finite PCA scores in {path}"

    for component in range(2):
        actual = scores[:, component]
        expected = EXPECTED_SCORES[:, component]
        error = min(
            np.max(np.abs(actual - expected)),
            np.max(np.abs(actual + expected)),
        )
        assert error < 1e-6, f"Incorrect PCA component {component + 1} in {path}; max error {error}"


def test_python_pca_values():
    assert_pca_matches_reference("/home/user/pca_python.csv")


def test_r_pca_values():
    assert_pca_matches_reference("/home/user/pca_r.csv")


def test_python_and_r_pca_agree_as_specified():
    py_scores = pd.read_csv("/home/user/pca_python.csv").to_numpy(dtype=float)
    r_scores = pd.read_csv("/home/user/pca_r.csv").to_numpy(dtype=float)
    difference = np.max(np.abs(np.abs(py_scores) - np.abs(r_scores)))
    assert difference < 1e-4, f"Python and R PCA outputs differ by {difference}"


def test_accuracy_report():
    """Test that accuracy_report.txt exists and contains PASS."""
    file_path = "/home/user/accuracy_report.txt"
    assert os.path.isfile(file_path), f"Missing {file_path}"
    with open(file_path, 'r') as f:
        content = f.read().strip()
    assert content == "PASS", f"Expected 'PASS' in {file_path}, found '{content}'"


def test_accuracy_script_computes_result():
    py_path = "/home/user/pca_python.csv"
    r_path = "/home/user/pca_r.csv"
    report_path = "/home/user/accuracy_report.txt"
    with open(py_path, "rb") as f:
        original_py = f.read()
    with open(r_path, "rb") as f:
        original_r = f.read()

    try:
        pd.DataFrame({"PC1": [1.0, -3.0], "PC2": [2.0, 4.0]}).to_csv(py_path, index=False)
        pd.DataFrame({"PC1": [-1.0, 3.0], "PC2": [-2.00005, -4.0]}).to_csv(r_path, index=False)
        result = run_as_user("cd /home/user && python3 ./test_accuracy.py", timeout=60)
        assert result.returncode == 0, result.stdout
        with open(report_path) as f:
            assert f.read().strip() == "PASS", "Accuracy script rejected sign-equivalent values within tolerance"

        pd.DataFrame({"PC1": [-1.0, 3.0], "PC2": [-2.0002, -4.0]}).to_csv(r_path, index=False)
        result = run_as_user("cd /home/user && python3 ./test_accuracy.py", timeout=60)
        assert result.returncode == 0, result.stdout
        with open(report_path) as f:
            assert f.read().strip() == "FAIL", "Accuracy script did not detect an error exceeding 1e-4"
    finally:
        with open(py_path, "wb") as f:
            f.write(original_py)
        with open(r_path, "wb") as f:
            f.write(original_r)

    result = run_as_user("cd /home/user && python3 ./test_accuracy.py", timeout=60)
    assert result.returncode == 0, result.stdout
    with open(report_path) as f:
        assert f.read().strip() == "PASS"


def test_pipeline_script_exists():
    """Test that run_pipeline.sh exists."""
    file_path = "/home/user/run_pipeline.sh"
    assert os.path.isfile(file_path), f"Missing pipeline script {file_path}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
