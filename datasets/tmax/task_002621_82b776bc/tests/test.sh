#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import tempfile
import numpy as np
import cv2

VIDEO_PATH = '/app/thermal_diffusion.mp4'
MODE_PATH = '/home/user/best_sim_mode.npy'
D_PATH = '/home/user/best_D.txt'
SRC_DIR = '/home/user/sim_src'
CPP_PATH = os.path.join(SRC_DIR, 'heat_solver.cpp')
BIN_PATH = os.path.join(SRC_DIR, 'heat_solver')


def experimental_mode():
    assert os.path.exists(VIDEO_PATH), f"Video file missing: {VIDEO_PATH}"
    cap = cv2.VideoCapture(VIDEO_PATH)
    frames = []
    while True:
        ret, frame = cap.read()
        if not ret:
            break
        gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
        frames.append(gray.flatten() / 255.0)
    cap.release()
    assert len(frames) > 0, "Video contains no frames."
    X = np.column_stack(frames)
    U, S, Vt = np.linalg.svd(X, full_matrices=False)
    mode = U[:, 0]
    return mode / np.linalg.norm(mode)


def primary_mode(rows):
    X = np.asarray(rows, dtype=np.float64).T
    gram = X.T @ X
    values, vectors = np.linalg.eigh(gram)
    mode = X @ vectors[:, -1]
    norm = np.linalg.norm(mode)
    assert np.isfinite(norm) and norm > 0, "Cannot derive a primary mode from simulation output."
    return mode / norm


def independent_simulation(D):
    N, T, dt = 64, 100, 0.5
    u = np.zeros((N, N), dtype=np.float64)
    u[20:40, 20:40] = 1.0
    rows = []
    for _ in range(T):
        u = u + D * dt * (
            np.roll(u, 1, axis=0) + np.roll(u, -1, axis=0) +
            np.roll(u, 1, axis=1) + np.roll(u, -1, axis=1) - 4.0 * u
        )
        rows.append(u.reshape(-1).copy())
    return np.asarray(rows)


def read_d():
    assert os.path.exists(D_PATH), f"Output file missing: {D_PATH}"
    assert os.path.isfile(D_PATH), f"Path {D_PATH} is not a file."
    with open(D_PATH, 'r') as f:
        content = f.read().strip()
    assert len(content) > 0, f"File {D_PATH} is empty."
    try:
        value = float(content)
    except ValueError:
        assert False, f"File {D_PATH} does not contain a valid float."
    assert np.isfinite(value), "best_D.txt must contain a finite float."
    assert 0.01 <= value <= 0.20, f"Diffusion coefficient {value} is outside [0.01, 0.20]."
    return value


def run_solver(binary, D):
    with tempfile.TemporaryDirectory() as work:
        result = subprocess.run(
            [binary, format(D, '.17g')], cwd=work,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
            timeout=30
        )
        assert result.returncode == 0, f"Solver failed: {result.stderr}"
        csv_path = os.path.join(work, 'sim_output.csv')
        assert os.path.isfile(csv_path), "Solver did not create sim_output.csv."
        try:
            rows = np.loadtxt(csv_path, delimiter=',')
        except Exception as exc:
            assert False, f"Could not parse sim_output.csv: {exc}"
    assert rows.shape == (100, 4096), f"Expected solver output shape (100, 4096), got {rows.shape}."
    assert np.all(np.isfinite(rows)), "Solver output contains non-finite values."
    return rows


def test_best_sim_mode_similarity():
    assert os.path.exists(MODE_PATH), f"Agent output missing: {MODE_PATH}"
    u_ref = experimental_mode()
    try:
        saved = np.load(MODE_PATH)
        assert saved.shape == (64, 64), f"Expected best_sim_mode.npy shape (64, 64), got {saved.shape}."
        assert np.all(np.isfinite(saved)), "best_sim_mode.npy contains non-finite values."
        saved_norm = np.linalg.norm(saved)
        assert np.isclose(saved_norm, 1.0, atol=1e-5), f"Saved mode L2 norm is {saved_norm}, not 1.0."
        u_agent = saved.flatten() / saved_norm
        similarity = np.abs(np.dot(u_ref, u_agent))
    except Exception as e:
        assert False, f"Failed to load or process {MODE_PATH}: {e}"
    assert similarity >= 0.95, f"Similarity {similarity:.4f} is below threshold 0.95"


def test_best_d_file_exists():
    read_d()


def test_cpp_mesh_size_updated():
    assert os.path.exists(CPP_PATH), f"C++ source file {CPP_PATH} is missing."
    with open(CPP_PATH, 'r') as f:
        content = f.read()
    assert "#define N 64" in content, "The mesh size was not updated to '#define N 64' in heat_solver.cpp."


def test_compiled_solver_mode_and_optimality():
    D = read_d()
    assert os.path.isfile(BIN_PATH), "Compiled heat_solver binary is missing."
    assert os.access(BIN_PATH, os.X_OK), "heat_solver is not executable."

    # Exercise the artifact left by the agent before rebuilding it.
    submitted_rows = run_solver(BIN_PATH, D)

    # Ensure the submitted Makefile really builds a runnable solver from the current state.
    os.remove(BIN_PATH)
    build = subprocess.run(
        ['make'], cwd=SRC_DIR, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, timeout=60
    )
    assert build.returncode == 0, f"make failed: {build.stdout}\n{build.stderr}"
    assert os.path.isfile(BIN_PATH) and os.access(BIN_PATH, os.X_OK), "make did not produce heat_solver."
    rebuilt_rows = run_solver(BIN_PATH, D)

    expected_rows = independent_simulation(D)
    assert np.allclose(submitted_rows, expected_rows, rtol=2e-5, atol=2e-6), \
        "The submitted solver output does not match the required 64x64 heat simulation."
    assert np.allclose(rebuilt_rows, expected_rows, rtol=2e-5, atol=2e-6), \
        "The solver rebuilt with make does not match the required 64x64 heat simulation."

    u_ref = experimental_mode()
    expected_mode = primary_mode(expected_rows)
    saved = np.load(MODE_PATH)
    assert saved.shape == (64, 64), f"Expected best_sim_mode.npy shape (64, 64), got {saved.shape}."
    saved_flat = saved.reshape(-1)
    assert np.all(np.isfinite(saved_flat)), "best_sim_mode.npy contains non-finite values."
    assert np.isclose(np.linalg.norm(saved_flat), 1.0, atol=1e-5), "Saved mode is not L2-normalized."
    correspondence = abs(float(np.dot(saved_flat / np.linalg.norm(saved_flat), expected_mode)))
    assert correspondence >= 0.9999, \
        f"Saved mode does not correspond to the simulation at best_D (similarity {correspondence:.6f})."

    claimed_score = abs(float(np.dot(u_ref, expected_mode)))
    grid_scores = []
    for i in range(1, 21):
        candidate_mode = primary_mode(independent_simulation(i / 100.0))
        grid_scores.append(abs(float(np.dot(u_ref, candidate_mode))))
    best_grid_score = max(grid_scores)
    assert claimed_score + 2e-6 >= best_grid_score, \
        f"D={D} is not optimal at 0.01 precision: score {claimed_score:.8f}, best grid score {best_grid_score:.8f}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
