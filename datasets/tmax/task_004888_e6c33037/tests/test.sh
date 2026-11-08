#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import glob
import inspect
import json
import os
import random
import shutil
import stat
import string
import subprocess
import sys
import textwrap

import pytest

ORACLE_PATH = "/app/bin/legacy_evaluator"
PROJECT_DIR = "/home/user/api_integration/legacy_decoder"
SOURCE_PATH = os.path.join(PROJECT_DIR, "src", "decoder.c")
SETUP_PATH = os.path.join(PROJECT_DIR, "setup.py")
AGENT_SCRIPT = "/home/user/api_integration/run_api.py"

STANDARD_B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
CUSTOM_B64 = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-_"


def custom_b64encode(data: bytes) -> str:
    std_b64 = base64.b64encode(data).decode("ascii")
    return std_b64.translate(str.maketrans(STANDARD_B64, CUSTOM_B64))


def generate_valid_rpn():
    stack_depth = 0
    tokens = []
    num_tokens = random.randint(3, 15)
    for _ in range(num_tokens):
        if stack_depth >= 2 and random.random() < 0.5:
            tokens.append(random.choice(["+", "-", "*"]))
            stack_depth -= 1
        else:
            tokens.append(str(random.randint(-100, 100)))
            stack_depth += 1
    while stack_depth > 1:
        tokens.append(random.choice(["+", "-", "*"]))
        stack_depth -= 1
    return " ".join(tokens)


def generate_fuzz_inputs(n=1000):
    random.seed(42)
    inputs = []
    for _ in range(n):
        if random.random() < 0.7:
            inputs.append(custom_b64encode(generate_valid_rpn().encode("ascii")))
        else:
            length = random.randint(4, 64)
            if random.random() < 0.5:
                s = "".join(random.choice(CUSTOM_B64 + "=") for _ in range(length))
            else:
                s = "".join(random.choice(string.printable) for _ in range(length))
            inputs.append(s)
    return inputs


def oracle_results(inputs):
    results = []
    for inp in inputs:
        proc = subprocess.run(
            [ORACLE_PATH, inp], capture_output=True, text=True, timeout=2
        )
        out = proc.stdout.strip()
        if not out and proc.stderr:
            out = proc.stderr.strip()
        results.append((out, proc.returncode))
    return results


def install_noexec_site(path, shim=False):
    os.makedirs(path, exist_ok=True)
    shim_code = ""
    if shim:
        shim_code = r'''
import os, sys, types
m = types.ModuleType("legacy_decoder")
def evaluate(value):
    with open(os.environ["DECODER_MARKER"], "w") as f:
        f.write(value)
    return 314159
m.evaluate = evaluate
sys.modules["legacy_decoder"] = m
'''
    code = r'''
# Install a seccomp filter which permits normal Python operation but denies
# execve/execveat after this interpreter has started. This prevents wrappers or
# extensions from delegating evaluation to a copied or relocated oracle.
import ctypes
import errno

class SockFilter(ctypes.Structure):
    _fields_ = [("code", ctypes.c_ushort), ("jt", ctypes.c_ubyte),
                ("jf", ctypes.c_ubyte), ("k", ctypes.c_uint32)]
class SockFprog(ctypes.Structure):
    _fields_ = [("len", ctypes.c_ushort),
                ("filter", ctypes.POINTER(SockFilter))]

BPF_LD = 0x00
BPF_W = 0x00
BPF_ABS = 0x20
BPF_JMP = 0x05
BPF_JEQ = 0x10
BPF_K = 0x00
BPF_RET = 0x06
SECCOMP_RET_ALLOW = 0x7fff0000
SECCOMP_RET_ERRNO = 0x00050000
PR_SET_NO_NEW_PRIVS = 38
PR_SET_SECCOMP = 22
SECCOMP_MODE_FILTER = 2

filters = (SockFilter * 6)(
    SockFilter(BPF_LD | BPF_W | BPF_ABS, 0, 0, 0),
    SockFilter(BPF_JMP | BPF_JEQ | BPF_K, 0, 1, 59),
    SockFilter(BPF_RET | BPF_K, 0, 0, SECCOMP_RET_ERRNO | errno.EACCES),
    SockFilter(BPF_JMP | BPF_JEQ | BPF_K, 0, 1, 322),
    SockFilter(BPF_RET | BPF_K, 0, 0, SECCOMP_RET_ERRNO | errno.EACCES),
    SockFilter(BPF_RET | BPF_K, 0, 0, SECCOMP_RET_ALLOW),
)
prog = SockFprog(len(filters), filters)
libc = ctypes.CDLL(None, use_errno=True)
if libc.prctl(PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0) != 0:
    raise OSError(ctypes.get_errno(), "PR_SET_NO_NEW_PRIVS failed")
if libc.prctl(PR_SET_SECCOMP, SECCOMP_MODE_FILTER, ctypes.byref(prog)) != 0:
    raise OSError(ctypes.get_errno(), "PR_SET_SECCOMP failed")
''' + shim_code
    with open(os.path.join(path, "sitecustomize.py"), "w") as f:
        f.write(code)


