#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import math
import os
import random
import re
import secrets
import stat
import subprocess

import pytest

SCRIPT_PATH = "/home/user/analyze_sensors.sh"
DATA_PATH = "/home/user/data/sensor_readings.csv"
REPORT_PATH = "/home/user/analysis_report.txt"

BASELINE = """machine_id,machine_type,sensor1,sensor2,sensor3,sensor4
0,A,0.496714,0.993428,0.248357,-0.138264
1,A,-0.138264,-0.276528,-0.069132,0.647689
2,A,0.647689,1.295378,0.323845,1.523030
3,A,1.523030,3.046060,0.761515,-0.234153
4,A,-0.234153,-0.468306,-0.117077,-0.234137
5,A,-0.234137,-0.468274,-0.117069,1.579213
6,A,1.579213,3.158426,0.789607,0.767435
7,A,0.767435,1.534870,0.383718,-0.469474
8,A,-0.469474,-0.938948,-0.234737,0.542560
9,A,0.542560,1.085120,0.271280,-0.463418
10,A,NaN,NaN,NaN,NaN
11,A,-0.463418,-0.926836,-0.231709,-0.465730
12,B,2.465730,4.931460,1.232865,0.241962
13,B,1.241962,2.483924,0.620981,-1.913280
14,B,-0.913280,-1.826560,-0.456640,-1.724918
15,B,-0.724918,-1.449836,-0.362459,-0.562288
16,B,0.437712,0.875424,0.218856,-1.012831
17,B,-0.012831,-0.025662,-0.006416,0.314247
18,B,1.314247,2.628494,0.657124,-0.908024
19,B,0.091976,0.183952,0.045988,-1.412304
20,B,NaN,NaN,NaN,NaN
21,B,1.465662,2.931324,0.732831,-0.225776
22,B,1.767435,3.534870,0.883718,0.067528
23,B,1.067528,2.135056,0.533764,-1.424748
"""

REPORT_RE = re.compile(
    r"\APC1_Variance_Ratio: ([0-9]+\.[0-9]{4})\n"
    r"T-Test_P-Value: ([0-9]+\.[0-9]{4})\n?\Z"
)


def write_dataset(text):
    os.makedirs(os.path.dirname(DATA_PATH), exist_ok=True)
    with open(DATA_PATH, "w", newline="") as f:
        f.write(text)


def run_script():
    if os.path.exists(REPORT_PATH):
        os.remove(REPORT_PATH)
    result = subprocess.run(
        [SCRIPT_PATH], capture_output=True, text=True, timeout=240
    )
    assert result.returncode == 0, (
        f"Script failed to execute. stdout: {result.stdout}\nstderr: {result.stderr}"
    )
    assert os.path.isfile(REPORT_PATH), f"Report {REPORT_PATH} was not created by the script."
    with open(REPORT_PATH, "r") as f:
        content = f.read()
    match = REPORT_RE.fullmatch(content)
    assert match is not None, (
        "Report must contain exactly the two required lines, with exactly four "
        f"decimal places. Content was:\n{content!r}"
    )
    return content, match.group(1), match.group(2)


def jacobi_largest_eigenpair(matrix):
    a = [row[:] for row in matrix]
    n = len(a)
    vectors = [[1.0 if i == j else 0.0 for j in range(n)] for i in range(n)]
    for _ in range(100):
        p, q = max(
            ((i, j) for i in range(n) for j in range(i + 1, n)),
            key=lambda pair: abs(a[pair[0]][pair[1]]),
        )
        if abs(a[p][q]) < 1e-14:
            break
        tau = (a[q][q] - a[p][p]) / (2.0 * a[p][q])
        t = (1.0 if tau >= 0 else -1.0) / (abs(tau) + math.sqrt(1.0 + tau * tau))
        c = 1.0 / math.sqrt(1.0 + t * t)
        s = t * c
        apq = a[p][q]
        app = a[p][p]
        aqq = a[q][q]
        for k in range(n):
            if k != p and k != q:
                akp, akq = a[k][p], a[k][q]
                a[k][p] = a[p][k] = c * akp - s * akq
                a[k][q] = a[q][k] = s * akp + c * akq
        a[p][p] = app - t * apq
        a[q][q] = aqq + t * apq
        a[p][q] = a[q][p] = 0.0
        for k in range(n):
            vkp, vkq = vectors[k][p], vectors[k][q]
            vectors[k][p] = c * vkp - s * vkq
            vectors[k][q] = s * vkp + c * vkq
    index = max(range(n), key=lambda i: a[i][i])
    return a[index][index], [vectors[i][index] for i in range(n)]


def beta_continued_fraction(a, b, x):
    max_iter = 300
    eps = 3e-14
    tiny = 1e-300
    qab = a + b
    qap = a + 1.0
    qam = a - 1.0
    c = 1.0
    d = 1.0 - qab * x / qap
    if abs(d) < tiny:
        d = tiny
    d = 1.0 / d
    h = d
    for m in range(1, max_iter + 1):
        m2 = 2 * m
        aa = m * (b - m) * x / ((qam + m2) * (a + m2))
        d = 1.0 + aa * d
        if abs(d) < tiny:
            d = tiny
        c = 1.0 + aa / c
        if abs(c) < tiny:
            c = tiny
        d = 1.0 / d
        h *= d * c
        aa = -(a + m) * (qab + m) * x / ((a + m2) * (qap + m2))
        d = 1.0 + aa * d
        if abs(d) < tiny:
            d = tiny
        c = 1.0 + aa / c
        if abs(c) < tiny:
            c = tiny
        d = 1.0 / d
        delta = d * c
        h *= delta
        if abs(delta - 1.0) < eps:
            break
    return h


