#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import json
import secrets
import subprocess
import pytest
from io import StringIO
from datetime import datetime, timedelta


def test_setup_py_fixed():
    path = "/app/vendored/python-dateutil/setup.py"
    assert os.path.isfile(path), f"setup.py missing at {path}"

    with open(path, "r", encoding="utf-8") as f:
        content = f.read()

    assert "import non_existent_setuptools_module" not in content, "setup.py still contains the broken import"
    assert "from setuptools import setup" in content or "import setuptools" in content, "setup.py does not seem to import setuptools correctly"


def test_vendored_dateutil_installed_for_user():
    check = r'''
import os
import site
import dateutil

module_path = os.path.realpath(dateutil.__file__)
user_site = os.path.realpath(site.getusersitepackages())
vendor = os.path.realpath('/app/vendored/python-dateutil')
assert module_path.startswith(vendor + os.sep) or module_path.startswith(user_site + os.sep), (
    'python-dateutil is not installed from the vendored source into the user environment: ' + module_path
)
'''
    proc = subprocess.run(
        ["runuser", "-u", "user", "--", "env", "HOME=/home/user", "python3", "-c", check],
        text=True,
        capture_output=True,
    )
    assert proc.returncode == 0, f"Vendored python-dateutil is not installed for user: {proc.stderr}"


def test_agent_script_exists_and_executable():
    path = "/home/user/etl_processor.py"
    assert os.path.isfile(path), f"Agent script missing at {path}"
    assert os.access(path, os.X_OK), f"Agent script at {path} is not executable"

    with open(path, "r", encoding="utf-8") as f:
        first_line = f.readline().strip()
    assert first_line == "#!/usr/bin/env python3", f"Agent script must start with #!/usr/bin/env python3, got {first_line}"


def generate_fuzz_csv(num_rows):
    random = secrets.SystemRandom()
    output = StringIO()
    all_sensors = [f"sensor_{chr(65+i)}" for i in range(26)]
    num_cols = random.randint(3, 10)
    sensors = random.sample(all_sensors, num_cols)

    writer = csv.writer(output)
    writer.writerow(["raw_time"] + sensors)
    statuses = ["OK", "ERR", "WARN", "MAINT"]
    base_time = datetime(2023, 1, 1, 12, 0, 0)

    for _ in range(num_rows):
        delta = timedelta(
            days=random.randint(0, 300),
            hours=random.randint(0, 23),
            minutes=random.randint(0, 59),
            seconds=random.randint(0, 59),
            microseconds=random.randint(0, 999999),
        )
        row_time = base_time + delta
        time_str = row_time.strftime("%Y-%m-%dT%H:%M:%S.%fZ")

        row = [time_str]
        for _ in range(num_cols):
            val = round(random.uniform(-100.0, 100.0), 2)
            status = random.choice(statuses)
            row.append(f"[VAL: {val}] [STATUS: {status}]")
        writer.writerow(row)

    return output.getvalue()


def test_fuzz_equivalence():
    oracle_path = "/tests/oracle_processor.py"
    agent_path = "/home/user/etl_processor.py"

    assert os.path.isfile(oracle_path), f"Oracle missing at {oracle_path}"
    assert os.path.isfile(agent_path), f"Agent script missing at {agent_path}"

    csv_data = generate_fuzz_csv(2000)

    oracle_proc = subprocess.run(
        ["python3", oracle_path],
        input=csv_data,
        text=True,
        capture_output=True,
    )
    assert oracle_proc.returncode == 0, f"Oracle failed: {oracle_proc.stderr}"
    oracle_output = oracle_proc.stdout

    probe_dir = "/tmp/dateutil_probe"
    marker = "/tmp/dateutil_parse_used"
    os.makedirs(probe_dir, exist_ok=True)
    if os.path.exists(marker):
        os.unlink(marker)
    with open(os.path.join(probe_dir, "sitecustomize.py"), "w", encoding="utf-8") as f:
        f.write(r'''
import dateutil.parser
_original_parse = dateutil.parser.parse
def _tracked_parse(*args, **kwargs):
    with open('/tmp/dateutil_parse_used', 'a', encoding='utf-8') as marker_file:
        marker_file.write('1')
    return _original_parse(*args, **kwargs)
dateutil.parser.parse = _tracked_parse
''')
    os.chmod(probe_dir, 0o755)
    os.chmod(os.path.join(probe_dir, "sitecustomize.py"), 0o644)

    agent_proc = subprocess.run(
        [
            "runuser", "-u", "user", "--", "env",
            "HOME=/home/user",
            f"PYTHONPATH={probe_dir}",
            agent_path,
        ],
        input=csv_data,
        text=True,
        capture_output=True,
    )
    assert agent_proc.returncode == 0, f"Agent script failed: {agent_proc.stderr}"
    assert os.path.isfile(marker) and os.path.getsize(marker) > 0, "Agent did not use dateutil.parser.parse for timestamp parsing"
    agent_output = agent_proc.stdout

    oracle_lines = [line for line in oracle_output.splitlines() if line.strip()]
    agent_lines = [line for line in agent_output.splitlines() if line.strip()]

    assert len(oracle_lines) == len(agent_lines), f"Output line count mismatch. Oracle: {len(oracle_lines)}, Agent: {len(agent_lines)}"

    for i, (o_line, a_line) in enumerate(zip(oracle_lines, agent_lines)):
        try:
            o_json = json.loads(o_line)
        except json.JSONDecodeError:
            pytest.fail(f"Oracle produced invalid JSON on line {i+1}: {o_line}")

        try:
            a_json = json.loads(a_line)
        except json.JSONDecodeError:
            pytest.fail(f"Agent produced invalid JSON on line {i+1}: {a_line}")

        assert o_json == a_json, f"Mismatch on line {i+1}.\nOracle: {o_json}\nAgent:  {a_json}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
