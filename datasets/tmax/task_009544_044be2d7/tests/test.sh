#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/test_final_state.py
import glob
import math
import os
import re
import shutil
import subprocess
import tempfile

HOME = "/home/user"
DATA = os.path.join(HOME, "profiling_data")
REPORT = os.path.join(HOME, "report.txt")


def check_original_report():
    assert os.path.isfile(REPORT), f"Expected report file {REPORT} does not exist."
    with open(REPORT, "r") as f:
        content = f.read().strip()

    lines = [line.strip() for line in content.split("\n") if line.strip()]
    slope_line_found = False
    status_line_found = False

    for line in lines:
        if line.startswith("SLOPE:"):
            slope_line_found = True
            assert line == "SLOPE: 2.99", f"Expected SLOPE: 2.99, but got '{line}'"
        elif line.startswith("STATUS:"):
            status_line_found = True
            assert line == "STATUS: STABLE_CUBIC", f"Expected STATUS: STABLE_CUBIC, but got '{line}'"

    assert slope_line_found, "The 'SLOPE: <value>' line is missing from the report."
    assert status_line_found, "The 'STATUS: <status>' line is missing from the report."


def find_pipeline_candidates():
    candidates = []
    forbidden = re.compile(r"(?i)(^|[^A-Za-z0-9_])(python[0-9.]*|perl|rscript)([^A-Za-z0-9_]|$)")

    for root, dirs, files in os.walk(HOME):
        dirs[:] = [d for d in dirs if not d.startswith(".")]
        for name in files:
            path = os.path.join(root, name)
            if path == REPORT or re.fullmatch(r"run_N[0-9]+\.csv", name):
                continue
            try:
                if not os.path.isfile(path) or os.path.getsize(path) > 1024 * 1024:
                    continue
                raw = open(path, "rb").read()
                if b"\x00" in raw:
                    continue
                text = raw.decode("utf-8")
            except (OSError, UnicodeDecodeError):
                continue

            # A submitted pipeline must consume the named function and produce
            # the required report; this also excludes stock shell dotfiles.
            if "ComputeEigen" not in text or "report.txt" not in text:
                continue
            if forbidden.search(text) or re.search(r"(?m)^\s*(?:sudo\s+)?R(?:\s|$)", text):
                continue

            first = text.splitlines()[0] if text.splitlines() else ""
            is_awk = bool(re.search(r"awk", first)) or name.endswith(".awk")
            if not is_awk:
                syntax = subprocess.run(
                    ["bash", "-n", path], stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE, text=True
                )
                if syntax.returncode != 0:
                    continue
            candidates.append((path, is_awk))
    return candidates


def install_case(sizes, exponent, noise):
    os.makedirs(DATA, exist_ok=True)
    for old in glob.glob(os.path.join(DATA, "run_N*.csv")):
        os.remove(old)

    for i, n in enumerate(sizes):
        total = max(2, int(round(0.73 * (n ** exponent) * (1.0 + noise[i]))))
        part1 = total // 3
        part2 = total - part1
        with open(os.path.join(DATA, f"run_N{n}.csv"), "w") as f:
            f.write("Function,Caller,ExecutionTime_ms\n")
            f.write(f"Init,main,{7 + i}\n")
            f.write(f"ComputeEigen,SolveSystem,{part1}\n")
            f.write(f"OtherFunction,SolveSystem,{100 + i}\n")
            f.write(f"ComputeEigen,RefineMesh,{part2}\n")
            f.write(f"Cleanup,main,{3 + i}\n")


def expected_report_from_installed_csvs():
    points = []
    for path in glob.glob(os.path.join(DATA, "run_N*.csv")):
        match = re.fullmatch(r"run_N([0-9]+)\.csv", os.path.basename(path))
        assert match
        n_value = int(match.group(1))
        total = 0.0
        with open(path) as f:
            next(f)
            for line in f:
                fields = line.rstrip("\n").split(",")
                if len(fields) >= 3 and fields[0] == "ComputeEigen":
                    total += float(fields[2])
        assert total > 0
        points.append((math.log(n_value), math.log(total)))

    count = len(points)
    sx = sum(x for x, _ in points)
    sy = sum(y for _, y in points)
    sxy = sum(x * y for x, y in points)
    sx2 = sum(x * x for x, _ in points)
    slope = (count * sxy - sx * sy) / (count * sx2 - sx * sx)
    status = "STABLE_CUBIC" if 2.90 <= slope <= 3.10 else "UNSTABLE"
    return f"SLOPE: {slope:.2f}\nSTATUS: {status}"


def run_candidate(path, is_awk):
    cases = [
        ([11, 18, 31, 53, 89], 3.03, [0.02, -0.015, 0.01, -0.01, 0.015]),
        ([13, 22, 37, 61, 101], 2.43, [-0.02, 0.01, 0.015, -0.01, 0.02]),
        ([9, 16, 27, 46, 78], 3.48, [0.01, -0.02, 0.015, 0.0, -0.01]),
    ]

    forbidden_runtime = re.compile(r"(?i)(^|[^A-Za-z0-9_])(python[0-9.]*|perl|rscript)([^A-Za-z0-9_]|$)")
    for sizes, exponent, noise in cases:
        install_case(sizes, exponent, noise)
        expected = expected_report_from_installed_csvs()
        try:
            os.remove(REPORT)
        except FileNotFoundError:
            pass

        command = ["gawk", "-f", path] if is_awk else ["bash", "-x", path]
        try:
            result = subprocess.run(
                command, cwd=HOME, stdout=subprocess.PIPE,
                stderr=subprocess.PIPE, text=True, timeout=15,
                env={**os.environ, "HOME": HOME}
            )
        except (subprocess.TimeoutExpired, OSError):
            return False

        if result.returncode != 0:
            return False
        trace = result.stdout + "\n" + result.stderr
        if forbidden_runtime.search(trace) or re.search(r"(?m)^\s*\+?\s*(?:sudo\s+)?R(?:\s|$)", trace):
            return False
        if not os.path.isfile(REPORT):
            return False
        try:
            actual = open(REPORT).read().strip()
        except OSError:
            return False
        if actual != expected:
            return False
    return True


check_original_report()
original_report = open(REPORT, "rb").read()
backup_root = tempfile.mkdtemp(prefix="profiling_backup_")
backup_data = os.path.join(backup_root, "profiling_data")
shutil.copytree(DATA, backup_data)

try:
    candidates = find_pipeline_candidates()
    assert candidates, "No Bash/AWK analysis pipeline artifact was found."
    assert any(run_candidate(path, is_awk) for path, is_awk in candidates), (
        "No submitted Bash/AWK pipeline recomputed the correct report for changed profiling data."
    )
finally:
    shutil.rmtree(DATA, ignore_errors=True)
    shutil.copytree(backup_data, DATA)
    with open(REPORT, "wb") as f:
        f.write(original_report)
    shutil.rmtree(backup_root, ignore_errors=True)
PY_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