def regularized_beta(x, a, b):
    if x <= 0.0:
        return 0.0
    if x >= 1.0:
        return 1.0
    front = math.exp(
        math.lgamma(a + b) - math.lgamma(a) - math.lgamma(b)
        + a * math.log(x) + b * math.log1p(-x)
    )
    if x < (a + 1.0) / (a + b + 2.0):
        return front * beta_continued_fraction(a, b, x) / a
    return 1.0 - front * beta_continued_fraction(b, a, 1.0 - x) / b


def expected_metrics(rows):
    values = [row[1] for row in rows]
    means = [sum(row[j] for row in values) / len(values) for j in range(4)]
    centered = [[row[j] - means[j] for j in range(4)] for row in values]
    scatter = [[sum(row[i] * row[j] for row in centered) for j in range(4)] for i in range(4)]
    largest, direction = jacobi_largest_eigenpair(scatter)
    ratio = largest / sum(scatter[i][i] for i in range(4))
    scores = [sum(row[j] * direction[j] for j in range(4)) for row in centered]
    group_a = [scores[i] for i, row in enumerate(rows) if row[0] == "A"]
    group_b = [scores[i] for i, row in enumerate(rows) if row[0] == "B"]

    def sample_stats(group):
        mean = sum(group) / len(group)
        variance = sum((x - mean) ** 2 for x in group) / (len(group) - 1)
        return mean, variance

    mean_a, var_a = sample_stats(group_a)
    mean_b, var_b = sample_stats(group_b)
    term_a = var_a / len(group_a)
    term_b = var_b / len(group_b)
    t_value = (mean_a - mean_b) / math.sqrt(term_a + term_b)
    degrees = (term_a + term_b) ** 2 / (
        term_a ** 2 / (len(group_a) - 1) + term_b ** 2 / (len(group_b) - 1)
    )
    x = degrees / (degrees + t_value * t_value)
    p_value = regularized_beta(x, degrees / 2.0, 0.5)
    return f"{ratio:.4f}", f"{p_value:.4f}"


def make_random_dataset():
    rng = random.Random(secrets.randbits(128))
    rows = []
    csv_rows = [["machine_id", "machine_type", "sensor1", "sensor2", "sensor3", "sensor4"]]
    machine_id = 0
    shift = rng.uniform(-1.25, 1.25)
    coefficients = [
        rng.uniform(0.75, 1.35),
        rng.uniform(1.4, 2.3),
        rng.uniform(-1.1, -0.35),
        rng.uniform(0.15, 0.8),
    ]
    for machine_type in ("A", "B"):
        for _ in range(14):
            latent = rng.gauss(0.0, 1.0) + (shift if machine_type == "B" else 0.0)
            vals = [
                coefficients[0] * latent + rng.gauss(0, 0.22),
                coefficients[1] * latent + rng.gauss(0, 0.28),
                coefficients[2] * latent + rng.gauss(0, 0.20),
                coefficients[3] * latent + rng.gauss(0, 0.75),
            ]
            vals = [float(f"{v:.9f}") for v in vals]
            rows.append((machine_type, vals))
            csv_rows.append([machine_id, machine_type] + [f"{v:.9f}" for v in vals])
            machine_id += 1

    # These extreme rows must be removed because each has a missing value in a column.
    csv_rows.append(["", "A", "9000", "-8000", "7000", "-6000"])
    csv_rows.append([machine_id, "B", "NaN", "5000", "4000", "3000"])
    csv_rows.append([machine_id + 1, "", "-7000", "6000", "-5000", "4000"])

    output = []
    for row in csv_rows:
        output.append(",".join(str(item) for item in row))
    return "\n".join(output) + "\n", rows


def test_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    st = os.stat(SCRIPT_PATH)
    assert bool(st.st_mode & stat.S_IXUSR), f"Script {SCRIPT_PATH} is not executable."


def test_script_execution_and_output():
    write_dataset(BASELINE)
    content, pca_text, ttest_text = run_script()

    # Retain the original baseline assertions.
    match_pca = re.search(r"PC1_Variance_Ratio:\s*([0-9.]+)", content)
    match_ttest = re.search(r"T-Test_P-Value:\s*([0-9.]+)", content)
    assert match_pca is not None, f"PC1_Variance_Ratio not found in report. Content was:\n{content}"
    assert match_ttest is not None, f"T-Test_P-Value not found in report. Content was:\n{content}"
    pca_val = float(match_pca.group(1))
    ttest_val = float(match_ttest.group(1))
    assert abs(pca_val - 0.9351) <= 0.0015, f"PC1_Variance_Ratio expected ~0.9351, got {pca_val}"
    assert abs(ttest_val - 0.1160) <= 0.0015, f"T-Test_P-Value expected ~0.1160, got {ttest_val}"

    # Exercise the submitted script on fresh, unpredictable datasets. Expected
    # answers are independently derived rather than taken from fixed constants.
    for _ in range(2):
        dataset, valid_rows = make_random_dataset()
        expected_pca, expected_p = expected_metrics(valid_rows)
        write_dataset(dataset)
        _, actual_pca, actual_p = run_script()
        assert actual_pca == expected_pca, (
            f"PC1 variance ratio expected {expected_pca}, got {actual_pca}"
        )
        assert actual_p == expected_p, (
            f"Welch t-test p-value expected {expected_p}, got {actual_p}"
        )

    write_dataset(BASELINE)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
