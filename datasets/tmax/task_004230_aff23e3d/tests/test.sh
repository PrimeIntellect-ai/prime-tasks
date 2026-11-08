#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import filecmp
import importlib.machinery
import json
import os
import random
import string
import struct
import subprocess
import tempfile

ORACLE_PATH = "/opt/oracle/process_artifacts_oracle.py"
AGENT_PATH = "/home/user/process_artifacts.py"
PARSER_DIR = "/app/vendored/artifact_parser-1.2.0"
PARSER_SOURCE = os.path.join(PARSER_DIR, "src/parser.c")
BUILD_TOOL_DIR = "/app/build_tool"
NUM_TESTS = 1000


def generate_valid_manifest():
    """Generate a validly formatted manifest: 4-byte integer N, followed by N length-prefixed strings."""
    num_entries = random.randint(0, 20)
    data = bytearray(num_entries.to_bytes(4, byteorder="little"))
    for _ in range(num_entries):
        length = random.randint(1, 50)
        value = "".join(random.choices(string.ascii_letters + string.digits, k=length)).encode("utf-8")
        data += length.to_bytes(4, byteorder="little") + value
    return bytes(data)


def generate_random_bytes():
    """Generate random bytes to trigger edge cases and test memory safety."""
    return os.urandom(random.randint(4, 2048))


