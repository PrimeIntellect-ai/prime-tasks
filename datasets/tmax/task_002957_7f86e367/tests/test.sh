#!/bin/bash
mkdir -p /logs/verifier
echo "0" > /logs/verifier/reward.txt

cat << 'CPP_EOF' > /tmp/oracle.cpp
#include <iostream>
#include <random>
#include <omp.h>
using namespace std;
int main(int argc, char** argv) {
    if (argc < 6) return 1;
    double k = stod(argv[1]);
    double c = stod(argv[2]);
    double x0 = stod(argv[3]);
    double y0 = stod(argv[4]);
    int N_mc = stoi(argv[5]);
    double dt = 0.01;
    int steps = 500;
    double sum_x = 0, sum_y = 0;
    #pragma omp parallel
    {
        double local_sum_x = 0, local_sum_y = 0;
        mt19937 gen(42 + omp_get_thread_num());
        normal_distribution<double> dist(0.0, 0.1);
        #pragma omp for
        for (int i = 0; i < N_mc; ++i) {
            double x = x0 + dist(gen);
            double y = y0 + dist(gen);
            for (int s = 0; s < steps; ++s) {
                double k1_x = y;
                double k1_y = -k*x - c*y;
                double k2_x = y + 0.5*dt*k1_y;
                double k2_y = -k*(x + 0.5*dt*k1_x) - c*(y + 0.5*dt*k1_y);
                double k3_x = y + 0.5*dt*k2_y;
                double k3_y = -k*(x + 0.5*dt*k2_x) - c*(y + 0.5*dt*k2_y);
                double k4_x = y + dt*k3_y;
                double k4_y = -k*(x + dt*k3_x) - c*(y + dt*k3_y);
                x += (dt/6.0)*(k1_x + 2*k2_x + 2*k3_x + k4_x);
                y += (dt/6.0)*(k1_y + 2*k2_y + 2*k3_y + k4_y);
            }
            local_sum_x += x;
            local_sum_y += y;
        }
        #pragma omp atomic
        sum_x += local_sum_x;
        #pragma omp atomic
        sum_y += local_sum_y;
    }
    cout << sum_x/N_mc << " " << sum_y/N_mc << endl;
    return 0;
}
CPP_EOF

cat << 'PY_EOF' > /tmp/test_pipeline.py
import hashlib
import json
import math
import os
import random
import subprocess
import time

import h5py
import numpy as np
import redis
import requests

WORKSPACE = "/home/user/workspace"
WORKER = WORKSPACE + "/mc_worker"
SOURCE = WORKSPACE + "/mc_integrator.cpp"
API_SOURCE = WORKSPACE + "/api_server.py"
NOTEBOOK = WORKSPACE + "/workflow.ipynb"
H5_PATH = WORKSPACE + "/training_data.h5"
ORACLE = "/tmp/oracle_worker"
SOURCE_WORKER = "/tmp/source_worker"


def run_pair(path, args):
    result = subprocess.run([path] + [str(x) for x in args], capture_output=True,
                            text=True, timeout=30)
    assert result.returncode == 0, result.stderr
    assert result.stderr.strip() == "", f"Unexpected stderr from {path}: {result.stderr}"
    fields = result.stdout.strip().split()
    assert len(fields) == 2, f"Expected exactly two output fields, got {result.stdout!r}"
    values = tuple(float(x) for x in fields)
    assert all(math.isfinite(x) for x in values)
    return values


def assert_close(actual, expected, args):
    assert math.isclose(actual[0], expected[0], rel_tol=1e-3, abs_tol=1e-3), \
        f"x mismatch for {args}: {actual[0]} versus {expected[0]}"
    assert math.isclose(actual[1], expected[1], rel_tol=1e-3, abs_tol=1e-3), \
        f"y mismatch for {args}: {actual[1]} versus {expected[1]}"


def h5_values(path):
    values = []
    with h5py.File(path, "r") as handle:
        def visit(_name, obj):
            if isinstance(obj, h5py.Dataset) and np.issubdtype(obj.dtype, np.number):
                arr = np.asarray(obj[...])
                if arr.size:
                    assert np.all(np.isfinite(arr)), "HDF5 contains non-finite numerical data"
                    values.extend(arr.astype(float, copy=False).ravel().tolist())
        handle.visititems(visit)
    assert values, "HDF5 file contains no nonempty numerical datasets"
    return values


def digest(path):
    with open(path, "rb") as stream:
        return hashlib.sha256(stream.read()).hexdigest()


