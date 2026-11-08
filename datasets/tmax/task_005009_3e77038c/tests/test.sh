#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import random
import shutil
import subprocess
import pytest

AGENT_SCRIPT = "/home/user/process_configs.sh"
PARSER_SCRIPT = "/app/bash-json-parser/parse.sh"
ORACLE_SCRIPT = "/tests/process_configs_oracle.sh"


def test_agent_script_exists_and_executable():
    assert os.path.isfile(AGENT_SCRIPT), f"Agent script {AGENT_SCRIPT} does not exist."
    st = os.stat(AGENT_SCRIPT)
    assert st.st_mode & stat.S_IXUSR, f"Agent script {AGENT_SCRIPT} is not executable."


def test_parser_is_patched_for_unicode():
    assert os.path.isfile(PARSER_SCRIPT), f"Parser {PARSER_SCRIPT} does not exist."
    st = os.stat(PARSER_SCRIPT)
    assert st.st_mode & stat.S_IXUSR, f"Parser {PARSER_SCRIPT} is not executable."

    line = '{"timestamp": 1700000000, "host": "srv-\\u0031", "metric": "memory_weight", "value": 1024}'
    proc = subprocess.run(
        [PARSER_SCRIPT, line],
        text=True,
        capture_output=True,
    )
    assert proc.returncode == 0, f"Parser still rejects Unicode escapes: {proc.stderr}"
    fields = set(proc.stdout.splitlines())
    assert "metric=memory_weight" in fields, f"Parser did not extract metric: {proc.stdout!r}"
    assert "value=1024" in fields, f"Parser did not extract value: {proc.stdout!r}"


def test_agent_uses_parser_value_output():
    saved_parser = "/tmp/parser_saved_for_usage_test"
    marker = "/tmp/parser_usage_marker"
    shutil.copy2(PARSER_SCRIPT, saved_parser)
    if os.path.exists(marker):
        os.unlink(marker)

    wrapper = f'''#!/bin/bash
echo called >> {marker}
out=$({saved_parser} "$@") || exit $?
printf '%s\n' "$out" | sed 's/^value=.*/value=777/'
'''

    try:
        with open(PARSER_SCRIPT, "w") as f:
            f.write(wrapper)
        os.chmod(PARSER_SCRIPT, 0o755)

        input_data = '{"timestamp": 1700000000, "host": "srv-\\u0031", "metric": "memory_weight", "value": 321}\n'
        proc = subprocess.run(
            [AGENT_SCRIPT],
            input=input_data,
            text=True,
            capture_output=True,
        )
    finally:
        shutil.copy2(saved_parser, PARSER_SCRIPT)

    assert proc.returncode == 0, f"Agent failed while exercising parser: {proc.stderr}"
    assert os.path.isfile(marker), "Agent script did not invoke /app/bash-json-parser/parse.sh."
    assert proc.stdout == "777\n", "Agent did not use the value extracted by the parser."


def generate_jsonl(num_lines):
    lines = []
    for _ in range(num_lines):
        metric = "memory_weight" if random.random() < 0.5 else "cpu_limit"
        value = random.randint(10, 10000)
        if random.random() < 0.5:
            host = f"srv-\\u{random.randint(0, 65535):04x}"
        else:
            host = f"srv-{random.randint(1, 100)}"

        line = f'{{"timestamp": 1700000000, "host": "{host}", "metric": "{metric}", "value": {value}}}'
        lines.append(line)
    return "\n".join(lines) + "\n"


def test_fuzz_equivalence():
    assert os.path.isfile(ORACLE_SCRIPT), f"Oracle script {ORACLE_SCRIPT} missing."

    random.seed(42)
    for i in range(100):
        num_lines = random.randint(50, 500)
        input_data = generate_jsonl(num_lines)

        oracle_proc = subprocess.run(
            ["bash", ORACLE_SCRIPT],
            input=input_data,
            text=True,
            capture_output=True,
        )
        assert oracle_proc.returncode == 0, f"Oracle failed on iteration {i}"

        agent_proc = subprocess.run(
            [AGENT_SCRIPT],
            input=input_data,
            text=True,
            capture_output=True,
        )

        if agent_proc.returncode != 0:
            pytest.fail(f"Agent script failed on iteration {i} with exit code {agent_proc.returncode}.\nStderr: {agent_proc.stderr}")

        if agent_proc.stdout != oracle_proc.stdout:
            pytest.fail(
                f"Output mismatch on iteration {i}.\n"
                f"Input sample:\n{input_data[:200]}...\n"
                f"Expected output sample:\n{oracle_proc.stdout[:200]}...\n"
                f"Agent output sample:\n{agent_proc.stdout[:200]}..."
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
