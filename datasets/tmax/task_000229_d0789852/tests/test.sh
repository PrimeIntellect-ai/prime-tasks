#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import os
import pwd
import random
import shutil
import subprocess
import tempfile
import pytest

ORACLE_PATH = "/app/legacy_feature_extractor"
AGENT_SCRIPT = "/home/user/py_feature_extractor.py"
GENERATOR = "/app/signal_gen_src/signal_gen"
RAW_DATA = "/home/user/raw_signals.txt"
LEGACY_DATA = "/home/user/legacy_features.txt"
NOTEBOOK = "/home/user/analyze_transform.ipynb"
N_ITERATIONS = 100
SEED = 42


def test_agent_script_exists():
    assert os.path.isfile(AGENT_SCRIPT), f"Agent script not found at {AGENT_SCRIPT}"


def test_required_workflow_artifacts():
    assert os.path.isfile(GENERATOR), f"Compiled signal generator not found at {GENERATOR}"
    assert os.access(GENERATOR, os.X_OK), f"Signal generator is not executable: {GENERATOR}"
    assert os.path.isfile(RAW_DATA), f"Raw dataset not found at {RAW_DATA}"
    assert os.path.isfile(LEGACY_DATA), f"Legacy feature dataset not found at {LEGACY_DATA}"
    assert os.path.isfile(NOTEBOOK), f"Notebook not found at {NOTEBOOK}"
    assert os.path.isfile(ORACLE_PATH), f"Oracle binary not found at {ORACLE_PATH}"
    assert os.access(ORACLE_PATH, os.X_OK), f"Oracle binary is not executable: {ORACLE_PATH}"

    generated = subprocess.run(
        [GENERATOR], capture_output=True, check=True, timeout=10
    ).stdout
    with open(RAW_DATA, "rb") as f:
        raw = f.read()
    assert raw == generated, "raw_signals.txt is not the 10,000-point output of signal_gen"
    raw_lines = raw.splitlines()
    assert len(raw_lines) == 10000, f"Expected 10,000 raw signals, found {len(raw_lines)}"
    for line in raw_lines:
        float(line)

    expected_legacy = subprocess.run(
        [ORACLE_PATH], input=raw, capture_output=True, check=True, timeout=10
    ).stdout
    with open(LEGACY_DATA, "rb") as f:
        legacy = f.read()
    assert legacy == expected_legacy, "legacy_features.txt was not produced from raw_signals.txt by the legacy extractor"

    candidates = [NOTEBOOK, "/home/user/analyze_transform.nbconvert.ipynb"]
    valid_workflow = False
    for path in candidates:
        if not os.path.isfile(path):
            continue
        try:
            with open(path, encoding="utf-8") as f:
                notebook = json.load(f)
        except Exception:
            continue
        code_cells = [c for c in notebook.get("cells", []) if c.get("cell_type") == "code"]
        source = "\n".join(
            "".join(c.get("source", [])) if isinstance(c.get("source", []), list)
            else str(c.get("source", ""))
            for c in code_cells
        ).lower()
        loads_data = (
            "raw_signals.txt" in source
            and "legacy_features.txt" in source
            and any(marker in source for marker in ("loadtxt", "genfromtxt", "read_csv", "open("))
        )
        fits_parameters = (
            "alpha" in source
            and "beta" in source
            and any(marker in source for marker in ("curve_fit(", "least_squares(", "minimize(", ".fit("))
        )
        executed = bool(code_cells) and all(c.get("execution_count") is not None for c in code_cells)
        if loads_data and fits_parameters and executed:
            valid_workflow = True
            break
    assert valid_workflow, "The notebook must load both datasets, fit alpha and beta, and be executed headlessly"


