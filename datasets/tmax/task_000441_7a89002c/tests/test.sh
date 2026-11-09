#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import re
import subprocess
import textwrap

PROJECT = "/app/project"
EXECUTABLE = os.path.join(PROJECT, "optimize_sensor")
RESULT = os.path.join(PROJECT, "result.txt")
SENSOR = os.path.join(PROJECT, "sensor_data.csv")


def parse_cost(path):
    try:
        with open(path, "r") as f:
            content = f.read()
    except Exception as e:
        assert False, f"Failed to read {path}: {e}"

    try:
        cost_str = content.split("Final cost:")[1].strip()
        cost = float(cost_str)
    except Exception as e:
        assert False, f"Failed to parse the final cost from {path}. Error: {e}\nFile content:\n{content}"
    return cost


def test_executable_exists():
    assert os.path.isfile(EXECUTABLE), f"The executable {EXECUTABLE} is missing."
    assert os.access(EXECUTABLE, os.X_OK), f"The file {EXECUTABLE} is not executable."


def test_liblbfgs_installed():
    lib_path_a = "/app/local/lib/liblbfgs.a"
    lib_path_so = "/app/local/lib/liblbfgs.so"
    assert os.path.isfile(lib_path_a) or os.path.isfile(lib_path_so), "liblbfgs was not installed to /app/local/lib."


def test_result_file_exists():
    assert os.path.isfile(RESULT), f"The result file {RESULT} is missing."


def test_cost_threshold():
    cost = parse_cost(RESULT)
    assert cost <= 0.01, f"Metric threshold failed: Final cost {cost} is greater than the threshold of 0.01."


def compile_c(source, output):
    source_path = output + ".c"
    with open(source_path, "w") as f:
        f.write(source)
    proc = subprocess.run(
        ["gcc", "-std=c99", "-Wall", "-Wextra", "-I/app/local/include",
         source_path, "/app/local/lib/liblbfgs.a", "-lm", "-o", output],
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=30,
    )
    assert proc.returncode == 0, f"Failed to compile verification harness:\n{proc.stdout}"


def test_clean_build_and_execute_artifact():
    build = subprocess.run(
        ["make", "clean", "all"], cwd=PROJECT,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=60,
    )
    assert build.returncode == 0, f"Project clean build failed:\n{build.stdout}"
    assert os.path.isfile(EXECUTABLE) and os.access(EXECUTABLE, os.X_OK)
    with open(EXECUTABLE, "rb") as f:
        assert f.read(4) == b"\x7fELF", "optimize_sensor is not a compiled ELF executable."

    original_sensor = open(SENSOR, "rb").read()
    try:
        with open(SENSOR, "w") as f:
            f.write("NaN,inf\n")
        if os.path.exists(RESULT):
            os.remove(RESULT)
        run = subprocess.run(
            [EXECUTABLE], cwd=PROJECT,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=30,
        )
        assert run.returncode == 0, f"optimize_sensor failed when executed:\n{run.stdout}"
        assert os.path.isfile(RESULT), "Running optimize_sensor did not create result.txt."
        cost = parse_cost(RESULT)
        assert math.isfinite(cost), f"The executed optimizer reported a non-finite cost: {cost}"
        assert cost <= 0.01, f"The executed optimizer did not converge: final cost was {cost}"
    finally:
        with open(SENSOR, "wb") as f:
            f.write(original_sensor)


