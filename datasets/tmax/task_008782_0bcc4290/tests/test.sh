#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import math
import os
import re
import subprocess
import time

C_FILE = '/home/user/analyze.c'
BIN_FILE = '/home/user/analyze'
CSV_FILE = '/home/user/sensor_data.csv'
RESULT_FILE = '/home/user/result.txt'


def parse_result():
    assert os.path.isfile(RESULT_FILE), f"Result file {RESULT_FILE} is missing."
    with open(RESULT_FILE, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]
    assert len(lines) == 2, f"Expected exactly 2 lines in {RESULT_FILE}, found {len(lines)}"
    time_match = re.match(r"^Time: [0-9.]+ ms$", lines[1])
    assert time_match is not None, f"Expected second line to match 'Time: <Y> ms', got '{lines[1]}'"
    return lines, float(lines[1][len('Time: '):-len(' ms')])


def expected_probability(rows):
    total = len(rows)
    count_f1 = sum(1 for s1, s2, s3, fault in rows if fault == 1)
    count_f0 = total - count_f1

    s1_1_f1 = sum(1 for s1, s2, s3, fault in rows if fault == 1 and s1 == 1)
    s2_0_f1 = sum(1 for s1, s2, s3, fault in rows if fault == 1 and s2 == 0)
    s3_1_f1 = sum(1 for s1, s2, s3, fault in rows if fault == 1 and s3 == 1)
    s1_1_f0 = sum(1 for s1, s2, s3, fault in rows if fault == 0 and s1 == 1)
    s2_0_f0 = sum(1 for s1, s2, s3, fault in rows if fault == 0 and s2 == 0)
    s3_1_f0 = sum(1 for s1, s2, s3, fault in rows if fault == 0 and s3 == 1)

    p_f1 = count_f1 / total
    p_f0 = count_f0 / total
    u1 = p_f1 * ((s1_1_f1 + 1) / (count_f1 + 2)) * ((s2_0_f1 + 1) / (count_f1 + 2)) * ((s3_1_f1 + 1) / (count_f1 + 2))
    u0 = p_f0 * ((s1_1_f0 + 1) / (count_f0 + 2)) * ((s2_0_f0 + 1) / (count_f0 + 2)) * ((s3_1_f0 + 1) / (count_f0 + 2))
    return u1 / (u1 + u0)


def write_dataset(rows):
    with open(CSV_FILE, 'w', newline='') as f:
        writer = csv.writer(f, lineterminator='\n')
        writer.writerow(['id', 's1', 's2', 's3', 'fault'])
        for i, row in enumerate(rows, 1):
            writer.writerow((i,) + row)


def run_program(env=None):
    if os.path.exists(RESULT_FILE):
        os.unlink(RESULT_FILE)
    subprocess.run([BIN_FILE], check=True, timeout=30, cwd='/home/user', env=env)
    return parse_result()


def test_analyze_c_exists_and_uses_time():
    assert os.path.isfile(C_FILE), f"C source file {C_FILE} is missing."
    with open(C_FILE, 'r') as f:
        content = f.read()
    assert '<time.h>' in content, "The C file does not include <time.h>."
    assert 'clock(' in content, "The C file does not use clock() for benchmarking."


