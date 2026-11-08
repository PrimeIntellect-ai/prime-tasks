#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import math
import shutil
import secrets
import subprocess
import importlib.util
import pytest
import numpy as np


def get_ca_coordinates(pdb_path):
    coords = []
    with open(pdb_path, 'r') as f:
        for line in f:
            if line.startswith("ATOM") and line[12:16].strip() == "CA":
                x = float(line[30:38].strip())
                y = float(line[38:46].strip())
                z = float(line[46:54].strip())
                coords.append((x, y, z))
    return coords


def compute_distance_matrix(coords):
    n = len(coords)
    D = [[0.0] * n for _ in range(n)]
    for i in range(n):
        for j in range(n):
            dx = coords[i][0] - coords[j][0]
            dy = coords[i][1] - coords[j][1]
            dz = coords[i][2] - coords[j][2]
            D[i][j] = math.sqrt(dx*dx + dy*dy + dz*dz)
    return D


def power_iteration_max_sv(A, iters=100):
    n = len(A)
    b_k = [1.0] * n
    for _ in range(iters):
        b_k1 = [sum(A[i][j] * b_k[j] for j in range(n)) for i in range(n)]
        norm = math.sqrt(sum(x*x for x in b_k1))
        b_k = [x / norm for x in b_k1]
    Ax = [sum(A[i][j] * b_k[j] for j in range(n)) for i in range(n)]
    eigenvalue = sum(b_k[i] * Ax[i] for i in range(n))
    return abs(eigenvalue)


def test_extract_svd_output():
    svd_file = "/home/user/results/svd_max.txt"
    assert os.path.isfile(svd_file), f"{svd_file} is missing. Did extract_svd.py run?"

    coords = get_ca_coordinates("/home/user/data/input.pdb")
    D = compute_distance_matrix(coords)
    expected_sigma_max = power_iteration_max_sv(D)

    with open(svd_file, 'r') as f:
        content = f.read().strip()
    try:
        actual_sigma_max = float(content)
    except ValueError:
        pytest.fail(f"Could not parse float from {svd_file}. Content: {content}")

    assert math.isclose(actual_sigma_max, expected_sigma_max, rel_tol=1e-3), \
        f"Expected max singular value ~{expected_sigma_max:.4f}, got {actual_sigma_max}"


def test_integrator_implementation():
    integrator_path = "/home/user/sim/integrator.py"
    assert os.path.isfile(integrator_path), f"{integrator_path} is missing."

    with open(integrator_path, 'r') as f:
        code = f.read()

    assert "solve_ivp" in code, "integrator.py must use scipy.integrate.solve_ivp"
    assert "'RK45'" in code or '"RK45"' in code, "integrator.py must specify the 'RK45' method"

    import scipy.integrate
    original_solve_ivp = scipy.integrate.solve_ivp
    calls = []

    def recording_solve_ivp(*args, **kwargs):
        calls.append((args, kwargs.copy()))
        return original_solve_ivp(*args, **kwargs)

    scipy.integrate.solve_ivp = recording_solve_ivp
    try:
        spec = importlib.util.spec_from_file_location("submitted_integrator", integrator_path)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)

        rng = secrets.SystemRandom()
        cases = [(rng.uniform(0.08, 1.8), rng.uniform(0.3, 2.5)) for _ in range(4)]
        for k, t_end in cases:
            before = len(calls)
            actual = module.simulate(k, t_end)
            assert type(actual) is float, "simulate must return a Python float"
            expected = 100.0 * math.exp(-k * t_end)
            assert math.isclose(actual, expected, rel_tol=5e-3, abs_tol=1e-8), \
                f"simulate({k}, {t_end}) returned {actual}, expected {expected}"
            assert len(calls) > before, "simulate did not call scipy.integrate.solve_ivp"

            args, kwargs = calls[-1]
            method = kwargs.get("method", args[3] if len(args) > 3 else None)
            assert method == "RK45", "simulate must call solve_ivp with method='RK45'"
            t_span = kwargs.get("t_span", args[1] if len(args) > 1 else None)
            y0 = kwargs.get("y0", args[2] if len(args) > 2 else None)
            assert t_span is not None and math.isclose(float(t_span[0]), 0.0) and math.isclose(float(t_span[1]), t_end)
            assert y0 is not None and math.isclose(float(y0[0]), 100.0)
    finally:
        scipy.integrate.solve_ivp = original_solve_ivp