def test_script_is_pure_python_not_a_binary_proxy():
    with open(AGENT_SCRIPT, "r", encoding="utf-8") as f:
        source = f.read()
    tree = ast.parse(source, filename=AGENT_SCRIPT)

    banned_modules = {"subprocess", "ctypes", "cffi", "pexpect", "importlib", "_posixsubprocess", "posix"}
    os_aliases = set()
    banned_direct_names = set()

    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                root = alias.name.split(".")[0]
                assert root not in banned_modules, f"Pure-Python implementation may not import {alias.name}"
                if alias.name == "os":
                    os_aliases.add(alias.asname or "os")
        elif isinstance(node, ast.ImportFrom):
            root = (node.module or "").split(".")[0]
            assert root not in banned_modules, f"Pure-Python implementation may not import from {node.module}"
            if node.module == "os":
                for alias in node.names:
                    if alias.name == "*" or alias.name in {"system", "popen"} or alias.name.startswith(("exec", "spawn")):
                        banned_direct_names.add(alias.asname or alias.name)

    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        if isinstance(node.func, ast.Name):
            assert node.func.id not in banned_direct_names | {"__import__"}, "External process execution is not allowed"
        elif isinstance(node.func, ast.Attribute) and isinstance(node.func.value, ast.Name):
            if node.func.value.id in os_aliases:
                assert not (node.func.attr in {"system", "popen"} or node.func.attr.startswith(("exec", "spawn"))), \
                    "External process execution is not allowed"


def _demote_to_user():
    account = pwd.getpwnam("user")
    os.setgroups([])
    os.setgid(account.pw_gid)
    os.setuid(account.pw_uid)


def test_fuzz_equivalence():
    assert os.path.isfile(ORACLE_PATH), f"Oracle binary not found at {ORACLE_PATH}"
    assert os.access(ORACLE_PATH, os.X_OK), f"Oracle binary at {ORACLE_PATH} is not executable"

    random.seed(SEED)
    cases = []
    for i in range(N_ITERATIONS):
        seq_length = random.randint(1, 5000)
        input_floats = [random.uniform(-100.0, 100.0) for _ in range(seq_length)]
        input_data = "\n".join(f"{x:.6f}" for x in input_floats) + "\n"
        input_bytes = input_data.encode("utf-8")
        try:
            oracle_proc = subprocess.run(
                [ORACLE_PATH], input=input_bytes, capture_output=True, check=True, timeout=5
            )
        except subprocess.CalledProcessError as e:
            pytest.fail(f"Oracle failed on iteration {i}: {e.stderr.decode('utf-8', errors='replace')}")
        except subprocess.TimeoutExpired:
            pytest.fail(f"Oracle timed out on iteration {i}")
        cases.append((input_floats, input_bytes, oracle_proc.stdout.decode("utf-8")))

    # The instruction requires the oracle during the workflow, so it cannot be removed
    # from the initial image. Hide it in a root-only directory while exercising the
    # submitted program, preventing a wrapper from delegating transformation work to it.
    private_dir = tempfile.mkdtemp(prefix="verifier-oracle-")
    os.chmod(private_dir, 0o700)
    hidden_oracle = os.path.join(private_dir, "oracle")
    os.replace(ORACLE_PATH, hidden_oracle)
    try:
        for i, (input_floats, input_bytes, oracle_output) in enumerate(cases):
            try:
                agent_proc = subprocess.run(
                    ["python3", AGENT_SCRIPT],
                    input=input_bytes,
                    capture_output=True,
                    check=True,
                    timeout=5,
                    preexec_fn=_demote_to_user,
                )
                agent_output = agent_proc.stdout.decode("utf-8")
            except subprocess.CalledProcessError as e:
                pytest.fail(f"Agent script failed on iteration {i}: {e.stderr.decode('utf-8', errors='replace')}")
            except subprocess.TimeoutExpired:
                pytest.fail(f"Agent script timed out on iteration {i}")

            if oracle_output != agent_output:
                err_msg = f"Output mismatch on iteration {i} (sequence length {len(input_floats)}).\n"
                oracle_lines = oracle_output.splitlines()
                agent_lines = agent_output.splitlines()
                for line_idx, (o_line, a_line) in enumerate(zip(oracle_lines, agent_lines)):
                    if o_line != a_line:
                        err_msg += f"First mismatch at line {line_idx}:\n"
                        err_msg += f"Input value: {input_floats[line_idx]:.6f}\n"
                        err_msg += f"Expected (Oracle): {o_line}\n"
                        err_msg += f"Got (Agent):      {a_line}\n"
                        break
                else:
                    if len(oracle_lines) != len(agent_lines):
                        err_msg += f"Line count mismatch. Oracle: {len(oracle_lines)}, Agent: {len(agent_lines)}\n"
                pytest.fail(err_msg)
    finally:
        if os.path.exists(hidden_oracle):
            os.replace(hidden_oracle, ORACLE_PATH)
        shutil.rmtree(private_dir, ignore_errors=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
