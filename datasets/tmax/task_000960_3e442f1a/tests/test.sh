#!/bin/bash
set -e
mkdir -p /logs/verifier

backup_dir=$(mktemp -d)
cp -p /home/user/perf_logs.txt "$backup_dir/perf_logs.txt"
had_results=0
if [ -e /home/user/results.json ]; then
    cp -p /home/user/results.json "$backup_dir/results.json"
    had_results=1
fi
cleanup() {
    cp -p "$backup_dir/perf_logs.txt" /home/user/perf_logs.txt
    if [ "$had_results" -eq 1 ]; then
        cp -p "$backup_dir/results.json" /home/user/results.json
    else
        rm -f /home/user/results.json
    fi
    rm -rf "$backup_dir"
}
trap cleanup EXIT

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import pwd
import random
import re
import subprocess

SCRIPT = "/home/user/analyze_perf.sh"
LOG = "/home/user/perf_logs.txt"
RESULTS = "/home/user/results.json"


def test_script_exists_and_executable():
    assert os.path.isfile(SCRIPT), f"Script {SCRIPT} does not exist. You must create it."
    assert os.access(SCRIPT, os.X_OK), f"Script {SCRIPT} is not executable. Use 'chmod +x' to make it executable."

    with open(SCRIPT, "rb") as f:
        raw = f.read()
    assert b"\x00" not in raw, "analyze_perf.sh must be a shell script, not a binary artifact."
    try:
        source = raw.decode("utf-8")
    except UnicodeDecodeError:
        assert False, "analyze_perf.sh must be a text Bash script."
    first_line = source.splitlines()[0] if source.splitlines() else ""
    assert re.match(r"^#![^\n]*\bbash\b", first_line), "analyze_perf.sh must use Bash."

    forbidden = re.compile(
        r"(?:^|[;&|`(])\s*(?:(?:exec|command|env|sudo|nohup)\s+)*(?:[^\s;&|]*/)?"
        r"(?:python(?:[0-9.]*)?|perl|Rscript|gcc|g\+\+|clang|cc)\b",
        re.MULTILINE,
    )
    assert not forbidden.search(source), "Use Bash and standard shell tools only; Python, Perl, R, and C/C++ compilers are forbidden."


def expected_from_values(x_vals, y_vals):
    n = len(x_vals)
    assert n > 0
    sum_x = sum(x_vals)
    sum_y = sum(y_vals)
    sum_x2 = sum(x * x for x in x_vals)
    sum_xy = sum(x * y for x, y in zip(x_vals, y_vals))
    denominator = n * sum_x2 - sum_x * sum_x
    assert denominator != 0
    m = (n * sum_xy - sum_x * sum_y) / denominator
    b = (sum_y - m * sum_x) / n
    mean_y = sum_y / n
    model_mse = sum((y - (m * x + b)) ** 2 for x, y in zip(x_vals, y_vals)) / n
    null_mse = sum((y - mean_y) ** 2 for y in y_vals) / n
    return {
        "m": f"{m:.2f}",
        "b": f"{b:.2f}",
        "model_mse": f"{abs(model_mse):.2f}",
        "null_mse": f"{null_mse:.2f}",
    }


def assert_results(expected):
    assert os.path.isfile(RESULTS), f"Results file {RESULTS} does not exist. Did you run the script?"
    with open(RESULTS, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"File {RESULTS} does not contain valid JSON."

    for key in ("m", "b", "model_mse", "null_mse"):
        assert key in data, f"Key '{key}' missing in JSON output."
        assert str(data[key]) == expected[key], f"Expected {key}='{expected[key]}', got '{data[key]}'"


def test_results_json_exists_and_correct():
    assert os.path.isfile(RESULTS), f"Results file {RESULTS} does not exist. Did you run the script?"
    assert os.path.isfile(LOG), f"Log file {LOG} is missing."

    x_vals = []
    y_vals = []
    with open(LOG, "r") as f:
        for line in f:
            if "load:" in line and "latency:" in line:
                m_load = re.search(r"load:([\d.]+)", line)
                m_lat = re.search(r"latency:([\d.]+)", line)
                if m_load and m_lat:
                    x_vals.append(float(m_load.group(1)))
                    y_vals.append(float(m_lat.group(1)))

    assert len(x_vals) > 0, "No valid data points found in log file."
    assert_results(expected_from_values(x_vals, y_vals))


def run_as_user():
    account = pwd.getpwnam("user")

    def demote():
        os.setgroups([])
        os.setgid(account.pw_gid)
        os.setuid(account.pw_uid)

    completed = subprocess.run(
        [SCRIPT],
        cwd="/home/user",
        env={**os.environ, "HOME": "/home/user"},
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
        preexec_fn=demote,
    )
    assert completed.returncode == 0, (
        f"analyze_perf.sh exited with status {completed.returncode}.\n"
        f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
    )


def test_script_executes_and_recomputes_for_unseen_logs():
    rng = random.SystemRandom()
    for case_number in range(3):
        count = rng.randint(5, 9)
        x_vals = sorted(rng.sample(range(3, 180), count))
        y_vals = [rng.randint(8, 420) for _ in range(count)]

        lines = [
            f"[case {case_number}] INFO startup complete\n",
            f"[case {case_number}] DEBUG load:{rng.randint(1, 99)} req/s without latency\n",
            f"[case {case_number}] DEBUG latency:{rng.randint(1, 99)} ms without load\n",
        ]
        for i, (x, y) in enumerate(zip(x_vals, y_vals)):
            lines.append(
                f"[case {case_number}:{i}] DEBUG metrics - load:{x} req/s, "
                f"memory:{500 + i}MB, latency:{y} ms\n"
            )
            if i == 1:
                lines.append(f"[case {case_number}:{i}] WARN unrelated diagnostic\n")

        with open(LOG, "w") as f:
            f.writelines(lines)
        os.chmod(LOG, 0o666)
        if os.path.exists(RESULTS):
            os.unlink(RESULTS)

        run_as_user()
        assert_results(expected_from_values(x_vals, y_vals))
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