def test_evaluate_gradient_and_real_optimizer_result():
    harness = r'''
#include <math.h>
#include <stdio.h>
#define main submission_main
#include "/app/project/main.c"
#undef main

static double true_cost(double a, double b) {
    double d1 = 1.0 - a;
    double d2 = b - a * a;
    return d1 * d1 + 100.0 * d2 * d2;
}

int main(void) {
    lbfgsfloatval_t p[2] = {0.3, -0.7};
    lbfgsfloatval_t g[2] = {0.0, 0.0};
    double expected_fx = true_cost(p[0], p[1]);
    double expected_g0 = -2.0 * (1.0 - p[0]) - 400.0 * p[0] * (p[1] - p[0] * p[0]);
    double expected_g1 = 200.0 * (p[1] - p[0] * p[0]);
    double got_fx = evaluate(NULL, p, g, 2, 0.0);
    if (fabs(got_fx - expected_fx) > 1e-8 ||
        fabs(g[0] - expected_g0) > 1e-8 ||
        fabs(g[1] - expected_g1) > 1e-8) {
        fprintf(stderr, "incorrect objective or gradient: fx=%g g=(%g,%g)\n", got_fx, g[0], g[1]);
        return 10;
    }

    lbfgsfloatval_t *x = lbfgs_malloc(2);
    lbfgsfloatval_t fx = 0.0;
    if (!x) return 11;
    x[0] = 0.0;
    x[1] = 0.0;
    int ret = lbfgs(2, x, &fx, evaluate, NULL, NULL, NULL);
    double recomputed = true_cost(x[0], x[1]);
    if (ret < 0 || !isfinite(fx) || !isfinite(recomputed) ||
        recomputed > 0.01 || fabs(fx - recomputed) > 1e-6) {
        fprintf(stderr, "optimizer failed: ret=%d x=(%g,%g) reported=%g recomputed=%g\n",
                ret, x[0], x[1], fx, recomputed);
        lbfgs_free(x);
        return 12;
    }
    lbfgs_free(x);
    return 0;
}
'''
    output = "/tmp/check_optimizer"
    compile_c(harness, output)
    run = subprocess.run([output], stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                         text=True, timeout=30)
    assert run.returncode == 0, f"Gradient/convergence verification failed:\n{run.stdout}"


def test_invalid_sensor_values_are_replaced_with_zero():
    harness = r'''
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

#define main submission_main
#define lbfgs probe_lbfgs
#define lbfgs_malloc probe_lbfgs_malloc
#define lbfgs_free probe_lbfgs_free
#include "/app/project/main.c"
#undef lbfgs_free
#undef lbfgs_malloc
#undef lbfgs
#undef main

static lbfgsfloatval_t seen0, seen1;
static int called;

lbfgsfloatval_t *probe_lbfgs_malloc(int n) {
    return (lbfgsfloatval_t *)calloc((size_t)n, sizeof(lbfgsfloatval_t));
}
void probe_lbfgs_free(lbfgsfloatval_t *x) { free(x); }
int probe_lbfgs(int n, lbfgsfloatval_t *x, lbfgsfloatval_t *ptr_fx,
                lbfgs_evaluate_t e, lbfgs_progress_t p, void *instance,
                lbfgs_parameter_t *param) {
    (void)n; (void)e; (void)p; (void)instance; (void)param;
    seen0 = x[0]; seen1 = x[1]; called = 1;
    *ptr_fx = 0.0;
    return 0;
}

static int check_case(const char *data, double want0, double want1) {
    FILE *f = fopen("sensor_data.csv", "w");
    if (!f) return 20;
    fputs(data, f);
    fclose(f);
    called = 0;
    char *argv[] = {"probe", NULL};
    if (submission_main(1, argv) != 0 || !called) return 21;
    if (!isfinite(seen0) || !isfinite(seen1) ||
        fabs(seen0 - want0) > 1e-12 || fabs(seen1 - want1) > 1e-12) {
        fprintf(stderr, "input %s produced (%g,%g), expected (%g,%g)\n",
                data, seen0, seen1, want0, want1);
        return 22;
    }
    return 0;
}

int main(void) {
    system("rm -rf /tmp/sensor_probe && mkdir /tmp/sensor_probe");
    if (chdir("/tmp/sensor_probe") != 0) return 23;
    int r;
    if ((r = check_case("NaN,inf\n", 0.0, 0.0))) return r;
    if ((r = check_case("nan,2.5\n", 0.0, 2.5))) return r;
    if ((r = check_case("-3,-inf\n", -3.0, 0.0))) return r;
    return 0;
}
'''
    output = "/tmp/check_sanitization"
    compile_c(harness, output)
    run = subprocess.run([output], stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                         text=True, timeout=30)
    assert run.returncode == 0, f"Invalid sensor-value handling is incorrect:\n{run.stdout}"

    # Leave the requested result corresponding to the original sensor file.
    if os.path.exists(RESULT):
        os.remove(RESULT)
    final_run = subprocess.run([EXECUTABLE], cwd=PROJECT, stdout=subprocess.PIPE,
                               stderr=subprocess.STDOUT, text=True, timeout=30)
    assert final_run.returncode == 0 and os.path.isfile(RESULT), final_run.stdout
    final_cost = parse_cost(RESULT)
    assert math.isfinite(final_cost) and final_cost <= 0.01
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