def test_ensemble_output():
    ensemble_file = "/home/user/results/ensemble_final.json"
    assert os.path.isfile(ensemble_file), f"{ensemble_file} is missing. Did run_ensemble.py run?"

    coords = get_ca_coordinates("/home/user/data/input.pdb")
    D = compute_distance_matrix(coords)
    sigma_max = power_iteration_max_sv(D)

    with open(ensemble_file, 'r') as f:
        try:
            results = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{ensemble_file} is not valid JSON.")

    expected_c_values = ["0.5", "1.0", "1.5", "2.0"]
    for c_str in expected_c_values:
        assert c_str in results, f"Missing scaling factor {c_str} in ensemble results."
        c = float(c_str)
        k = c * sigma_max
        expected_y = 100.0 * math.exp(-k * 5.0)
        actual_y = results[c_str]
        assert math.isclose(actual_y, expected_y, rel_tol=1e-2), \
            f"For c={c_str}, expected y ~ {expected_y:.4f}, but got {actual_y}"


def test_pipeline_script():
    pipeline_path = "/home/user/run_pipeline.sh"
    assert os.path.isfile(pipeline_path), f"{pipeline_path} is missing."
    assert os.access(pipeline_path, os.X_OK), f"{pipeline_path} is not executable."

    with open(pipeline_path, 'r') as f:
        script_content = f.read()

    assert "extract_svd.py" in script_content, "Pipeline script must run extract_svd.py"
    assert "run_ensemble.py" in script_content, "Pipeline script must run run_ensemble.py"
    assert "mkdir" in script_content and "results" in script_content, "Pipeline script must create the results directory"


def make_pdb(coords):
    lines = []
    for serial, (x, y, z) in enumerate(coords, 1):
        line = list(" " * 80)
        line[0:6] = "ATOM  "
        line[6:11] = f"{serial:5d}"
        line[12:16] = " CA "
        line[17:20] = "ALA"
        line[21] = "A"
        line[22:26] = f"{serial:4d}"
        line[30:38] = f"{x:8.3f}"
        line[38:46] = f"{y:8.3f}"
        line[46:54] = f"{z:8.3f}"
        line[54:60] = "  1.00"
        line[60:66] = "  0.00"
        line[76:78] = " C"
        lines.append("".join(line) + "\n")
    return "".join(lines)


