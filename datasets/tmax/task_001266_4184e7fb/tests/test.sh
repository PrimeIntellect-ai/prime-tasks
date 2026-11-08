#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import os
import re
import stat
import struct
import subprocess
import textwrap

import numpy as np
import pytest

HOME = "/home/user"
OUTPUTS = [
    f"{HOME}/W_out.npy",
    f"{HOME}/H_out.npy",
    f"{HOME}/W_heatmap.png",
]


def run_checked(command, timeout=600):
    result = subprocess.run(
        command,
        cwd=HOME,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=timeout,
    )
    assert result.returncode == 0, (
        f"Command failed with status {result.returncode}: {command}\n"
        f"Last output:\n{result.stdout[-8000:]}"
    )
    return result


@pytest.fixture(scope="session", autouse=True)
def execute_pipeline_and_script():
    for path in OUTPUTS:
        if os.path.exists(path):
            os.remove(path)

    # Exercise the requested reproducible pipeline rather than trusting stale files.
    run_checked([f"{HOME}/run.sh"])
    assert os.path.isfile(f"{HOME}/.venv/bin/python"), "run.sh did not create /home/user/.venv"
    for path in OUTPUTS:
        assert os.path.isfile(path), f"run.sh did not produce {path}"
        assert os.path.getsize(path) > 0, f"run.sh produced an empty {path}"

    # Also prove that motif_nmf.py itself, not unrelated commands in run.sh,
    # creates all requested artifacts.
    for path in OUTPUTS:
        os.remove(path)
    run_checked([f"{HOME}/.venv/bin/python", f"{HOME}/motif_nmf.py"])
    for path in OUTPUTS:
        assert os.path.isfile(path), f"motif_nmf.py did not produce {path}"
        assert os.path.getsize(path) > 0, f"motif_nmf.py produced an empty {path}"


