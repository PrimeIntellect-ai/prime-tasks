#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import io
import os
import sys
import random
import string
import subprocess
import pytest

VENDORED_ROOT = "/app/py_custom_csv-0.1"
AGENT_SCRIPT = "/home/user/log_analyzer.py"
ORACLE_SCRIPT = "/tests/log_analyzer_oracle.py"


def generate_random_csv(seed):
    random.seed(seed)
    num_rows = random.randint(10, 100)
    server_ids = ['srv1', 'srv2', 'srv3']

    lines = []

    # 50% chance to have a header
    if random.choice([True, False]):
        lines.append("timestamp,server_id,message")

    for _ in range(num_rows):
        num_cols = random.randint(1, 5)
        row = []
        for c in range(num_cols):
            if c == 1 and num_cols == 3:
                # 80% chance to use a valid server id
                if random.random() < 0.8:
                    row.append(random.choice(server_ids))
                else:
                    row.append("".join(random.choices(string.ascii_letters, k=4)))
            else:
                # Random text with spaces, newlines, quotes
                length = random.randint(0, 50)
                chars = string.ascii_letters + string.digits + " \n\t"
                text = "".join(random.choices(chars, k=length))

                # Format as CSV field (quote if contains comma, newline, quote)
                if any(x in text for x in [',', '\n', '"']):
                    text = '"' + text.replace('"', '""') + '"'
                row.append(text)
        lines.append(",".join(row))

    return "\n".join(lines)


def test_vendored_parser_handles_rfc4180_records():
    parser_path = os.path.join(VENDORED_ROOT, "py_custom_csv", "parser.py")
    assert os.path.isfile(parser_path), f"Vendored parser {parser_path} is missing."

    sys.path.insert(0, VENDORED_ROOT)
    try:
        import py_custom_csv
        assert os.path.realpath(py_custom_csv.__file__).startswith(os.path.realpath(VENDORED_ROOT) + os.sep)

        data = (
            'timestamp,server_id,message\r\n'
            '1,srv1,"first line\nsecond line"\r\n'
            '2,srv2,"comma, and ""quoted"" text"\r\n'
            '3,srv3,"tab\tand newline\r\ninside"\r\n'
        )
        assert list(py_custom_csv.parse(io.StringIO(data))) == [
            ['timestamp', 'server_id', 'message'],
            ['1', 'srv1', 'first line\nsecond line'],
            ['2', 'srv2', 'comma, and "quoted" text'],
            ['3', 'srv3', 'tab\tand newline\r\ninside'],
        ]
    finally:
        sys.path.pop(0)


def test_analyzer_calls_py_custom_csv_parse(tmp_path):
    assert os.path.isfile(AGENT_SCRIPT), f"Agent script {AGENT_SCRIPT} is missing."

    shim_root = tmp_path / "shim"
    package_dir = shim_root / "py_custom_csv"
    package_dir.mkdir(parents=True)
    marker = tmp_path / "parse-called"
    (package_dir / "__init__.py").write_text(
        "import csv\n"
        "import os\n"
        "def parse(stream):\n"
        "    with open(os.environ['PARSE_MARKER'], 'a') as f:\n"
        "        f.write('1')\n"
        "    yield from csv.reader(stream)\n"
    )

    csv_data = 'timestamp,server_id,message\n1,srv1,"hello\nworld"\n2,srv1,"hello world again"\n'
    env = os.environ.copy()
    env["PARSE_MARKER"] = str(marker)
    env["PYTHONPATH"] = str(shim_root) + os.pathsep + VENDORED_ROOT

    oracle_proc = subprocess.run(
        [sys.executable, ORACLE_SCRIPT], input=csv_data, text=True,
        capture_output=True, env=env
    )
    agent_proc = subprocess.run(
        [sys.executable, AGENT_SCRIPT], input=csv_data, text=True,
        capture_output=True, env=env
    )

    assert agent_proc.returncode == 0, agent_proc.stderr
    assert agent_proc.stdout == oracle_proc.stdout
    assert marker.is_file() and marker.read_text(), (
        "The analyzer did not call py_custom_csv.parse()."
    )


def test_fuzz_equivalence():
    assert os.path.isfile(AGENT_SCRIPT), f"Agent script {AGENT_SCRIPT} is missing."
    assert os.path.isfile(ORACLE_SCRIPT), f"Oracle script {ORACLE_SCRIPT} is missing."

    env = os.environ.copy()
    env["PYTHONPATH"] = VENDORED_ROOT + os.pathsep + env.get("PYTHONPATH", "")

    for i in range(200):
        csv_data = generate_random_csv(i)

        # Run oracle supplied only with the verifier tests.
        oracle_proc = subprocess.run(
            [sys.executable, ORACLE_SCRIPT],
            input=csv_data,
            text=True,
            capture_output=True,
            env=env
        )
        assert oracle_proc.returncode == 0, oracle_proc.stderr

        # Run agent.
        agent_proc = subprocess.run(
            [sys.executable, AGENT_SCRIPT],
            input=csv_data,
            text=True,
            capture_output=True,
            env=env
        )

        if agent_proc.returncode != 0:
            pytest.fail(f"Agent script failed with return code {agent_proc.returncode} on input seed {i}.\nStderr: {agent_proc.stderr}")

        if oracle_proc.stdout != agent_proc.stdout:
            pytest.fail(f"Output mismatch on input seed {i}.\n\nInput CSV:\n{csv_data}\n\nOracle stdout:\n{oracle_proc.stdout}\n\nAgent stdout:\n{agent_proc.stdout}")
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