def test_dynamic_pipeline_execution_and_parallel_ensemble():
    extract_path = "/home/user/extract_svd.py"
    ensemble_path = "/home/user/sim/run_ensemble.py"
    pipeline_path = "/home/user/run_pipeline.sh"
    integrator_path = "/home/user/sim/integrator.py"
    pdb_path = "/home/user/data/input.pdb"

    for path in (extract_path, ensemble_path, pipeline_path):
        assert os.path.isfile(path), f"{path} is missing"
        assert os.access(path, os.X_OK), f"{path} is not executable"

    rng = secrets.SystemRandom()
    coords = []
    for _ in range(rng.randrange(5, 9)):
        coords.append(tuple(round(rng.uniform(-0.08, 0.08), 3) for _ in range(3)))

    original_pdb = open(pdb_path, "rb").read()
    original_integrator = open(integrator_path, "rb").read()
    backup_integrator = "/tmp/submitted_integrator_impl.py"
    with open(backup_integrator, "wb") as f:
        f.write(original_integrator)

    pool_log = "/tmp/verifier_pool_calls.log"
    sim_log = "/tmp/verifier_sim_calls.log"
    for path in (pool_log, sim_log):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    hook_dir = "/tmp/verifier_hook"
    os.makedirs(hook_dir, exist_ok=True)
    with open(os.path.join(hook_dir, "sitecustomize.py"), "w") as f:
        f.write('import multiprocessing as _mp\n')
        f.write('_original_pool = _mp.Pool\n')
        f.write('def _recording_pool(processes=None, *args, **kwargs):\n')
        f.write('    with open("/tmp/verifier_pool_calls.log", "a") as _log:\n')
        f.write('        _log.write(str(processes) + "\\n")\n')
        f.write('    return _original_pool(processes, *args, **kwargs)\n')
        f.write('_mp.Pool = _recording_pool\n')

    wrapper = '''import importlib.util\nimport json\nimport os\n_spec = importlib.util.spec_from_file_location("_submitted_integrator_impl", "/tmp/submitted_integrator_impl.py")\n_impl = importlib.util.module_from_spec(_spec)\n_spec.loader.exec_module(_impl)\ndef simulate(k, t_end):\n    with open("/tmp/verifier_sim_calls.log", "a") as f:\n        f.write(json.dumps([os.getpid(), float(k), float(t_end)]) + "\\n")\n    return _impl.simulate(k, t_end)\n'''

    try:
        with open(pdb_path, "w") as f:
            f.write(make_pdb(coords))
        with open(integrator_path, "w") as f:
            f.write(wrapper)

        shutil.rmtree("/home/user/results", ignore_errors=True)
        env = os.environ.copy()
        env["PYTHONPATH"] = hook_dir + (os.pathsep + env["PYTHONPATH"] if env.get("PYTHONPATH") else "")
        completed = subprocess.run(
            [pipeline_path], cwd="/tmp", env=env, text=True,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=90
        )
        assert completed.returncode == 0, \
            f"Pipeline failed when executed from scratch. stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"

        parsed = get_ca_coordinates(pdb_path)
        array = np.asarray(parsed, dtype=float)
        distances = np.linalg.norm(array[:, None, :] - array[None, :, :], axis=2)
        expected_sigma = float(np.linalg.svd(distances, compute_uv=False)[0])
        rounded_sigma = round(expected_sigma, 4)

        svd_file = "/home/user/results/svd_max.txt"
        assert os.path.isfile(svd_file), "Executed pipeline did not create svd_max.txt"
        with open(svd_file) as f:
            actual_sigma = float(f.read().strip())
        assert math.isclose(actual_sigma, rounded_sigma, rel_tol=0.0, abs_tol=5e-5), \
            f"Dynamic PDB expected rounded sigma {rounded_sigma}, got {actual_sigma}"

        result_file = "/home/user/results/ensemble_final.json"
        assert os.path.isfile(result_file), "Executed pipeline did not create ensemble_final.json"
        with open(result_file) as f:
            results = json.load(f)
        expected_keys = {"0.5", "1.0", "1.5", "2.0"}
        assert isinstance(results, dict) and set(results) == expected_keys
        for key in expected_keys:
            assert type(results[key]) in (int, float) and not isinstance(results[key], bool)
            expected = 100.0 * math.exp(-float(key) * actual_sigma * 5.0)
            assert math.isclose(float(results[key]), expected, rel_tol=1e-2, abs_tol=1e-9), \
                f"Dynamic ensemble result for {key} is incorrect"

        assert os.path.isfile(pool_log), "run_ensemble.py did not execute multiprocessing.Pool"
        with open(pool_log) as f:
            pool_sizes = [line.strip() for line in f if line.strip()]
        assert "4" in pool_sizes, "run_ensemble.py must execute multiprocessing.Pool with 4 workers"

        assert os.path.isfile(sim_log), "run_ensemble.py did not call integrator.simulate"
        with open(sim_log) as f:
            sim_calls = [json.loads(line) for line in f if line.strip()]
        assert len(sim_calls) == 4, f"Expected four ensemble simulate calls, observed {len(sim_calls)}"
        expected_ks = sorted(float(c) * actual_sigma for c in expected_keys)
        actual_ks = sorted(float(call[1]) for call in sim_calls)
        assert all(math.isclose(a, e, rel_tol=1e-10, abs_tol=1e-12) for a, e in zip(actual_ks, expected_ks)), \
            "Ensemble did not call simulate with all four scaled decay rates"
        assert all(math.isclose(float(call[2]), 5.0) for call in sim_calls), \
            "Ensemble must call simulate with t_end=5.0"
    finally:
        with open(pdb_path, "wb") as f:
            f.write(original_pdb)
        with open(integrator_path, "wb") as f:
            f.write(original_integrator)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
