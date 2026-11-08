#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import importlib.metadata
import importlib.machinery
import json
import os
import random
import string
import subprocess
import sys
import tempfile
import urllib.parse
import zipfile

import pytest

SOURCE_DIR = "/app/ultrajson"
AGENT_SCRIPT = "/home/user/process_record.py"
ORACLE_SCRIPT = "/app/oracle_processor.py"


def test_ujson_installed():
    """Verify that the installed ujson is the native vendored package, not a Python shim."""
    try:
        import ujson
    except ImportError:
        pytest.fail("ujson is not installed. The agent failed to fix and install the package.")

    assert ujson.dumps({"test": 1}) == '{"test":1}', "ujson is installed but dumps() failed."
    assert ujson.loads('{"a":[1,true,null]}') == {"a": [1, True, None]}

    module_path = os.path.realpath(ujson.__file__)
    assert os.path.isfile(module_path), f"Imported ujson has no module file: {module_path}"
    assert any(module_path.endswith(suffix) for suffix in importlib.machinery.EXTENSION_SUFFIXES), (
        f"ujson must be a compiled extension, not a Python shim: {module_path}"
    )
    assert importlib.metadata.version("ujson") == "5.4.0"


def test_vendored_source_builds_and_matches_installation():
    """Build the repaired vendored tree and verify the active install came from it."""
    assert os.path.isdir(SOURCE_DIR), f"Vendored source directory is missing: {SOURCE_DIR}"
    assert os.path.isfile(os.path.join(SOURCE_DIR, "setup.py")), "Vendored setup.py is missing"

    with tempfile.TemporaryDirectory() as wheel_dir:
        proc = subprocess.run(
            [sys.executable, "-m", "pip", "wheel", "--no-deps", "--no-build-isolation", "--no-cache-dir",
             "--wheel-dir", wheel_dir, SOURCE_DIR],
            capture_output=True,
            text=True,
            timeout=180,
        )
        assert proc.returncode == 0, (
            "The repaired /app/ultrajson source still cannot build.\n"
            f"stdout:\n{proc.stdout}\nstderr:\n{proc.stderr}"
        )
        wheels = [os.path.join(wheel_dir, name) for name in os.listdir(wheel_dir) if name.endswith(".whl")]
        assert len(wheels) == 1, f"Expected one ujson wheel, found: {wheels}"

        import ujson
        installed_path = os.path.realpath(ujson.__file__)
        installed_hash = hashlib.sha256(open(installed_path, "rb").read()).hexdigest()
        with zipfile.ZipFile(wheels[0]) as archive:
            extension_entries = [
                name for name in archive.namelist()
                if any(name.endswith(suffix) for suffix in importlib.machinery.EXTENSION_SUFFIXES)
            ]
            assert extension_entries, "The vendored build did not produce a native ujson extension"
            built_hashes = {hashlib.sha256(archive.read(name)).hexdigest() for name in extension_entries}

    direct_from_vendor = False
    try:
        dist = importlib.metadata.distribution("ujson")
        direct_url_text = dist.read_text("direct_url.json")
        if direct_url_text:
            direct_url = json.loads(direct_url_text).get("url", "")
            parsed = urllib.parse.urlparse(direct_url)
            direct_path = os.path.realpath(urllib.parse.unquote(parsed.path))
            direct_from_vendor = parsed.scheme == "file" and direct_path == os.path.realpath(SOURCE_DIR)
    except Exception:
        direct_from_vendor = False

    assert direct_from_vendor or installed_hash in built_hashes, (
        "The active ujson extension was not installed from the repaired /app/ultrajson build"
    )


def test_process_record_exists():
    """Verify the agent created the process_record.py script."""
    assert os.path.isfile(AGENT_SCRIPT), "The script /home/user/process_record.py is missing."
    assert os.path.isfile(ORACLE_SCRIPT), f"Oracle script missing: {ORACLE_SCRIPT}"
    assert open(AGENT_SCRIPT, "rb").read() != open(ORACLE_SCRIPT, "rb").read(), (
        "The submitted processor must not be a byte-identical copy of the reference implementation"
    )


def test_processor_really_uses_ujson():
    """Inject a probe ujson module and ensure the processor calls its parser."""
    with tempfile.TemporaryDirectory() as probe_dir:
        probe_module = os.path.join(probe_dir, "ujson.py")
        with open(probe_module, "w", encoding="utf-8") as handle:
            handle.write(
                "def loads(value):\n"
                "    if value != '{\\\"probe\\\":[1,2]}':\n"
                "        raise ValueError('processor extracted the wrong JSON substring')\n"
                "    return {'vendored_parser_used': True, 'value': 9137}\n"
            )

        payload = b"leading-garbage{\"probe\":[1,2]}trailing-garbage".hex()
        env = os.environ.copy()
        env["PYTHONPATH"] = probe_dir
        proc = subprocess.run(
            [sys.executable, AGENT_SCRIPT, payload],
            capture_output=True,
            text=True,
            env=env,
            timeout=10,
        )
        expected = '{"value":9137,"vendored_parser_used":true}'
        assert proc.returncode == 0, f"Processor exited with {proc.returncode}: {proc.stderr}"
        assert proc.stdout.strip() == expected, (
            "process_record.py did not parse the extracted record using ujson.loads"
        )


def generate_fuzz_inputs(n=500, seed=42):
    random.seed(seed)
    inputs = []

    def random_garbage(length):
        alphabet = string.ascii_letters + string.digits + string.punctuation.replace('{', '').replace('}', '')
        return ''.join(random.choices(alphabet, k=length))

    for _ in range(n):
        category = random.random()
        if category < 0.6:
            valid_jsons = [
                '{"status": "ok"}',
                '{"value": 42, "data": [1, 2, 3]}',
                '{"empty": {}}',
                '{"nested": {"a": "b"}}'
            ]
            core = random.choice(valid_jsons)
            prefix = random_garbage(random.randint(0, 50))
            suffix = random_garbage(random.randint(0, 50))
            text = prefix + core + suffix
        elif category < 0.8:
            core = '{"bad": json, "missing_quotes": true'
            prefix = random_garbage(random.randint(0, 50))
            suffix = random_garbage(random.randint(0, 50))
            text = prefix + core + '}' + suffix
        else:
            text = random_garbage(random.randint(10, 100))
        inputs.append(text.encode('utf-8').hex())

    return inputs


def test_fuzz_equivalence():
    """Compare the agent's script against the oracle using 500 randomized inputs."""
    assert os.path.isfile(AGENT_SCRIPT), f"Agent script missing: {AGENT_SCRIPT}"
    assert os.path.isfile(ORACLE_SCRIPT), f"Oracle script missing: {ORACLE_SCRIPT}"

    for i, hex_input in enumerate(generate_fuzz_inputs(n=500)):
        oracle_proc = subprocess.run(
            [sys.executable, ORACLE_SCRIPT, hex_input], capture_output=True, text=True, timeout=10
        )
        agent_proc = subprocess.run(
            [sys.executable, AGENT_SCRIPT, hex_input], capture_output=True, text=True, timeout=10
        )
        oracle_out = oracle_proc.stdout.strip()
        agent_out = agent_proc.stdout.strip()
        if oracle_out != agent_out:
            pytest.fail(
                f"Mismatch on fuzz input {i}!\nInput (hex): {hex_input}\n"
                f"Oracle output: {oracle_out}\nAgent output:  {agent_out}\n"
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
