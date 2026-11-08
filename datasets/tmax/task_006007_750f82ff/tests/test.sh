#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import hashlib
import json
import os
import re
import secrets
import shutil
import subprocess
import tempfile

import numpy as np
from scipy.optimize import minimize

SIMULATION_DIR = "/home/user/simulation"
C_FILE = os.path.join(SIMULATION_DIR, "objective.c")
SO_FILE = os.path.join(SIMULATION_DIR, "libobjective.so")
PY_FILE = os.path.join(SIMULATION_DIR, "optimize.py")
RESULT_FILE = os.path.join(SIMULATION_DIR, "result.txt")
RESULT_RE = re.compile(r"(-?\d+\.\d{4}),(-?\d+\.\d{4})")


def load_cost(path):
    lib = ctypes.CDLL(path)
    func = lib.compute_cost
    func.argtypes = [ctypes.c_double, ctypes.c_double]
    func.restype = ctypes.c_double
    return lib, func


def read_result():
    assert os.path.isfile(RESULT_FILE), f"Result file {RESULT_FILE} was not created by optimize.py."
    with open(RESULT_FILE) as f:
        content = f.read().strip()
    match = RESULT_RE.fullmatch(content)
    assert match is not None, (
        f"Content of {RESULT_FILE} ('{content}') does not match the required format 'x.xxxx,y.yyyy'."
    )
    return content, float(match.group(1)), float(match.group(2))


def run_script(extra_env=None):
    env = os.environ.copy()
    env["OMP_NUM_THREADS"] = "4"
    if extra_env:
        env.update(extra_env)
    result = subprocess.run(
        ["python3", PY_FILE], capture_output=True, text=True,
        cwd=SIMULATION_DIR, env=env, timeout=180
    )
    assert result.returncode == 0, f"Running optimize.py failed with error:\n{result.stderr}"
    return read_result()


def test_objective_c_fixed():
    assert os.path.isfile(C_FILE), f"File {C_FILE} is missing."
    with open(C_FILE) as f:
        content = f.read()
    assert "float sum" not in content, "The accumulator 'sum' is still declared as a float in objective.c."
    assert "double sum" in content, "The accumulator 'sum' should be declared as a double in objective.c."
    assert re.search(r"#\s*pragma\s+omp\s+parallel\s+for[^\n]*reduction\s*\(\s*\+\s*:\s*sum\s*\)", content), \
        "The OpenMP parallel reduction over sum is missing."