@pytest.fixture(scope="session")
def installed_extension():
    assert os.path.isfile(SETUP_PATH), "setup.py is missing"
    assert os.path.isfile(SOURCE_PATH), "src/decoder.c is missing"

    setup_text = open(SETUP_PATH, encoding="utf-8").read()
    source_text = open(SOURCE_PATH, encoding="utf-8", errors="replace").read()
    assert "Extension" in setup_text and "src/decoder.c" in setup_text.replace("\\\\", "/"), (
        "setup.py must build the extension from src/decoder.c"
    )
    assert CUSTOM_B64 in source_text, "decoder.c does not contain the required custom alphabet"

    # Force the editable installation to rebuild instead of reusing an artifact
    # left by the submission.
    for pattern in [
        os.path.join(PROJECT_DIR, "legacy_decoder*.so"),
        os.path.join(PROJECT_DIR, "**", "legacy_decoder*.so"),
    ]:
        for artifact in glob.glob(pattern, recursive=True):
            os.remove(artifact)
    shutil.rmtree(os.path.join(PROJECT_DIR, "build"), ignore_errors=True)

    proc = subprocess.run(
        [sys.executable, "-m", "pip", "install", "-e", "."],
        cwd=PROJECT_DIR,
        capture_output=True,
        text=True,
        timeout=120,
    )
    assert proc.returncode == 0, f"pip install -e . failed:\n{proc.stdout}\n{proc.stderr}"
    return True


def test_run_api_exists():
    assert os.path.exists(AGENT_SCRIPT), f"Agent script not found at {AGENT_SCRIPT}"


def test_native_extension_and_direct_behavior(installed_extension, tmp_path):
    assert os.path.exists(ORACLE_PATH), f"Oracle not found at {ORACLE_PATH}"
    assert os.access(ORACLE_PATH, os.X_OK), "Oracle not executable"

    inputs = generate_fuzz_inputs(1000)
    expected = oracle_results(inputs)

    site = str(tmp_path / "noexec")
    install_noexec_site(site)
    helper = tmp_path / "exercise_extension.py"
    helper.write_text(textwrap.dedent(r'''
        import importlib.machinery
        import inspect
        import json
        import legacy_decoder
        import sys

        origin = getattr(legacy_decoder, "__file__", "") or ""
        is_native = any(origin.endswith(s) for s in importlib.machinery.EXTENSION_SUFFIXES)
        is_builtin = inspect.isbuiltin(getattr(legacy_decoder, "evaluate", None))
        answers = []
        for value in json.load(sys.stdin):
            try:
                answers.append({"value": legacy_decoder.evaluate(value)})
            except BaseException:
                answers.append({"error": True})
        print(json.dumps({"origin": origin, "native": is_native,
                          "builtin": is_builtin, "answers": answers}))
    '''))
    env = os.environ.copy()
    env["PYTHONPATH"] = site
    proc = subprocess.run(
        [sys.executable, str(helper)],
        input=json.dumps(inputs),
        capture_output=True,
        text=True,
        env=env,
        timeout=30,
    )
    assert proc.returncode == 0, f"native module crashed or failed:\n{proc.stdout}\n{proc.stderr}"
    report = json.loads(proc.stdout)
    assert report["native"], f"legacy_decoder is not a native extension: {report['origin']}"
    assert report["builtin"], "legacy_decoder.evaluate is not implemented by the extension"
    assert len(report["answers"]) == len(inputs)

    for i, ((oracle_out, _), answer) in enumerate(zip(expected, report["answers"])):
        if oracle_out == "ERROR":
            assert answer.get("error") is True, f"extension accepted invalid input {i}: {inputs[i]!r}"
        else:
            assert answer.get("value") == int(oracle_out), (
                f"direct extension mismatch on input {i}: {inputs[i]!r}; "
                f"expected {oracle_out}, got {answer!r}"
            )


def test_wrapper_uses_module(installed_extension, tmp_path):
    site = str(tmp_path / "shim")
    install_noexec_site(site, shim=True)
    marker = str(tmp_path / "called")
    encoded = custom_b64encode(b"1")
    env = os.environ.copy()
    env["PYTHONPATH"] = site
    env["DECODER_MARKER"] = marker
    proc = subprocess.run(
        [sys.executable, AGENT_SCRIPT, encoded],
        capture_output=True,
        text=True,
        env=env,
        timeout=5,
    )
    assert proc.stdout.strip() == "314159", "run_api.py did not print the module's result"
    assert os.path.exists(marker), "run_api.py did not call legacy_decoder.evaluate"
    assert open(marker).read() == encoded


def test_fuzz_equivalence(installed_extension, tmp_path):
    assert os.path.exists(ORACLE_PATH), f"Oracle not found at {ORACLE_PATH}"
    assert os.access(ORACLE_PATH, os.X_OK), "Oracle not executable"

    inputs = generate_fuzz_inputs(1000)
    expected = oracle_results(inputs)
    site = str(tmp_path / "noexec")
    install_noexec_site(site)
    env = os.environ.copy()
    env["PYTHONPATH"] = site

    for i, (inp, (oracle_out, oracle_code)) in enumerate(zip(inputs, expected)):
        try:
            agent_proc = subprocess.run(
                [sys.executable, AGENT_SCRIPT, inp],
                capture_output=True,
                text=True,
                timeout=2,
                env=env,
            )
        except subprocess.TimeoutExpired:
            pytest.fail(f"Agent script timed out on input: {inp}")

        agent_out = agent_proc.stdout.strip()
        if not agent_out and agent_proc.stderr:
            agent_out = agent_proc.stderr.strip()
        assert agent_out == oracle_out, (
            f"Output mismatch on input {i}: {inp!r}\n"
            f"Oracle output: {oracle_out!r}\n"
            f"Agent output:  {agent_out!r}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
