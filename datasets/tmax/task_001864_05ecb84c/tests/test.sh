#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/test_final_state.py
import math
import os
import re
import subprocess
import textwrap
import pandas as pd
import numpy as np

ROOT = "/app/fastcsv-1.0"
SOURCE = "/home/user/bootstrap.c"
RESULTS = "/home/user/bootstrap_results.txt"
CSV = "/home/user/data/sales.csv"
TRACE = "/tmp/bootstrap_trace.txt"
BINARY = "/tmp/bootstrap_verified"


def test_fastcsv_max_columns_fixed():
    header_path = os.path.join(ROOT, "fastcsv.h")
    assert os.path.isfile(header_path), f"fastcsv.h not found at {header_path}"

    with open(header_path, "r") as f:
        content = f.read()

    match = re.search(r"#define\s+MAX_COLUMNS\s+(\d+)", content)
    assert match is not None, "Could not find #define MAX_COLUMNS in fastcsv.h"

    max_cols = int(match.group(1))
    assert max_cols >= 5, f"MAX_COLUMNS is {max_cols}, expected at least 5 to parse the dataset"


def test_library_was_built_and_parses_five_columns():
    archive = os.path.join(ROOT, "libfastcsv.a")
    obj = os.path.join(ROOT, "fastcsv.o")
    header = os.path.join(ROOT, "fastcsv.h")
    implementation = os.path.join(ROOT, "fastcsv.c")

    assert os.path.isfile(archive), "libfastcsv.a was not built"
    assert os.path.isfile(obj), "fastcsv.o was not built"
    newest_source = max(os.path.getmtime(header), os.path.getmtime(implementation))
    assert os.path.getmtime(obj) >= newest_source, "fastcsv.o is older than the modified library source"
    assert os.path.getmtime(archive) >= os.path.getmtime(obj), "libfastcsv.a is older than fastcsv.o"

    subprocess.run(["make", "clean"], cwd=ROOT, check=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    subprocess.run(["make"], cwd=ROOT, check=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)

    probe = r'''
#include <stdio.h>
#include "fastcsv.h"
int main(void) {
    char line[] = "1,2023-01-01,1234,19.75,A\n";
    CSVRow row;
    if (parse_csv_line(line, &row) != 5 || row.column_count != 5) return 1;
    if (!row.columns[3] || !row.columns[4]) return 2;
    printf("%s|%s\n", row.columns[3], row.columns[4]);
    return 0;
}
'''
    with open("/tmp/fastcsv_probe.c", "w") as f:
        f.write(probe)
    subprocess.run(
        ["gcc", "-I" + ROOT, "/tmp/fastcsv_probe.c", archive, "-o", "/tmp/fastcsv_probe"],
        check=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
    )
    run = subprocess.run(["/tmp/fastcsv_probe"], check=True, capture_output=True, text=True)
    assert run.stdout.strip() == "19.75|A", "rebuilt fastcsv library did not parse all five columns"


def test_bootstrap_program_executes_required_work():
    assert os.path.isfile(SOURCE), f"C source not found at {SOURCE}"
    assert os.path.isfile(CSV), f"Data file missing at {CSV}"

    wrapper = r'''
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include "fastcsv.h"

void __real_srand(unsigned int seed);
int __real_rand(void);
int __real_parse_csv_line(char *line, CSVRow *row);

static unsigned long long rand_calls = 0;
static unsigned long long parse_calls = 0;
static unsigned long long seed_calls = 0;
static unsigned int last_seed = 0;
static double *amounts = NULL;
static size_t amount_count = 0;
static double sample_sum = 0.0;
static size_t sample_draws = 0;
static unsigned long long completed_resamples = 0;
static double mean_of_means = 0.0;
static double m2_of_means = 0.0;

static void load_amounts(void) __attribute__((constructor));
static void load_amounts(void) {
    FILE *f = fopen("/home/user/data/sales.csv", "r");
    if (!f) return;
    size_t cap = 65536;
    amounts = malloc(cap * sizeof(double));
    if (!amounts) { fclose(f); return; }
    char line[4096];
    if (!fgets(line, sizeof(line), f)) { fclose(f); return; }
    while (fgets(line, sizeof(line), f)) {
        char *p = line;
        for (int i = 0; i < 3; i++) {
            p = strchr(p, ',');
            if (!p) break;
            p++;
        }
        if (!p) continue;
        if (amount_count == cap) {
            cap *= 2;
            double *next = realloc(amounts, cap * sizeof(double));
            if (!next) break;
            amounts = next;
        }
        amounts[amount_count++] = strtod(p, NULL);
    }
    fclose(f);
}

void __wrap_srand(unsigned int seed) {
    seed_calls++;
    last_seed = seed;
    __real_srand(seed);
}

int __wrap_rand(void) {
    int value = __real_rand();
    rand_calls++;
    if (amount_count > 0 && completed_resamples < 10000) {
        sample_sum += amounts[((unsigned int)value) % amount_count];
        sample_draws++;
        if (sample_draws == amount_count) {
            double m = sample_sum / (double)amount_count;
            completed_resamples++;
            double delta = m - mean_of_means;
            mean_of_means += delta / (double)completed_resamples;
            m2_of_means += delta * (m - mean_of_means);
            sample_sum = 0.0;
            sample_draws = 0;
        }
    }
    return value;
}

int __wrap_parse_csv_line(char *line, CSVRow *row) {
    parse_calls++;
    return __real_parse_csv_line(line, row);
}

static void write_trace(void) __attribute__((destructor));
static void write_trace(void) {
    FILE *f = fopen("/tmp/bootstrap_trace.txt", "w");
    if (!f) return;
    double expected_se = NAN;
    if (completed_resamples > 1)
        expected_se = sqrt(m2_of_means / (double)(completed_resamples - 1));
    fprintf(f, "seed_calls=%llu\n", seed_calls);
    fprintf(f, "seed=%u\n", last_seed);
    fprintf(f, "rand_calls=%llu\n", rand_calls);
    fprintf(f, "parse_calls=%llu\n", parse_calls);
    fprintf(f, "resamples=%llu\n", completed_resamples);
    fprintf(f, "expected_se=%.17g\n", expected_se);
    fclose(f);
    free(amounts);
}
'''
    # strchr is used by the wrapper.
    wrapper = wrapper.replace('#include <math.h>', '#include <math.h>\n#include <string.h>')
    with open("/tmp/bootstrap_wrapper.c", "w") as f:
        f.write(wrapper)

    archive = os.path.join(ROOT, "libfastcsv.a")
    compile_result = subprocess.run(
        ["gcc", "-O2", "-Wall", "-I" + ROOT, SOURCE, "/tmp/bootstrap_wrapper.c", archive,
         "-Wl,--wrap=rand", "-Wl,--wrap=srand", "-Wl,--wrap=parse_csv_line", "-lm", "-o", BINARY],
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
    )
    assert compile_result.returncode == 0, "bootstrap.c failed to compile against fastcsv:\n" + compile_result.stdout

    for path in (RESULTS, TRACE):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    run = subprocess.run([BINARY], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=300)
    assert run.returncode == 0, f"bootstrap program failed ({run.returncode}):\n{run.stderr}"
    assert os.path.isfile(TRACE), "instrumentation trace was not produced"
    assert os.path.isfile(RESULTS), f"Results file not found at {RESULTS}"

    trace = {}
    with open(TRACE) as f:
        for line in f:
            key, value = line.strip().split("=", 1)
            trace[key] = value

    row_count = sum(1 for _ in open(CSV)) - 1
    assert int(trace["seed_calls"]) == 1, "program must seed the C random generator once"
    assert int(trace["seed"]) == 42, "program did not call srand(42)"
    assert int(trace["parse_calls"]) >= row_count, "program did not use fastcsv to parse every data row"
    assert int(trace["rand_calls"]) == row_count * 10000, "program did not draw exactly one full bootstrap sample for each of 10,000 resamples"
    assert int(trace["resamples"]) == 10000, "program did not complete exactly 10,000 bootstrap resamples"

    with open(RESULTS, "r") as f:
        text = f.read()

    exact = re.fullmatch(
        r"Sample Mean:\s*([\d\.]+)\nStandard Error:\s*([\d\.]+)\n?", text
    )
    assert exact is not None, "Results file must contain exactly the two required lines. File content:\n" + text

    mean_match = re.search(r"Sample Mean:\s*([\d\.]+)", text)
    se_match = re.search(r"Standard Error:\s*([\d\.]+)", text)
    assert mean_match is not None, "Sample Mean not found in output. File content:\n" + text
    assert se_match is not None, "Standard Error not found in output. File content:\n" + text

    agent_mean = float(mean_match.group(1))
    agent_se = float(se_match.group(1))

    df = pd.read_csv(CSV)
    amounts = df['amount'].values
    expected_mean = np.mean(amounts)
    expected_se = np.std(amounts, ddof=1) / np.sqrt(len(amounts))

    mean_diff = abs(agent_mean - expected_mean)
    se_diff = abs(agent_se - expected_se)
    assert mean_diff <= 0.05, f"Mean difference {mean_diff} exceeds tolerance 0.05. Agent: {agent_mean}, Expected: {expected_mean}"
    assert se_diff <= 0.015, f"SE difference {se_diff} exceeds tolerance 0.015. Agent: {agent_se}, Expected: {expected_se}"

    seeded_bootstrap_se = float(trace["expected_se"])
    assert math.isfinite(seeded_bootstrap_se)
    assert abs(agent_se - seeded_bootstrap_se) <= 0.0001, (
        f"reported SE {agent_se} does not match the 10,000-resample srand(42) bootstrap value "
        f"{seeded_bootstrap_se}"
    )
PY_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