def test_shared_library_compiled_and_usable():
    assert os.path.isfile(SO_FILE), f"Shared library {SO_FILE} is missing."
    with open(SO_FILE, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{SO_FILE} is not a valid ELF file."

    header = subprocess.run(["readelf", "-h", SO_FILE], capture_output=True, text=True, check=True).stdout
    assert re.search(r"Type:\s+DYN", header), "libobjective.so is not an ELF shared object."
    dynamic = subprocess.run(["ldd", SO_FILE], capture_output=True, text=True, check=True).stdout
    assert "libgomp" in dynamic, "libobjective.so is not linked with GCC OpenMP support."

    submitted_lib, submitted = load_cost(SO_FILE)
    assert np.isfinite(submitted(0.25, -0.5)), "compute_cost did not return a finite double."

    with tempfile.TemporaryDirectory() as td:
        rebuilt = os.path.join(td, "librebuilt.so")
        build = subprocess.run(
            ["gcc", "-O2", "-fopenmp", "-fPIC", "-shared", C_FILE, "-lm", "-o", rebuilt],
            capture_output=True, text=True
        )
        assert build.returncode == 0, f"objective.c cannot be compiled as required:\n{build.stderr}"
        rebuilt_lib, rebuilt_cost = load_cost(rebuilt)

        # Secretly selected points ensure both the submitted artifact and rebuilt source
        # implement the supplied landscape rather than a constant or fixed-coordinate stub.
        rng = np.random.default_rng(secrets.randbits(64))
        points = [(float(x), float(y)) for x, y in rng.uniform(-2.5, 5.5, size=(4, 2))]
        mean_t = 999999.0 / 2000000.0
        for x, y in points:
            expected = ((x - 2.0) ** 2 + (y - 3.0) ** 2 * mean_t
                        + 0.01 * np.sin(x * 100.0) * np.cos(y * 100.0))
            actual_submitted = submitted(x, y)
            actual_rebuilt = rebuilt_cost(x, y)
            assert abs(actual_rebuilt - expected) < 2e-6, \
                "objective.c's mathematical cost landscape was changed."
            assert abs(actual_submitted - actual_rebuilt) < 2e-9, \
                "libobjective.so does not correspond to the current objective.c."

        # With a double accumulator, changing thread count must not affect the result.
        # Calls are made in fresh processes so the OpenMP runtime sees each setting.
        probe = r'''import ctypes, sys
p=sys.argv[1]; x=float(sys.argv[2]); y=float(sys.argv[3])
l=ctypes.CDLL(p); f=l.compute_cost
f.argtypes=[ctypes.c_double,ctypes.c_double]; f.restype=ctypes.c_double
print(format(f(x,y), '.17g'))'''
        values = []
        for threads in (1, 2, 3, 7):
            env = os.environ.copy()
            env["OMP_NUM_THREADS"] = str(threads)
            out = subprocess.run(
                ["python3", "-c", probe, SO_FILE, "1.234567", "2.345678"],
                capture_output=True, text=True, check=True, env=env, timeout=60
            )
            values.append(float(out.stdout.strip()))
        assert max(values) - min(values) < 1e-12, f"compute_cost varies with OpenMP thread count: {values}"


def test_optimize_script_exists():
    assert os.path.isfile(PY_FILE), f"Python script {PY_FILE} is missing."


def test_optimize_script_execution_and_result():
    content, x, y = run_script()
    assert abs(x - 2.0) < 0.05, f"Optimized x-coordinate {x} is not close enough to the expected value 2.0."
    assert abs(y - 3.0) < 0.05, f"Optimized y-coordinate {y} is not close enough to the expected value 3.0."

    # Independently minimize the actual exported function and compare rounded output.
    lib, cost = load_cost(SO_FILE)
    expected = minimize(lambda coords: cost(float(coords[0]), float(coords[1])),
                        [0.0, 0.0], method="Nelder-Mead")
    expected_text = f"{expected.x[0]:.4f},{expected.x[1]:.4f}"
    assert content == expected_text, \
        f"optimize.py produced {content}, but minimizing the actual library produced {expected_text}."


def test_script_really_uses_ctypes_and_scipy():
    # Replace the library temporarily with a secret quadratic. A genuine generic
    # ctypes/SciPy script follows it; a script that merely writes fixed coordinates does not.
    token = secrets.randbits(40)
    cx = 0.8 + (token % 1200) / 1000.0
    cy = -1.8 + ((token // 1200) % 1200) / 1000.0
    challenge_source = f'''double compute_cost(double x, double y) {{
        return (x - ({cx:.12f}))*(x - ({cx:.12f})) +
               0.7*(y - ({cy:.12f}))*(y - ({cy:.12f}));
    }}'''

    with tempfile.TemporaryDirectory() as td:
        backup = os.path.join(td, "libobjective.original.so")
        challenge_c = os.path.join(td, "challenge.c")
        log_path = os.path.join(td, "calls.jsonl")
        instrument = os.path.join(td, "instrument")
        os.mkdir(instrument)
        shutil.copy2(SO_FILE, backup)
        with open(challenge_c, "w") as f:
            f.write(challenge_source)

        sitecustomize = r'''import ctypes, json, os
import scipy.optimize as _so
_log_path = os.environ.get("VERIFY_CALL_LOG")
def _log(obj):
    if _log_path:
        with open(_log_path, "a") as f:
            f.write(json.dumps(obj) + "\n")

_orig_cdll = ctypes.CDLL
class _FunctionProxy:
    def __init__(self, fn, name):
        object.__setattr__(self, "_fn", fn)
        object.__setattr__(self, "_name", name)
    def __getattr__(self, name):
        return getattr(self._fn, name)
    def __setattr__(self, name, value):
        setattr(self._fn, name, value)
    def __call__(self, *args):
        _log({"kind":"compute", "name":self._name, "argc":len(args),
              "argtypes":[getattr(t, "__name__", str(t)) for t in (self._fn.argtypes or [])],
              "restype":getattr(self._fn.restype, "__name__", str(self._fn.restype))})
        return self._fn(*args)
class _LibraryProxy:
    def __init__(self, lib): object.__setattr__(self, "_lib", lib)
    def __getattr__(self, name):
        value = getattr(self._lib, name)
        return _FunctionProxy(value, name) if name == "compute_cost" else value
    def __setattr__(self, name, value): setattr(self._lib, name, value)
def _cdll(name, *args, **kwargs):
    _log({"kind":"cdll", "path":str(name)})
    return _LibraryProxy(_orig_cdll(name, *args, **kwargs))
ctypes.CDLL = _cdll
ctypes.cdll.LoadLibrary = _cdll

_orig_minimize = _so.minimize
def _minimize(fun, x0, *args, **kwargs):
    method = kwargs.get("method")
    if method is None and len(args) >= 2:
        method = args[1]
    try: start = [float(v) for v in x0]
    except Exception: start = None
    _log({"kind":"minimize", "method":method, "x0":start, "callable":callable(fun)})
    fun([0.314159, -0.271828])
    return _orig_minimize(fun, x0, *args, **kwargs)
_so.minimize = _minimize
'''
        with open(os.path.join(instrument, "sitecustomize.py"), "w") as f:
            f.write(sitecustomize)

        try:
            build = subprocess.run(
                ["gcc", "-fPIC", "-shared", challenge_c, "-o", SO_FILE],
                capture_output=True, text=True
            )
            assert build.returncode == 0, build.stderr
            challenge_hash = hashlib.sha256(open(SO_FILE, "rb").read()).hexdigest()
            content, x, y = run_script({"PYTHONPATH": instrument, "VERIFY_CALL_LOG": log_path})
            assert hashlib.sha256(open(SO_FILE, "rb").read()).hexdigest() == challenge_hash, \
                "optimize.py unexpectedly replaced libobjective.so instead of loading it."

            challenge_lib, challenge_cost = load_cost(SO_FILE)
            expected = minimize(lambda p: challenge_cost(float(p[0]), float(p[1])),
                                [0.0, 0.0], method="Nelder-Mead")
            expected_text = f"{expected.x[0]:.4f},{expected.x[1]:.4f}"
            assert content == expected_text, \
                f"optimize.py did not optimize the library it loaded: got {content}, expected {expected_text}."

            assert os.path.isfile(log_path), "No ctypes or scipy calls were observed while running optimize.py."
            records = [json.loads(line) for line in open(log_path) if line.strip()]
            loads = [r for r in records if r.get("kind") == "cdll"]
            mins = [r for r in records if r.get("kind") == "minimize"]
            calls = [r for r in records if r.get("kind") == "compute"]
            assert any(os.path.basename(r.get("path", "")) == "libobjective.so" for r in loads), \
                "optimize.py did not load libobjective.so using ctypes."
            assert any(r.get("method") == "Nelder-Mead" and r.get("x0") == [0.0, 0.0]
                       and r.get("callable") for r in mins), \
                "optimize.py did not call scipy.optimize.minimize with Nelder-Mead and x0=[0.0, 0.0]."
            assert any(r.get("name") == "compute_cost" and r.get("argc") == 2
                       and r.get("argtypes") == ["c_double", "c_double"]
                       and r.get("restype") == "c_double" for r in calls), \
                "compute_cost was not called with ctypes argtypes/restype set to c_double."
        finally:
            shutil.copy2(backup, SO_FILE)


def test_determinism():
    results = set()
    for _ in range(3):
        content, _, _ = run_script()
        results.add(content)
    assert len(results) == 1, f"Optimization results are not deterministic! Got different results: {results}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
