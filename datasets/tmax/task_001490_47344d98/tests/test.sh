#!/bin/bash
set +e
mkdir -p /logs/verifier

cat << 'EOF' > /tmp/h5_counter.c
#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>

typedef long hid_t;
typedef unsigned int flags_t;
static unsigned long open_count = 0;

hid_t H5Fopen(const char *name, flags_t flags, hid_t fapl_id) {
    static hid_t (*real_H5Fopen)(const char *, flags_t, hid_t) = NULL;
    if (!real_H5Fopen) {
        real_H5Fopen = (hid_t (*)(const char *, flags_t, hid_t))dlsym(RTLD_NEXT, "H5Fopen");
        if (!real_H5Fopen) _Exit(127);
    }
    open_count++;
    return real_H5Fopen(name, flags, fapl_id);
}

__attribute__((destructor)) static void write_count(void) {
    const char *path = getenv("H5_OPEN_COUNT_FILE");
    if (path) {
        FILE *f = fopen(path, "w");
        if (f) {
            fprintf(f, "%lu\n", open_count);
            fclose(f);
        }
    }
}
EOF

cat << 'EOF' > /tmp/reference.cpp
#include <iostream>
#include <vector>
#include <random>
#include <cmath>
#include "H5Cpp.h"
using namespace H5;
using namespace std;

vector<double> load_data() {
    H5File file("/home/user/input.h5", H5F_ACC_RDONLY);
    DataSet dataset = file.openDataSet("y_data");
    DataSpace dataspace = dataset.getSpace();
    hssize_t num_elements = dataspace.getSimpleExtentNpoints();
    vector<double> data(num_elements);
    dataset.read(data.data(), PredType::NATIVE_DOUBLE);
    return data;
}

double log_likelihood(double a, double b, const vector<double>& y) {
    double ll = 0.0;
    for (size_t i = 0; i < y.size(); ++i) {
        double expected = a * i + b;
        double diff = y[i] - expected;
        ll += -0.5 * diff * diff;
    }
    return ll;
}

int main() {
    vector<double> y = load_data();
    mt19937 gen(42);
    normal_distribution<double> proposal(0.0, 0.1);
    uniform_real_distribution<double> unif(0.0, 1.0);
    double current_a = 0.0, current_b = 0.0;
    double current_ll = log_likelihood(current_a, current_b, y);
    double sum_a = 0.0, sum_b = 0.0;
    int steps = 10000;
    for (int i = 0; i < steps; ++i) {
        double prop_a = current_a + proposal(gen);
        double prop_b = current_b + proposal(gen);
        double prop_ll = log_likelihood(prop_a, prop_b, y);
        if (log(unif(gen)) < (prop_ll - current_ll)) {
            current_a = prop_a;
            current_b = prop_b;
            current_ll = prop_ll;
        }
        sum_a += current_a;
        sum_b += current_b;
    }
    double mean_a = sum_a / steps;
    double mean_b = sum_b / steps;
    double z = 0.0;
    double lr = 0.1;
    for (int i = 0; i < 50; ++i) {
        double grad = 4*z - 2*mean_a - 2*mean_b;
        z = z - lr * grad;
    }
    cout << z << endl;
    return 0;
}
EOF

build_ok=1
gcc -shared -fPIC /tmp/h5_counter.c -o /tmp/h5_counter.so -ldl || build_ok=0
h5c++ -O2 /tmp/reference.cpp -o /tmp/reference_mcmc || build_ok=0

cat << 'PYEOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess

import h5py
import numpy as np

EXE = "/home/user/mcmc_opt"
SOURCE = "/home/user/mcmc_opt.cpp"
OUTPUT = "/home/user/output.txt"
REFERENCE = "/tmp/reference_mcmc"
COUNTER = "/tmp/h5_counter.so"
FLOAT_ONLY = re.compile(r"^[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?\n?$")


def write_data(values):
    with h5py.File("/home/user/input.h5", "w") as f:
        f.create_dataset("y_data", data=np.asarray(values, dtype=np.float64), dtype="f8")