def test_a_build_tool_is_buildable_and_generates_fixtures():
    assert os.path.isfile(os.path.join(BUILD_TOOL_DIR, "go.mod"))

    binary = "/tmp/build_tool_verified"
    if os.path.exists(binary):
        os.unlink(binary)

    build = subprocess.run(
        ["go", "build", "-o", binary, "."],
        cwd=BUILD_TOOL_DIR,
        capture_output=True,
        text=True,
        timeout=60,
    )
    assert build.returncode == 0, f"Go tool does not build:\n{build.stdout}\n{build.stderr}"
    assert os.path.isfile(binary) and os.access(binary, os.X_OK)

    fixtures_dir = "/tmp/fixtures"
    if os.path.lexists(fixtures_dir):
        if os.path.isdir(fixtures_dir) and not os.path.islink(fixtures_dir):
            import shutil
            shutil.rmtree(fixtures_dir)
        else:
            os.unlink(fixtures_dir)

    run = subprocess.run(
        [binary],
        cwd=BUILD_TOOL_DIR,
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert run.returncode == 0, f"Built Go tool failed:\n{run.stdout}\n{run.stderr}"
    assert os.path.isdir(fixtures_dir), "Running the rebuilt Go tool did not create /tmp/fixtures"
    assert os.listdir(fixtures_dir), "Running the rebuilt Go tool created no fixtures"


def _extension_probe(prefix):
    return f'''
import importlib.machinery
import struct
import sys
{prefix}
import artifact_parser
assert any(artifact_parser.__file__.endswith(s) for s in importlib.machinery.EXTENSION_SUFFIXES), artifact_parser.__file__

def expect_value(data, expected):
    actual = artifact_parser.parse_manifest(data)
    assert actual == expected, (actual, expected)

def expect_value_error(data):
    try:
        artifact_parser.parse_manifest(data)
    except ValueError:
        return
    raise AssertionError("malformed input did not raise ValueError")

expect_value(struct.pack("=i", 2) + struct.pack("=i", 1) + b"z" + struct.pack("=i", 2) + b"aa", ["z", "aa"])
expect_value(struct.pack("=i", 0), [])
expect_value_error(b"")
expect_value_error(struct.pack("=i", 1))
expect_value_error(struct.pack("=i", 1) + struct.pack("=i", 8) + b"x")
expect_value_error(struct.pack("=i", 1) + struct.pack("=i", -1))
expect_value_error(struct.pack("=i", 1) + struct.pack("=i", 1) + b"\\xff")
print("OK")
'''


def test_c_source_rebuilds_safely_and_extension_is_installed():
    assert os.path.isfile(PARSER_SOURCE), f"Missing required source file: {PARSER_SOURCE}"
    assert os.path.isfile(os.path.join(PARSER_DIR, "setup.py"))

    with tempfile.TemporaryDirectory() as tmpdir:
        build_lib = os.path.join(tmpdir, "lib")
        build_temp = os.path.join(tmpdir, "temp")
        build = subprocess.run(
            [
                "python3", "setup.py", "build_ext", "--force",
                "--build-lib", build_lib, "--build-temp", build_temp,
            ],
            cwd=PARSER_DIR,
            capture_output=True,
            text=True,
            timeout=90,
        )
        assert build.returncode == 0, f"parser.c cannot be rebuilt:\n{build.stdout}\n{build.stderr}"

        fresh_probe = subprocess.run(
            ["python3", "-c", _extension_probe(f"sys.path.insert(0, {build_lib!r})")],
            cwd=tmpdir,
            capture_output=True,
            text=True,
            timeout=20,
        )
        assert fresh_probe.returncode == 0, (
            "Extension rebuilt from parser.c is unsafe or incorrect:\n"
            f"{fresh_probe.stdout}\n{fresh_probe.stderr}"
        )

    installed_probe = subprocess.run(
        ["python3", "-I", "-c", _extension_probe("")],
        cwd="/tmp",
        capture_output=True,
        text=True,
        timeout=20,
    )
    assert installed_probe.returncode == 0, (
        "The installed artifact_parser C extension is missing, stale, unsafe, or incorrect:\n"
        f"{installed_probe.stdout}\n{installed_probe.stderr}"
    )


def test_script_really_uses_parse_manifest_result():
    assert os.path.isfile(AGENT_PATH), f"Agent script not found at {AGENT_PATH}"
    assert not filecmp.cmp(AGENT_PATH, ORACLE_PATH, shallow=False), "Agent script is a byte-identical copy of the reference"

    with tempfile.TemporaryDirectory() as tmpdir:
        spy_dir = os.path.join(tmpdir, "spy")
        os.mkdir(spy_dir)
        sitecustomize = os.path.join(spy_dir, "sitecustomize.py")
        with open(sitecustomize, "w") as f:
            f.write(r'''
import json
import os
import sys
import types

module = types.ModuleType("artifact_parser")
def parse_manifest(data):
    expected = bytes.fromhex(os.environ["SPY_EXPECTED_HEX"])
    if not isinstance(data, (bytes, bytearray)) or bytes(data) != expected:
        raise AssertionError("parse_manifest was not called with the file contents")
    with open(os.environ["SPY_MARKER"], "w") as marker:
        marker.write("called")
    mode = os.environ["SPY_MODE"]
    if mode == "raise":
        raise ValueError("malformed")
    if mode == "none":
        return None
    return json.loads(os.environ["SPY_RESULT"])
module.parse_manifest = parse_manifest
sys.modules["artifact_parser"] = module
''')

        cases = [
            (b"not a real manifest one", "list", ["zeta", "alpha", "middle"]),
            (b"not a real manifest two", "list", ["beta", "alpha", "alpha"]),
            (b"raise sentinel", "raise", None),
            (b"none sentinel", "none", None),
        ]
        for index, (data, mode, result) in enumerate(cases):
            input_path = os.path.join(tmpdir, f"spy_input_{index}.bin")
            marker = os.path.join(tmpdir, f"marker_{index}")
            with open(input_path, "wb") as f:
                f.write(data)

            env = os.environ.copy()
            env["PYTHONPATH"] = spy_dir
            env["SPY_EXPECTED_HEX"] = data.hex()
            env["SPY_MARKER"] = marker
            env["SPY_MODE"] = mode
            env["SPY_RESULT"] = json.dumps(result)
            run = subprocess.run(
                ["python3", AGENT_PATH, input_path],
                capture_output=True,
                text=True,
                env=env,
                timeout=10,
            )
            assert run.returncode == 0, run.stderr
            assert os.path.isfile(marker), "process_artifacts.py did not call artifact_parser.parse_manifest"
            expected = '["ERROR"]' if mode in ("raise", "none") else json.dumps(sorted(result))
            assert run.stdout.strip() == expected, (
                "process_artifacts.py did not use and sort parse_manifest's returned value; "
                f"expected {expected!r}, got {run.stdout.strip()!r}"
            )


def test_fuzz_equivalence():
    assert os.path.isfile(AGENT_PATH), f"Agent script not found at {AGENT_PATH}"
    assert os.path.isfile(ORACLE_PATH), f"Oracle script not found at {ORACLE_PATH}"

    random.seed(42)
    with tempfile.TemporaryDirectory() as tmpdir:
        for i in range(NUM_TESTS):
            data = generate_valid_manifest() if random.random() < 0.2 else generate_random_bytes()
            filepath = os.path.join(tmpdir, f"input_{i}.bin")
            with open(filepath, "wb") as f:
                f.write(data)

            oracle_res = subprocess.run(
                ["python3", ORACLE_PATH, filepath], capture_output=True, text=True
            )
            agent_res = subprocess.run(
                ["python3", AGENT_PATH, filepath], capture_output=True, text=True
            )

            assert agent_res.returncode == oracle_res.returncode, (
                f"Return code mismatch on input {i} (length {len(data)}).\n"
                f"Oracle exit code: {oracle_res.returncode}\n"
                f"Agent exit code: {agent_res.returncode}\n"
                f"Agent stderr: {agent_res.stderr}\n"
                "This may indicate a crash due to missing bounds checks."
            )
            assert agent_res.stdout.strip() == oracle_res.stdout.strip(), (
                f"Output mismatch on input {i} (length {len(data)}).\n"
                f"Oracle output: {oracle_res.stdout.strip()}\n"
                f"Agent output: {agent_res.stdout.strip()}\n"
                f"Agent stderr: {agent_res.stderr}"
            )


def test_build_tool_fixtures():
    fixtures_dir = "/tmp/fixtures"
    assert os.path.isdir(fixtures_dir), f"{fixtures_dir} directory was not created. Did you run the Go build tool?"
    assert len(os.listdir(fixtures_dir)) > 0, f"{fixtures_dir} is empty. The Go build tool should generate test fixtures here."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
