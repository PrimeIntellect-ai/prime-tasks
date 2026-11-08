#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import importlib
import inspect
import os
import random
import re
import shutil
import struct
import subprocess
import sys

import pytest

ORACLE_PATH = "/app/oracle_graph_parser"
PKG_DIR = "/home/user/graph_pkg"
CPP_PATH = os.path.join(PKG_DIR, "src", "resolver.cpp")
SETUP_PATH = os.path.join(PKG_DIR, "setup.py")
RUNNER_PATH = "/home/user/solution/runner.py"
AGENT_CMD = ["python3", RUNNER_PATH]


def generate_input(seed):
    random.seed(seed)
    if random.random() < 0.05:
        magic = b"BADD"
    else:
        magic = b"GRPH"

    V = random.randint(1, 500)
    E = random.randint(0, 2000)
    data = bytearray(magic)
    data += struct.pack("<II", V, E)
    for _ in range(E):
        u = random.randint(0, V - 1)
        v = random.randint(0, V - 1)
        data += struct.pack("<II", u, v)
    return bytes(data)


def test_build_and_artifacts():
    assert os.path.isfile(ORACLE_PATH), f"Oracle binary missing at {ORACLE_PATH}"
    assert os.access(ORACLE_PATH, os.X_OK), f"Oracle binary at {ORACLE_PATH} is not executable"
    assert os.path.isfile(SETUP_PATH), "setup.py is missing"
    assert os.path.isfile(CPP_PATH), "src/resolver.cpp is missing"
    assert os.path.isfile(RUNNER_PATH), f"Agent runner script missing at {RUNNER_PATH}"

    setup_text = open(SETUP_PATH, encoding="utf-8", errors="replace").read()
    cpp_text = open(CPP_PATH, encoding="utf-8", errors="replace").read()
    runner_text = open(RUNNER_PATH, encoding="utf-8", errors="replace").read()

    assert "_graph_resolver" in setup_text and "resolver.cpp" in setup_text
    assert "TODO" not in cpp_text, "resolver.cpp still contains the unfinished TODO"
    assert "_graph_resolver" in runner_text and re.search(r"\.resolve\s*\(", runner_text), \
        "runner.py must call _graph_resolver.resolve(data)"

    # Disallow the forwarding implementation that the old verifier accepted.
    forbidden_runner = ["oracle_graph_parser", "subprocess", "os.system", "os.popen"]
    for token in forbidden_runner:
        assert token not in runner_text, f"runner.py forwards work using forbidden token {token!r}"
    assert "oracle_graph_parser" not in cpp_text
    assert not re.search(r"\b(system|popen|fork|vfork|execl|execle|execlp|execv|execve|execvp|posix_spawn)\s*\(", cpp_text), \
        "the C++ resolver must implement the algorithm rather than launch another program"

    # Force a clean source build; a stale or prebuilt extension cannot satisfy this.
    shutil.rmtree(os.path.join(PKG_DIR, "build"), ignore_errors=True)
    for path in glob.glob(os.path.join(PKG_DIR, "_graph_resolver*.so")):
        os.unlink(path)

    proc = subprocess.run(
        [sys.executable, "setup.py", "build_ext", "--inplace", "--force"],
        cwd=PKG_DIR,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=180,
    )
    assert proc.returncode == 0, f"setup.py build failed:\n{proc.stdout.decode(errors='replace')}\n{proc.stderr.decode(errors='replace')}"

    extensions = glob.glob(os.path.join(PKG_DIR, "_graph_resolver*.so"))
    assert extensions, "setup.py did not build an in-place _graph_resolver extension"
    assert all(open(path, "rb").read(4) == b"\x7fELF" for path in extensions), \
        "_graph_resolver is not a native ELF extension"

    sys.path.insert(0, PKG_DIR)
    importlib.invalidate_caches()
    sys.modules.pop("_graph_resolver", None)
    module = importlib.import_module("_graph_resolver")
    assert os.path.realpath(module.__file__) in {os.path.realpath(p) for p in extensions}
    assert callable(module.resolve)
    assert inspect.isbuiltin(module.resolve), "resolve must be provided by the compiled C extension"


def test_fuzz_equivalence_and_leaks():
    assert os.path.isfile(ORACLE_PATH), f"Oracle binary missing at {ORACLE_PATH}"
    assert os.access(ORACLE_PATH, os.X_OK), f"Oracle binary at {ORACLE_PATH} is not executable"
    assert os.path.isfile(AGENT_CMD[1]), f"Agent runner script missing at {AGENT_CMD[1]}"

    cases = [generate_input(i) for i in range(1000)]
    oracle_outputs = []
    for data in cases:
        oracle_proc = subprocess.run([ORACLE_PATH], input=data, capture_output=True)
        assert oracle_proc.returncode == 0
        oracle_outputs.append(oracle_proc.stdout)

    # Remove the oracle while exercising both artifacts, closing direct forwarding.
    oracle_bytes = open(ORACLE_PATH, "rb").read()
    oracle_mode = os.stat(ORACLE_PATH).st_mode & 0o7777
    os.unlink(ORACLE_PATH)
    try:
        sys.path.insert(0, PKG_DIR)
        importlib.invalidate_caches()
        module = importlib.import_module("_graph_resolver")

        for i, (data, oracle_out) in enumerate(zip(cases, oracle_outputs)):
            result = module.resolve(data)
            assert isinstance(result, str), "_graph_resolver.resolve must return a Python string"
            direct_out = result.encode()
            if direct_out != oracle_out:
                pytest.fail(
                    f"Direct extension output mismatch on iteration {i} (seed {i}).\n"
                    f"Input length: {len(data)} bytes\n"
                    f"Oracle output: {oracle_out!r}\n"
                    f"Extension output: {direct_out!r}"
                )

            agent_proc = subprocess.run(AGENT_CMD, input=data, capture_output=True, timeout=20)
            agent_out = agent_proc.stdout
            if oracle_out != agent_out:
                pytest.fail(
                    f"Output mismatch on iteration {i} (seed {i}).\n"
                    f"Input length: {len(data)} bytes\n"
                    f"Oracle output: {oracle_out!r}\n"
                    f"Agent output: {agent_out!r}\n"
                    f"Agent stderr: {agent_proc.stderr!r}"
                )
            assert agent_proc.returncode == 0, f"runner exited with {agent_proc.returncode}: {agent_proc.stderr!r}"

        leak_script = r'''\
import random, struct, sys
sys.path.insert(0, "/home/user/graph_pkg")
import _graph_resolver
for seed in range(600):
    random.seed(seed + 10000)
    V = random.randint(1, 500)
    E = random.randint(0, 2000)
    data = bytearray(b"GRPH") + struct.pack("<II", V, E)
    for _ in range(E):
        data += struct.pack("<II", random.randrange(V), random.randrange(V))
    value = _graph_resolver.resolve(bytes(data))
    if not isinstance(value, str):
        raise SystemExit(2)
'''
        env = os.environ.copy()
        env["PYTHONMALLOC"] = "malloc"
        vg = subprocess.run(
            ["valgrind", "--quiet", "--leak-check=full",
             "--errors-for-leak-kinds=definite,indirect", "--error-exitcode=97",
             sys.executable, "-c", leak_script],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=env,
            timeout=240,
        )
        assert vg.returncode == 0, \
            f"Valgrind found extension errors or leaks (exit {vg.returncode}):\n{vg.stderr.decode(errors='replace')}"
    finally:
        with open(ORACLE_PATH, "wb") as f:
            f.write(oracle_bytes)
        os.chmod(ORACLE_PATH, oracle_mode)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