def test_worker_and_fixed_source():
    assert os.path.isfile(SOURCE), "mc_integrator.cpp is missing"
    assert os.path.isfile(WORKER), "mc_worker is missing"
    assert os.access(WORKER, os.X_OK), "mc_worker is not executable"

    linked = subprocess.run(["ldd", WORKER], capture_output=True, text=True, check=True).stdout.lower()
    assert "libgomp" in linked or "libomp" in linked, "mc_worker is not linked with OpenMP"

    built = subprocess.run(["g++", "-O2", "-fopenmp", SOURCE, "-o", SOURCE_WORKER],
                           capture_output=True, text=True)
    assert built.returncode == 0, f"mc_integrator.cpp does not compile with OpenMP: {built.stderr}"

    random.seed(42)
    cases = []
    for _ in range(100):
        cases.append((random.uniform(0.1, 5.0), random.uniform(0.0, 2.0),
                      random.uniform(-10.0, 10.0), random.uniform(-10.0, 10.0),
                      random.randint(10, 100)))

    for args in cases:
        expected = run_pair(ORACLE, args)
        assert_close(run_pair(WORKER, args), expected, args)

    for args in cases[:8]:
        expected = run_pair(ORACLE, args)
        assert_close(run_pair(SOURCE_WORKER, args), expected, args)


def test_configuration_services_notebook_and_rest_workflow():
    assert os.path.isfile(API_SOURCE), "api_server.py is missing"
    api_text = open(API_SOURCE, encoding="utf-8").read()
    lowered = api_text.lower()
    assert "localhost" in lowered and "6379" in lowered, \
        "api_server.py is not configured for Redis at localhost:6379"
    assert "/home/user/workspace/mc_worker" in api_text, \
        "api_server.py does not configure the required worker path"
    assert "mpirun" in lowered, "api_server.py does not invoke the worker through mpirun"

    client = redis.Redis(host="localhost", port=6379, socket_connect_timeout=2,
                         socket_timeout=2)
    assert client.ping() is True, "Redis is not running on localhost:6379"

    process_list = subprocess.run(["ps", "-eo", "args"], capture_output=True,
                                  text=True, check=True).stdout.lower()
    assert "api_server.py" in process_list, "The Flask API server is not running"
    assert "jupyter" in process_list and ("lab" in process_list or "8888" in process_list), \
        "Jupyter Lab is not running"

    api_probe = requests.get("http://localhost:5000/", timeout=5)
    assert api_probe.status_code < 500, "Nothing usable is listening on Flask port 5000"
    jupyter_probe = requests.get("http://localhost:8888/", timeout=5, allow_redirects=False)
    assert jupyter_probe.status_code in (200, 302, 303, 307, 308, 401, 403), \
        f"Jupyter Lab is not responding on port 8888: {jupyter_probe.status_code}"

    assert os.path.isfile(NOTEBOOK), "workflow.ipynb is missing"
    with open(NOTEBOOK, encoding="utf-8") as stream:
        notebook = json.load(stream)
    code_cells = [c for c in notebook.get("cells", []) if c.get("cell_type") == "code"]
    assert code_cells, "workflow.ipynb contains no code cells"
    code = "\n".join("".join(c.get("source", [])) for c in code_cells).lower()
    assert "/generate" in code and ("requests" in code or "urllib" in code or "curl" in code), \
        "The notebook does not send a request to the generation endpoint"
    assert "training_data.h5" in code and ("h5py" in code or "hdf5" in code), \
        "The notebook does not verify the generated HDF5 file"
    assert any(c.get("execution_count") is not None for c in code_cells), \
        "The workflow notebook has not been executed"

    assert os.path.isfile(H5_PATH), "training_data.h5 was not produced"
    h5_values(H5_PATH)
    before = digest(H5_PATH)

    payload = {"k": 1.731, "c": 0.417, "x0": 2.345, "y0": -1.234, "N_mc": 37}
    expected = run_pair(WORKER, tuple(payload[k] for k in ("k", "c", "x0", "y0", "N_mc")))
    response = requests.post("http://localhost:5000/generate", json=payload, timeout=30)
    assert 200 <= response.status_code < 300, \
        f"POST /generate failed with {response.status_code}: {response.text}"

    changed = False
    values = None
    for _ in range(40):
        try:
            if os.path.isfile(H5_PATH) and digest(H5_PATH) != before:
                values = h5_values(H5_PATH)
                changed = True
                break
        except (OSError, ValueError):
            pass
        time.sleep(0.5)
    assert changed, "The REST generation request did not update training_data.h5"
    assert any(math.isclose(v, expected[0], rel_tol=2e-3, abs_tol=2e-3) for v in values), \
        "Generated HDF5 data does not contain the worker's x result"
    assert any(math.isclose(v, expected[1], rel_tol=2e-3, abs_tol=2e-3) for v in values), \
        "Generated HDF5 data does not contain the worker's y result"
PY_EOF

if g++ -O3 -fopenmp /tmp/oracle.cpp -o /tmp/oracle_worker && \
   python3 -m pytest /tmp/test_pipeline.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
fi
