#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import glob
import json
import os
import random
import shutil
import string
import subprocess
import sysconfig
import pytest

ORACLE_PATH = "/opt/oracle/analyze_oracle"
AGENT_SCRIPT = "/home/user/analyze.py"
PACKAGE_DIR = "/app/vendored/fast_forensic_hash"
PYTHON_BIN = "/usr/bin/python3"


def run_as_user(args, **kwargs):
    return subprocess.run(
        ["runuser", "-u", "user", "--", "env", "HOME=/home/user"] + args,
        **kwargs,
    )


def generate_fuzz_inputs(n=100, seed=42):
    random.seed(seed)
    inputs = []
    for _ in range(n):
        if random.random() < 0.9:
            length = random.randint(10, 1000)
            raw_bytes = bytes(random.getrandbits(8) for _ in range(length))
            inputs.append(base64.b64encode(raw_bytes).decode("utf-8"))
        else:
            length = random.randint(10, 100)
            bad_chars = "!@#$%^&*()_+"
            inputs.append("".join(
                random.choice(string.ascii_letters + string.digits + bad_chars)
                for _ in range(length)
            ))
    return inputs


def test_package_builds_cleanly_and_installs_as_c_extension():
    setup_py = os.path.join(PACKAGE_DIR, "setup.py")
    source_c = os.path.join(PACKAGE_DIR, "hash_module.c")
    assert os.path.isfile(setup_py), "Vendored setup.py is missing."
    assert os.path.isfile(source_c), "Vendored C-extension source is missing."

    # Remove prior build products so a stale or manually supplied binary cannot
    # conceal an unfixed setup.py/linker configuration.
    shutil.rmtree(os.path.join(PACKAGE_DIR, "build"), ignore_errors=True)
    for path in glob.glob(os.path.join(PACKAGE_DIR, "*.egg-info")):
        shutil.rmtree(path, ignore_errors=True)
    for suffix in sysconfig.get_config_var("EXT_SUFFIX"), ".so":
        if suffix:
            for path in glob.glob(os.path.join(PACKAGE_DIR, "fast_forensic_hash*" + suffix)):
                os.remove(path)

    try:
        install = run_as_user(
            [PYTHON_BIN, "-m", "pip", "install", "--user", "--no-deps",
             "--no-build-isolation", "-e", "."],
            cwd=PACKAGE_DIR,
            capture_output=True,
            text=True,
            timeout=120,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("pip install -e . timed out")

    assert install.returncode == 0, (
        "pip install -e . failed.\n"
        f"stdout:\n{install.stdout}\n"
        f"stderr:\n{install.stderr}"
    )

    probe = r'''
import json
import fast_forensic_hash as m
vectors = [b"", b"abc", bytes(range(256)), b"forensic\x00artifact"]
print(json.dumps({"file": getattr(m, "__file__", ""),
                  "values": [m.compute_hash(v).hex() for v in vectors]}))
'''
    imported = run_as_user(
        [PYTHON_BIN, "-c", probe],
        cwd="/tmp",
        capture_output=True,
        text=True,
        timeout=10,
    )
    assert imported.returncode == 0, (
        "Installed fast_forensic_hash could not be imported or called.\n"
        f"stdout: {imported.stdout}\nstderr: {imported.stderr}"
    )
    result = json.loads(imported.stdout)
    extension_suffixes = tuple(
        s for s in (sysconfig.get_config_var("EXT_SUFFIX"), ".so") if s
    )
    assert result["file"].endswith(extension_suffixes), (
        f"fast_forensic_hash is not an installed C extension: {result['file']}"
    )

    import zlib
    vectors = [b"", b"abc", bytes(range(256)), b"forensic\x00artifact"]
    expected = [
        ((zlib.crc32(v) & 0xffffffff).to_bytes(4, "big") +
         (zlib.adler32(v) & 0xffffffff).to_bytes(4, "big")).hex()
        for v in vectors
    ]
    assert result["values"] == expected


def test_agent_script_exists():
    assert os.path.isfile(AGENT_SCRIPT), f"Agent script {AGENT_SCRIPT} does not exist."
    with open(AGENT_SCRIPT, "rb") as agent, open(ORACLE_PATH, "rb") as oracle:
        assert agent.read() != oracle.read(), "Agent script is byte-identical to the oracle."


def test_agent_imports_and_uses_compute_hash():
    raw = b"extension-call-probe\x00\xff"
    encoded = base64.b64encode(raw).decode("ascii")
    sentinel = "0123456789abcdef"
    launcher = r'''
import runpy, sys, types
expected = b"extension-call-probe\x00\xff"
m = types.ModuleType("fast_forensic_hash")
def compute_hash(data):
    if data != expected:
        raise AssertionError("analyze.py passed incorrect bytes to compute_hash")
    return bytes.fromhex("0123456789abcdef")
m.compute_hash = compute_hash
sys.modules["fast_forensic_hash"] = m
sys.argv = ["/home/user/analyze.py", sys.argv[1]]
runpy.run_path("/home/user/analyze.py", run_name="__main__")
'''
    result = run_as_user(
        [PYTHON_BIN, "-c", launcher, encoded],
        capture_output=True,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, (
        "analyze.py did not successfully import and call "
        f"fast_forensic_hash.compute_hash. stderr: {result.stderr}"
    )
    assert result.stdout == sentinel + "\n", (
        "analyze.py must print the bytes returned by "
        "fast_forensic_hash.compute_hash as lowercase hexadecimal."
    )


def test_fuzz_equivalence():
    assert os.path.isfile(ORACLE_PATH), f"Oracle {ORACLE_PATH} missing."
    assert os.access(ORACLE_PATH, os.X_OK), f"Oracle {ORACLE_PATH} not executable."

    inputs = generate_fuzz_inputs(100)
    for idx, inp in enumerate(inputs):
        try:
            oracle_res = subprocess.run(
                [ORACLE_PATH, inp], capture_output=True, text=True, timeout=5
            )
        except subprocess.TimeoutExpired:
            pytest.fail(f"Oracle timed out on input {idx}")

        try:
            agent_res = run_as_user(
                [PYTHON_BIN, AGENT_SCRIPT, inp],
                capture_output=True,
                text=True,
                timeout=5,
            )
        except subprocess.TimeoutExpired:
            pytest.fail(f"Agent script timed out on input {idx}")

        assert agent_res.returncode == oracle_res.returncode, (
            f"Return code mismatch on input {idx}.\n"
            f"Input: {inp[:50]}...\n"
            f"Oracle RC: {oracle_res.returncode}, Agent RC: {agent_res.returncode}\n"
            f"Oracle stdout: {oracle_res.stdout}\n"
            f"Agent stdout: {agent_res.stdout}\n"
            f"Agent stderr: {agent_res.stderr}"
        )
        assert agent_res.stdout == oracle_res.stdout, (
            f"Stdout mismatch on input {idx}.\n"
            f"Input: {inp[:50]}...\n"
            f"Oracle stdout: {repr(oracle_res.stdout)}\n"
            f"Agent stdout: {repr(agent_res.stdout)}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
