#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import random
import string
import subprocess
import py_compile


def test_toposort_syntax_fixed():
    path = "/app/toposort-1.10/toposort.py"
    assert os.path.isfile(path), f"Vendored package file {path} does not exist."

    try:
        py_compile.compile(path, doraise=True)
    except py_compile.PyCompileError as e:
        assert False, f"SyntaxError is still present in {path}: {e}"

    proc = subprocess.run(
        [
            "python3",
            "-c",
            "import sys; sys.path.insert(0, '/app/toposort-1.10'); "
            "import toposort; "
            "assert toposort.__file__.startswith('/app/toposort-1.10/'); "
            "assert toposort.toposort_flatten({'b': {'a'}, 'a': set()}, sort=True) == ['a', 'b']",
        ],
        capture_output=True,
        text=True,
    )
    assert proc.returncode == 0, f"Vendored toposort is not functional: {proc.stderr}"


def generate_dag(num_nodes):
    nodes = []
    for _ in range(num_nodes):
        name = ''.join(random.choices(string.ascii_letters + string.digits, k=random.randint(3, 10)))
        while name in nodes:
            name = ''.join(random.choices(string.ascii_letters + string.digits, k=random.randint(3, 10)))
        nodes.append(name)

    manifest = {}
    for i, node in enumerate(nodes):
        cost = random.randint(1, 100)
        num_deps = random.randint(0, min(5, i))
        deps = random.sample(nodes[:i], num_deps) if num_deps > 0 else []
        manifest[node] = {"cost": cost, "deps": deps}
    return manifest


def test_scheduler_fuzz_equivalence():
    agent_script = "/home/user/scheduler.py"
    oracle_script = "/tests/scheduler_oracle.py"
    package_path = "/app/toposort-1.10/toposort.py"
    marker = "/tmp/scheduler_used_vendored_toposort"

    assert os.path.isfile(agent_script), f"Agent script {agent_script} does not exist."
    assert os.path.isfile(oracle_script), f"Oracle script {oracle_script} does not exist."

    with open(package_path, "rb") as f:
        original_package = f.read()

    instrumentation = b'''\n\n# Verification instrumentation\n_verifier_original_toposort = toposort\ndef toposort(data):\n    with open("/tmp/scheduler_used_vendored_toposort", "a") as _marker:\n        _marker.write("toposort\\n")\n    return _verifier_original_toposort(data)\n\n_verifier_original_flatten = toposort_flatten\ndef toposort_flatten(data, sort=True):\n    with open("/tmp/scheduler_used_vendored_toposort", "a") as _marker:\n        _marker.write("toposort_flatten\\n")\n    return _verifier_original_flatten(data, sort=sort)\n'''

    try:
        with open(package_path, "ab") as f:
            f.write(instrumentation)

        random.seed(42)
        input_file = "/tmp/fuzz_input.json"

        for i in range(100):
            num_nodes = random.randint(5, 50)
            dag = generate_dag(num_nodes)

            with open(input_file, "w") as f:
                json.dump(dag, f)

            oracle_proc = subprocess.run(
                ["python3", oracle_script, input_file],
                capture_output=True,
                text=True
            )
            assert oracle_proc.returncode == 0, f"Oracle failed on iteration {i}. Stderr: {oracle_proc.stderr}"

            if os.path.exists(marker):
                os.remove(marker)

            agent_proc = subprocess.run(
                ["python3", agent_script, input_file],
                capture_output=True,
                text=True
            )
            assert agent_proc.returncode == 0, f"Agent script failed on iteration {i}. Stderr: {agent_proc.stderr}"
            assert os.path.isfile(marker), (
                f"Agent script did not use the vendored toposort package on iteration {i}."
            )

            try:
                oracle_out = json.loads(oracle_proc.stdout)
            except json.JSONDecodeError:
                assert False, f"Oracle output is not valid JSON. Output: {oracle_proc.stdout}"

            try:
                agent_out = json.loads(agent_proc.stdout)
            except json.JSONDecodeError:
                assert False, f"Agent output is not valid JSON. Output: {agent_proc.stdout}"

            assert agent_out == oracle_out, (
                f"Output mismatch on iteration {i}.\n"
                f"Input DAG: {json.dumps(dag)}\n"
                f"Oracle output: {json.dumps(oracle_out)}\n"
                f"Agent output: {json.dumps(agent_out)}"
            )
    finally:
        with open(package_path, "wb") as f:
            f.write(original_package)
        if os.path.exists(marker):
            os.remove(marker)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
