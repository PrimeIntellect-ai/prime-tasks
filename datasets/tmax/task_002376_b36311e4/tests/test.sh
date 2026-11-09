#!/bin/bash
set -u
mkdir -p /logs/verifier

TMPDIR_REPAIR=$(mktemp -d)
VENV_MOVED=0
ASSETS_BACKED_UP=0

cleanup() {
    if [ "$ASSETS_BACKED_UP" -eq 1 ]; then
        cp -a "$TMPDIR_REPAIR/run_sim.sh" /home/user/sim_env/run_sim.sh
        cp -a "$TMPDIR_REPAIR/find_peak.py" /home/user/sim_env/find_peak.py
    fi
    if [ "$VENV_MOVED" -eq 1 ]; then
        rm -rf /home/user/venv
        mv "$TMPDIR_REPAIR/original_venv" /home/user/venv
        VENV_MOVED=0
    fi
    rm -rf "$TMPDIR_REPAIR"
}
trap cleanup EXIT

main() {
    # Preserve the original verifier's assertions before modifying test inputs.
    python3 - <<'PY' || return 1
import os

script = "/home/user/validate_stability.sh"
assert os.path.isfile(script), f"File {script} is missing."
assert os.access(script, os.X_OK), f"File {script} is not executable."

venv = "/home/user/venv"
assert os.path.isdir(venv), f"Virtual environment directory {venv} is missing."
assert os.path.isfile(os.path.join(venv, "bin", "python")), "Python interpreter missing in venv."

output = "/home/user/sim_env/output.csv"
assert os.path.isfile(output), f"Simulation output file {output} is missing."

report = "/home/user/stability_report.txt"
assert os.path.isfile(report), f"Report file {report} is missing."
with open(report) as f:
    content = f.read().strip()
expected = "Average Frequency: 2.530 Hz"
assert content == expected, f"Content of {report} is incorrect. Expected '{expected}', got '{content}'."
PY

    # A dummy file at bin/python is not a valid virtual environment interpreter.
    /home/user/venv/bin/python - <<'PY' || return 1
import os, sys, numpy
assert os.path.abspath(sys.prefix) == "/home/user/venv"
PY

    cp -a /home/user/sim_env/run_sim.sh "$TMPDIR_REPAIR/run_sim.sh" || return 1
    cp -a /home/user/sim_env/find_peak.py "$TMPDIR_REPAIR/find_peak.py" || return 1
    ASSETS_BACKED_UP=1

    mv /home/user/venv "$TMPDIR_REPAIR/original_venv" || return 1
    VENV_MOVED=1

    : > /tmp/stability_run_calls
    : > /tmp/stability_peak_calls
    chmod 666 /tmp/stability_run_calls /tmp/stability_peak_calls

    # Install randomized probe tools. Their expected average is derived by the
    # verifier, so a script that merely writes the old fixed answer cannot pass.
    python3 - <<'PY' || return 1
import secrets

vals = [secrets.randbelow(2601) + 1700 for _ in range(5)]
vals[-1] += (-sum(vals)) % 5
expected_milli = sum(vals) // 5

run_sim = '''#!/bin/bash
set -e
[ "$#" -eq 1 ]
case "$1" in 1|2|3|4|5) ;; *) exit 41 ;; esac
printf '%s\\n' "$1" >> /tmp/stability_run_calls
printf 'seed,%s\\n' "$1" > /home/user/sim_env/output.csv
'''

find_peak = f'''import csv
import sys
import numpy as np

with open("/home/user/sim_env/output.csv", newline="") as f:
    rows = list(csv.reader(f))
if len(rows) != 1 or rows[0][0] != "seed":
    raise SystemExit(42)
seed = int(rows[0][1])
values = {vals!r}
with open("/tmp/stability_peak_calls", "a") as log:
    log.write(f"{{sys.executable}}|{{seed}}\\n")
# Exercise numpy in the newly created virtual environment as the real tool does.
_ = np.asarray(values, dtype=float).mean()
print(f"{{values[seed-1] / 1000:.3f}}")
'''

with open("/home/user/sim_env/run_sim.sh", "w") as f:
    f.write(run_sim)
with open("/home/user/sim_env/find_peak.py", "w") as f:
    f.write(find_peak)
with open("/tmp/stability_expected_report", "w") as f:
    f.write(f"Average Frequency: {expected_milli / 1000:.3f} Hz")
PY
    chmod 755 /home/user/sim_env/run_sim.sh
    chmod 644 /home/user/sim_env/find_peak.py
    rm -f /home/user/stability_report.txt /home/user/sim_env/output.csv

    timeout 300s runuser -u user -- env HOME=/home/user bash -c \
        'cd /home/user/sim_env && /home/user/validate_stability.sh' || return 1

    python3 - <<'PY' || return 1
import os

with open('/tmp/stability_run_calls') as f:
    run_calls = [line.strip() for line in f if line.strip()]
assert run_calls == ['1', '2', '3', '4', '5'], f"wrong simulation calls: {run_calls!r}"

with open('/tmp/stability_peak_calls') as f:
    peak_calls = [line.strip().split('|', 1) for line in f if line.strip()]
assert [seed for _, seed in peak_calls] == ['1', '2', '3', '4', '5'], \
    f"analysis was not run after every seed: {peak_calls!r}"
for exe, _ in peak_calls:
    assert exe.startswith('/home/user/venv/bin/python'), \
        f"find_peak.py used non-venv interpreter {exe!r}"

assert os.path.isfile('/home/user/sim_env/output.csv')
with open('/tmp/stability_expected_report') as f:
    expected = f.read()
with open('/home/user/stability_report.txt') as f:
    actual = f.read().strip()
assert actual == expected, f"expected randomized report {expected!r}, got {actual!r}"
PY

    test -x /home/user/venv/bin/python || return 1
    /home/user/venv/bin/python - <<'PY' || return 1
import os, sys, numpy
assert os.path.abspath(sys.prefix) == "/home/user/venv"
PY

    # Restore the supplied tools and original environment, then execute the
    # submitted pipeline once more and retain all original final-state checks.
    cp -a "$TMPDIR_REPAIR/run_sim.sh" /home/user/sim_env/run_sim.sh || return 1
    cp -a "$TMPDIR_REPAIR/find_peak.py" /home/user/sim_env/find_peak.py || return 1
    rm -rf /home/user/venv
    mv "$TMPDIR_REPAIR/original_venv" /home/user/venv || return 1
    VENV_MOVED=0

    timeout 300s runuser -u user -- env HOME=/home/user bash -c \
        'cd /home/user/sim_env && /home/user/validate_stability.sh' || return 1

    cat <<'TEST_EOF' > /tmp/test_final_state.py
import os

def test_validate_stability_script_exists_and_executable():
    file_path = "/home/user/validate_stability.sh"
    assert os.path.isfile(file_path), f"File {file_path} is missing."
    assert os.access(file_path, os.X_OK), f"File {file_path} is not executable."

def test_venv_directory_exists():
    dir_path = "/home/user/venv"
    assert os.path.isdir(dir_path), f"Virtual environment directory {dir_path} is missing."
    assert os.path.isfile(os.path.join(dir_path, "bin", "python")), "Python interpreter missing in venv."

def test_output_csv_exists():
    file_path = "/home/user/sim_env/output.csv"
    assert os.path.isfile(file_path), f"Simulation output file {file_path} is missing."

def test_stability_report_content():
    file_path = "/home/user/stability_report.txt"
    assert os.path.isfile(file_path), f"Report file {file_path} is missing."
    with open(file_path, 'r') as f:
        content = f.read().strip()
    expected_content = "Average Frequency: 2.530 Hz"
    assert content == expected_content, f"Content of {file_path} is incorrect. Expected '{expected_content}', got '{content}'."
TEST_EOF

    python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1 || return 1
}

if main; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