def test_source_compiles_and_program_handles_derived_inputs():
    if os.path.lexists(BIN_FILE):
        os.unlink(BIN_FILE)
    subprocess.run(
        ['gcc', '-std=c11', '-O2', '-Wall', '-Wextra', C_FILE, '-o', BIN_FILE],
        check=True, timeout=30
    )
    assert os.path.isfile(BIN_FILE), f"Compiled program {BIN_FILE} is missing."
    assert os.access(BIN_FILE, os.X_OK), f"Compiled program {BIN_FILE} is not executable."

    shim_c = '/tmp/clock_shim.c'
    shim_so = '/tmp/clock_shim.so'
    with open(shim_c, 'w') as f:
        f.write('''#include <time.h>\nclock_t clock(void) { static int n = 0; return n++ == 0 ? (clock_t)100000 : (clock_t)350000; }\n''')
    subprocess.run(['gcc', '-shared', '-fPIC', shim_c, '-o', shim_so], check=True, timeout=30)
    env = os.environ.copy()
    env['LD_PRELOAD'] = shim_so

    with open(CSV_FILE, 'rb') as f:
        original_csv = f.read()

    pattern_a = [
        (1, 0, 1, 1), (1, 1, 1, 1), (0, 0, 1, 1),
        (1, 0, 1, 0), (0, 0, 0, 0), (0, 1, 0, 0), (1, 1, 0, 0)
    ]
    pattern_b = [
        (1, 0, 1, 1), (1, 0, 1, 1), (1, 0, 0, 1), (0, 1, 1, 1),
        (1, 0, 1, 0), (1, 0, 1, 0), (0, 1, 0, 0), (0, 1, 0, 0), (0, 0, 1, 0)
    ]
    datasets = [pattern_a * 503, pattern_b * 419]
    observed = []

    try:
        for rows in datasets:
            write_dataset(rows)
            lines, reported_ms = run_program(env)
            expected = f"Probability: {expected_probability(rows):.6f}"
            assert lines[0] == expected, f"Expected first line to be '{expected}', got '{lines[0]}'"
            assert math.isclose(reported_ms, 250.0, rel_tol=0, abs_tol=0.01), \
                f"Benchmark must be computed from clock(); expected 250 ms under the test clock, got {reported_ms} ms"
            observed.append(lines[0])
        assert observed[0] != observed[1], "Program output did not change for datasets with different posteriors."
    finally:
        with open(CSV_FILE, 'wb') as f:
            f.write(original_csv)
        if os.path.exists(RESULT_FILE):
            os.unlink(RESULT_FILE)
        subprocess.run([BIN_FILE], check=True, timeout=30, cwd='/home/user')


def test_result_txt_correctness():
    total = 0
    count_f1 = 0
    count_f0 = 0
    s1_1_f1 = 0
    s2_0_f1 = 0
    s3_1_f1 = 0
    s1_1_f0 = 0
    s2_0_f0 = 0
    s3_1_f0 = 0

    with open(CSV_FILE, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            total += 1
            fault = int(row['fault'])
            s1 = int(row['s1'])
            s2 = int(row['s2'])
            s3 = int(row['s3'])
            if fault == 1:
                count_f1 += 1
                if s1 == 1: s1_1_f1 += 1
                if s2 == 0: s2_0_f1 += 1
                if s3 == 1: s3_1_f1 += 1
            else:
                count_f0 += 1
                if s1 == 1: s1_1_f0 += 1
                if s2 == 0: s2_0_f0 += 1
                if s3 == 1: s3_1_f0 += 1

    p_f1 = count_f1 / total
    p_f0 = count_f0 / total
    l_s1_f1 = (s1_1_f1 + 1) / (count_f1 + 2)
    l_s2_f1 = (s2_0_f1 + 1) / (count_f1 + 2)
    l_s3_f1 = (s3_1_f1 + 1) / (count_f1 + 2)
    l_s1_f0 = (s1_1_f0 + 1) / (count_f0 + 2)
    l_s2_f0 = (s2_0_f0 + 1) / (count_f0 + 2)
    l_s3_f0 = (s3_1_f0 + 1) / (count_f0 + 2)
    unnorm_f1 = p_f1 * l_s1_f1 * l_s2_f1 * l_s3_f1
    unnorm_f0 = p_f0 * l_s1_f0 * l_s2_f0 * l_s3_f0
    posterior_f1 = unnorm_f1 / (unnorm_f1 + unnorm_f0)
    expected_prob_str = f"Probability: {posterior_f1:.6f}"

    lines, reported_ms = parse_result()
    assert lines[0] == expected_prob_str, f"Expected first line to be '{expected_prob_str}', got '{lines[0]}'"
    assert math.isfinite(reported_ms) and reported_ms > 0, \
        f"Expected a positive finite measured processing time, got {reported_ms}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