def test_run_sh_exists_and_executable():
    """Test that run.sh exists and is executable."""
    run_sh_path = f"{HOME}/run.sh"
    assert os.path.isfile(run_sh_path), f"{run_sh_path} does not exist."
    st = os.stat(run_sh_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"{run_sh_path} is not executable."

    text = open(run_sh_path, encoding="utf-8").read()
    assert re.search(r"python3?\s+-m\s+venv", text), "run.sh must create a Python virtual environment"
    assert ".venv" in text, "run.sh must create/use the .venv directory"
    assert "activate" in text, "run.sh must activate the virtual environment"
    assert "requirements.txt" in text, "run.sh must install from requirements.txt"
    assert re.search(r"(?:pip|python3?\s+-m\s+pip).*install", text), "run.sh must install dependencies"
    assert "motif_nmf.py" in text, "run.sh must run motif_nmf.py"


def test_requirements_exists():
    """Test that requirements.txt exists and declares the necessary packages."""
    req_path = f"{HOME}/requirements.txt"
    assert os.path.isfile(req_path), f"{req_path} does not exist."
    lines = [line.strip().lower() for line in open(req_path, encoding="utf-8")]
    lines = [line for line in lines if line and not line.startswith("#")]
    assert any(re.match(r"numpy(?:\s|[<>=!~\[]|$)", line) for line in lines), "requirements.txt must include numpy"
    assert any(re.match(r"matplotlib(?:\s|[<>=!~\[]|$)", line) for line in lines), "requirements.txt must include matplotlib"


def test_motif_source_is_vectorized_and_has_required_constants():
    path = f"{HOME}/motif_nmf.py"
    assert os.path.isfile(path), f"{path} does not exist"
    source = open(path, encoding="utf-8").read()
    tree = ast.parse(source, filename=path)

    funcs = [n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name == "run_nmf"]
    assert len(funcs) == 1, "motif_nmf.py must define run_nmf"
    func = funcs[0]

    # The iteration loop is required, but matrix-element update loops are not.
    loops = [n for n in ast.walk(func) if isinstance(n, (ast.For, ast.AsyncFor, ast.While))]
    assert len(loops) == 1 and isinstance(loops[0], ast.For), (
        "run_nmf must have only the outer iteration loop; NMF matrix updates must be vectorized"
    )
    outer = loops[0]
    assert isinstance(outer.iter, ast.Call) and isinstance(outer.iter.func, ast.Name) and outer.iter.func.id == "range"
    assert len(outer.iter.args) == 1 and isinstance(outer.iter.args[0], ast.Name) and outer.iter.args[0].id == "iters", (
        "the outer NMF loop must retain the requested iteration parameter"
    )
    assert not any(isinstance(n, ast.comprehension) for n in ast.walk(func)), (
        "run_nmf must not hide element-wise updates in comprehensions"
    )

    seed_42 = False
    for node in ast.walk(func):
        if isinstance(node, ast.Call) and len(node.args) == 1:
            call_name = ""
            if isinstance(node.func, ast.Attribute):
                call_name = node.func.attr
            if call_name == "seed" and isinstance(node.args[0], ast.Constant) and node.args[0].value == 42:
                seed_42 = True
    assert seed_42, "run_nmf must retain np.random.seed(42)"
    assert any(
        isinstance(node, ast.Constant)
        and isinstance(node.value, float)
        and node.value == 1e-9
        for node in ast.walk(func)
    ), "run_nmf must use epsilon = 1e-9"

    constants = {n.value for n in ast.walk(tree) if isinstance(n, ast.Constant) and isinstance(n.value, str)}
    for filename in ("W_out.npy", "H_out.npy", "W_heatmap.png"):
        assert any(filename in value for value in constants), f"motif_nmf.py must write {filename}"


def test_run_nmf_on_independent_input(tmp_path):
    """Import and exercise the submitted function on verifier-generated data."""
    rng = np.random.default_rng(918273)
    V = rng.random((7, 9)) * 1e-10
    V[1] = V[0] + 1e-15
    V[3] = 0.0
    input_path = tmp_path / "V.npy"
    actual_w_path = tmp_path / "W.npy"
    actual_h_path = tmp_path / "H.npy"
    np.save(input_path, V)

    helper = tmp_path / "exercise.py"
    helper.write_text(textwrap.dedent(f"""
        import importlib.util
        import numpy as np
        spec = importlib.util.spec_from_file_location('submitted_motif_nmf', {f'{HOME}/motif_nmf.py'!r})
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        V = np.load({str(input_path)!r})
        W, H = module.run_nmf(V, 3, 4)
        np.save({str(actual_w_path)!r}, W)
        np.save({str(actual_h_path)!r}, H)
    """), encoding="utf-8")
    run_checked([f"{HOME}/.venv/bin/python", str(helper)])

    np.random.seed(42)
    W_expected = np.random.rand(7, 3)
    H_expected = np.random.rand(3, 9)
    for _ in range(4):
        num_H = W_expected.T @ V
        den_H = W_expected.T @ (W_expected @ H_expected)
        H_expected = H_expected * (num_H / (den_H + 1e-9))
        num_W = V @ H_expected.T
        den_W = (W_expected @ H_expected) @ H_expected.T
        W_expected = W_expected * (num_W / (den_W + 1e-9))

    W_actual = np.load(actual_w_path)
    H_actual = np.load(actual_h_path)
    assert np.isfinite(W_actual).all() and np.isfinite(H_actual).all()
    np.testing.assert_allclose(W_actual, W_expected, rtol=1e-11, atol=1e-14)
    np.testing.assert_allclose(H_actual, H_expected, rtol=1e-11, atol=1e-14)


def test_outputs_exist():
    """Test that the expected output files exist."""
    for path in OUTPUTS:
        assert os.path.isfile(path), f"Expected output file {path} does not exist."


def test_heatmap_is_real_png():
    path = f"{HOME}/W_heatmap.png"
    assert os.path.getsize(path) > 100, "W_heatmap.png is empty or implausibly small"
    with open(path, "rb") as fh:
        header = fh.read(24)
    assert header[:8] == b"\x89PNG\r\n\x1a\n", "W_heatmap.png is not a PNG file"
    assert header[12:16] == b"IHDR", "W_heatmap.png lacks a valid PNG IHDR chunk"
    width, height = struct.unpack(">II", header[16:24])
    assert width > 1 and height > 1, "W_heatmap.png has invalid dimensions"


def test_nmf_output_validity():
    """Test that the output matrices are valid (no NaNs, correct shapes)."""
    W = np.load(f"{HOME}/W_out.npy")
    H = np.load(f"{HOME}/H_out.npy")

    assert not np.isnan(W).any(), "W_out.npy contains NaNs. Stability fix failed."
    assert not np.isnan(H).any(), "H_out.npy contains NaNs. Stability fix failed."
    assert np.isfinite(W).all(), "W_out.npy contains non-finite values."
    assert np.isfinite(H).all(), "H_out.npy contains non-finite values."
    assert W.shape == (200, 10), f"Expected W shape (200, 10), got {W.shape}"
    assert H.shape == (10, 200), f"Expected H shape (10, 200), got {H.shape}"


def test_nmf_correctness():
    """Test that the NMF output matches the expected vectorized implementation with epsilon."""
    V = np.load(f"{HOME}/kmer_matrix.npy")

    n, m = V.shape
    k = 10
    iters = 50
    eps = 1e-9

    np.random.seed(42)
    W_expected = np.random.rand(n, k)
    H_expected = np.random.rand(k, m)

    for _ in range(iters):
        num_H = W_expected.T @ V
        den_H = W_expected.T @ (W_expected @ H_expected)
        H_expected = H_expected * (num_H / (den_H + eps))

        num_W = V @ H_expected.T
        den_W = (W_expected @ H_expected) @ H_expected.T
        W_expected = W_expected * (num_W / (den_W + eps))

    W_actual = np.load(f"{HOME}/W_out.npy")
    H_actual = np.load(f"{HOME}/H_out.npy")

    np.testing.assert_allclose(
        W_actual, W_expected, rtol=1e-5, atol=1e-8,
        err_msg="W_out.npy does not match expected values. Ensure epsilon=1e-9 is added to the denominator and operations are correctly vectorized."
    )
    np.testing.assert_allclose(
        H_actual, H_expected, rtol=1e-5, atol=1e-8,
        err_msg="H_out.npy does not match expected values. Ensure epsilon=1e-9 is added to the denominator and operations are correctly vectorized."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