def canonical_data():
    np.random.seed(42)
    return 2.5 * np.arange(100) + 10.0 + np.random.normal(0, 1.0, size=100)


def run(path, monitored=False):
    env = os.environ.copy()
    count_path = "/tmp/h5_open_count.txt"
    if monitored:
        try:
            os.unlink(count_path)
        except FileNotFoundError:
            pass
        env["LD_PRELOAD"] = COUNTER
        env["H5_OPEN_COUNT_FILE"] = count_path
    result = subprocess.run(
        [path], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        env=env, timeout=30, check=False
    )
    assert result.returncode == 0, (
        f"{path} exited with {result.returncode}: "
        f"{result.stderr.decode(errors='replace')}"
    )
    if monitored:
        assert os.path.isfile(count_path), "Could not observe the executable's HDF5 file accesses"
        with open(count_path) as f:
            count = int(f.read().strip())
        assert count == 1, (
            f"The executable opened the HDF5 input {count} times; optimized code must load it once"
        )
    return result.stdout


def extract_function_body(source, function_name):
    match = re.search(r"\b" + re.escape(function_name) + r"\s*\([^;]*?\)\s*\{", source, re.S)
    assert match, f"Could not find a definition of {function_name}"
    start = source.find("{", match.start())
    depth = 0
    for pos in range(start, len(source)):
        if source[pos] == "{":
            depth += 1
        elif source[pos] == "}":
            depth -= 1
            if depth == 0:
                return source[start + 1:pos]
    raise AssertionError(f"Could not parse the body of {function_name}")


def test_executable_exists_and_is_compiled():
    assert os.path.isfile(EXE), f"Compiled executable not found at {EXE}"
    assert os.access(EXE, os.X_OK), f"File {EXE} is not executable"
    with open(EXE, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{EXE} is not a compiled ELF executable"


def test_cpp_bottleneck_fixed():
    assert os.path.isfile(SOURCE), f"C++ source file missing: {SOURCE}"
    with open(SOURCE) as f:
        content = f.read()
    inefficient_line = "vector<double> y = load_data();"
    assert inefficient_line not in content, (
        "The deliberate bottleneck (calling load_data() inside the loop) is still present in the C++ file."
    )
    body = extract_function_body(content, "log_likelihood")
    assert not re.search(r"\bload_data\s*\(", body), (
        "log_likelihood still loads the HDF5 data on each likelihood evaluation"
    )


def test_execution_output_and_behavior():
    assert os.path.isfile(OUTPUT), f"Output file not found at {OUTPUT}"
    with open(OUTPUT, "rb") as f:
        saved_output = f.read()

    write_data(canonical_data())
    expected = run(REFERENCE)
    actual = run(EXE, monitored=True)

    assert FLOAT_ONLY.fullmatch(actual.decode("ascii")), "Executable stdout must contain only the final float"
    assert saved_output == actual, "output.txt is not the exact stdout produced by the executable"
    content = saved_output.decode("ascii").strip()
    try:
        z_value = float(content)
    except ValueError:
        raise AssertionError(f"Output file {OUTPUT} does not contain a valid float. Found: '{content}'")
    expected_z = 6.25
    tolerance = 0.1
    assert abs(z_value - expected_z) <= tolerance, f"Expected z value near {expected_z}, but got {z_value}"
    assert actual == expected, "Executable output does not preserve the required MCMC and gradient-descent behavior"

    # Exercise the executable on verifier-generated data so a hard-coded answer cannot pass.
    rng = secrets.SystemRandom()
    a = rng.uniform(1.2, 3.8)
    b = rng.uniform(4.0, 16.0)
    challenge = [a * i + b + 0.35 * np.sin(i * 0.73) for i in range(100)]
    write_data(challenge)
    try:
        challenge_expected = run(REFERENCE)
        challenge_actual = run(EXE, monitored=True)
        assert challenge_actual == challenge_expected, (
            "Executable does not preserve the required computation on verifier-generated input"
        )
    finally:
        write_data(canonical_data())
PYEOF

if [ "$build_ok" -eq 1 ] && python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
