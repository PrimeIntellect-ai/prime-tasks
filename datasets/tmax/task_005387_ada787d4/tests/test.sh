#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import ast
import os
import random
import subprocess

ORACLE_PATH = "/app/legacy_profiler.bin"
HIDDEN_ORACLE = "/root/.profiler_verifier/legacy_profiler.bin"
AGENT_SCRIPT = "/home/user/profiler_calc.py"
N_TESTS = 200

FORBIDDEN_MODULES = {
    "subprocess", "ctypes", "multiprocessing", "resource", "pty",
    "pexpect", "shutil", "base64", "binascii", "marshal", "pickle",
}
FORBIDDEN_CALLS = {"__import__", "eval", "exec", "compile", "open", "getattr"}
FORBIDDEN_ATTRIBUTES = {
    "system", "popen", "fork", "forkpty", "posix_spawn", "posix_spawnp",
    "execv", "execve", "execvp", "execvpe", "spawnl", "spawnle",
    "spawnlp", "spawnlpe", "spawnv", "spawnve", "spawnvp", "spawnvpe",
    "dlopen", "CDLL", "PyDLL",
}


def generate_input():
    length = random.randint(5, 100)
    seq = [str(random.randint(10, 15000)) for _ in range(length)]
    return ",".join(seq)


def derived_output(data_str):
    score = 0.0
    for item in data_str.split(","):
        val = int(item)
        if val > 9000:
            score += val - 9000
        score *= 0.85
    return f"{score:.4f}"


def assert_pure_python_source():
    assert os.path.isfile(AGENT_SCRIPT), f"Agent script {AGENT_SCRIPT} does not exist."
    with open(AGENT_SCRIPT, "rb") as f:
        source_bytes = f.read()
    assert not source_bytes.startswith(b"\x7fELF"), "profiler_calc.py must be Python source, not an executable."

    source = source_bytes.decode("utf-8")
    tree = ast.parse(source, filename=AGENT_SCRIPT)
    lowered = source.lower()
    assert "legacy_profiler.bin" not in lowered, "The Python replacement may not invoke the oracle binary."

    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                assert alias.name.split(".")[0] not in FORBIDDEN_MODULES, \
                    f"Native/process delegation module {alias.name!r} is not allowed."
        elif isinstance(node, ast.ImportFrom):
            module = (node.module or "").split(".")[0]
            assert module not in FORBIDDEN_MODULES, \
                f"Native/process delegation module {node.module!r} is not allowed."
        elif isinstance(node, ast.Call):
            if isinstance(node.func, ast.Name):
                assert node.func.id not in FORBIDDEN_CALLS, \
                    f"Dynamic/native delegation through {node.func.id!r} is not allowed."
            elif isinstance(node.func, ast.Attribute):
                assert node.func.attr not in FORBIDDEN_ATTRIBUTES, \
                    f"Process/native call {node.func.attr!r} is not allowed."


def reject_copied_executables():
    roots = ["/home/user", "/app", "/tmp", "/dev/shm"]
    oracle_real = os.path.realpath(ORACLE_PATH)
    for root in roots:
        if not os.path.isdir(root):
            continue
        for directory, _, files in os.walk(root):
            for name in files:
                path = os.path.join(directory, name)
                if os.path.realpath(path) == oracle_real:
                    continue
                try:
                    st = os.stat(path)
                    if st.st_uid != 1000:
                        continue
                    with open(path, "rb") as f:
                        magic = f.read(4)
                except (OSError, PermissionError):
                    continue
                assert magic != b"\x7fELF", f"Compiled executable found at {path}; replacement must be pure Python."


def test_fuzz_equivalence():
    assert_pure_python_source()
    assert os.path.exists(ORACLE_PATH), f"Oracle binary {ORACLE_PATH} does not exist."
    reject_copied_executables()

    random.seed(42)
    cases = [generate_input() for _ in range(N_TESTS)]
    expected = []

    for test_input in cases:
        oracle_proc = subprocess.run(
            [ORACLE_PATH, test_input], capture_output=True, text=True
        )
        assert oracle_proc.returncode == 0, \
            f"Oracle failed on input: {test_input}\nStderr: {oracle_proc.stderr}"
        oracle_output = oracle_proc.stdout.strip()
        independently_derived = derived_output(test_input)
        assert oracle_output == independently_derived, \
            f"Oracle disagreed with independently derived result for {test_input}"
        expected.append(oracle_output)

    os.makedirs(os.path.dirname(HIDDEN_ORACLE), mode=0o700, exist_ok=True)
    os.chmod(os.path.dirname(HIDDEN_ORACLE), 0o700)
    os.replace(ORACLE_PATH, HIDDEN_ORACLE)
    try:
        for i, (test_input, oracle_output) in enumerate(zip(cases, expected), 1):
            agent_proc = subprocess.run(
                ["runuser", "-u", "user", "--", "python3", AGENT_SCRIPT, test_input],
                capture_output=True,
                text=True,
            )
            assert agent_proc.returncode == 0, \
                f"Agent script failed on input: {test_input}\nStderr: {agent_proc.stderr}"
            agent_output = agent_proc.stdout.strip()
            assert agent_output == oracle_output, (
                f"Output mismatch on test {i}/{N_TESTS}.\n"
                f"Input: {test_input}\n"
                f"Expected (Oracle): {oracle_output}\n"
                f"Got (Agent): {agent_output}"
            )
    finally:
        if os.path.exists(HIDDEN_ORACLE):
            os.replace(HIDDEN_ORACLE, ORACLE_PATH)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
