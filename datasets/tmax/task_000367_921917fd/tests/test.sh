#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import filecmp
import importlib.machinery
import json
import os
from pathlib import Path
import random
import subprocess
import tempfile
import uuid

import pytest

SCRIPT_PATH = "/home/user/log_sanitizer/sanitizer.py"
VENDOR_DIR = Path("/app/vendored/py-fast-log-parser")


def test_vendored_package_installed():
    try:
        import fast_log_parser
    except ImportError:
        pytest.fail("The vendored package 'fast_log_parser' is not installed or cannot be imported.")

    module_path = getattr(fast_log_parser, "__file__", "")
    assert module_path and any(module_path.endswith(s) for s in importlib.machinery.EXTENSION_SUFFIXES), \
        f"fast_log_parser is not a compiled Python extension: {module_path}"

    parsed = fast_log_parser.parse('{"url":"/installed-check","parameters":{"id":"17"}}')
    assert parsed == {"url": "/installed-check", "parameters": {"id": "17"}}, \
        "fast_log_parser.parse did not parse JSON correctly"

    # Ensure it is importable outside the project/source directories as an installed package.
    env = os.environ.copy()
    env.pop("PYTHONPATH", None)
    env["PYTHONNOUSERSITE"] = "1"
    probe = subprocess.run(
        ["python3", "-c", (
            "import importlib.machinery, fast_log_parser as f; "
            "assert any(f.__file__.endswith(s) for s in importlib.machinery.EXTENSION_SUFFIXES); "
            "assert f.parse('{\\\"x\\\":3}') == {'x': 3}"
        )],
        cwd="/tmp",
        env=env,
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert probe.returncode == 0, f"Installed extension probe failed:\n{probe.stdout}\n{probe.stderr}"


def test_vendored_makefile_builds_extension_from_source():
    assert (VENDOR_DIR / "Makefile").is_file(), "Vendored Makefile is missing"
    assert (VENDOR_DIR / "setup.py").is_file(), "Vendored setup.py is missing"
    assert (VENDOR_DIR / "fast_log_parser.c").is_file(), "Vendored C source is missing"

    # Remove any old in-place artifact so success requires the repaired Makefile to build one.
    for suffix in importlib.machinery.EXTENSION_SUFFIXES:
        for artifact in VENDOR_DIR.glob(f"fast_log_parser*{suffix}"):
            artifact.unlink()

    env = os.environ.copy()
    env.pop("BUILD_ENV", None)
    result = subprocess.run(
        ["make", "-B", "all"],
        cwd=str(VENDOR_DIR),
        env=env,
        capture_output=True,
        text=True,
        timeout=120,
    )
    assert result.returncode == 0, \
        f"Repaired Makefile did not build with a clean BUILD_ENV:\n{result.stdout}\n{result.stderr}"

    artifacts = []
    for suffix in importlib.machinery.EXTENSION_SUFFIXES:
        artifacts.extend(VENDOR_DIR.glob(f"fast_log_parser*{suffix}"))
    assert artifacts, "Makefile succeeded but did not build the vendored C extension in place"

    # Import from the vendored directory and exercise the freshly built artifact.
    local_probe = subprocess.run(
        ["python3", "-c", (
            "import pathlib, fast_log_parser as f; "
            "assert pathlib.Path(f.__file__).resolve().parent == pathlib.Path.cwd().resolve(); "
            "assert f.parse('{\\\"url\\\":\\\"/from-vendored-source\\\",\\\"parameters\\\":{}}')"
            " == {'url':'/from-vendored-source','parameters':{}}"
        )],
        cwd=str(VENDOR_DIR),
        env=env,
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert local_probe.returncode == 0, \
        f"Freshly built vendored extension could not parse JSON:\n{local_probe.stdout}\n{local_probe.stderr}"


def test_sanitizer_script_exists():
    assert os.path.isfile(SCRIPT_PATH), f"Sanitizer script not found at {SCRIPT_PATH}"


def test_sanitizer_functionality():
    clean_in = "/app/corpora/clean"
    evil_in = "/app/corpora/evil"

    assert os.path.isdir(clean_in), f"Clean corpus missing at {clean_in}"
    assert os.path.isdir(evil_in), f"Evil corpus missing at {evil_in}"

    with tempfile.TemporaryDirectory() as clean_out, tempfile.TemporaryDirectory() as evil_out:
        res_clean = subprocess.run(
            ["python3", SCRIPT_PATH, clean_in, clean_out],
            capture_output=True, text=True
        )
        assert res_clean.returncode == 0, f"Script failed on clean corpus:\n{res_clean.stderr}"

        res_evil = subprocess.run(
            ["python3", SCRIPT_PATH, evil_in, evil_out],
            capture_output=True, text=True
        )
        assert res_evil.returncode == 0, f"Script failed on evil corpus:\n{res_evil.stderr}"

        clean_in_files = set(f for f in os.listdir(clean_in) if f.endswith('.log'))
        clean_out_files = set(f for f in os.listdir(clean_out) if f.endswith('.log'))

        missing_clean = clean_in_files - clean_out_files
        assert not missing_clean, f"Clean output is missing files: {missing_clean}"

        modified_clean = []
        for f in clean_in_files:
            in_file = os.path.join(clean_in, f)
            out_file = os.path.join(clean_out, f)
            if not filecmp.cmp(in_file, out_file, shallow=False):
                modified_clean.append(f)

        evil_in_files = set(f for f in os.listdir(evil_in) if f.endswith('.log'))
        evil_out_files = set(f for f in os.listdir(evil_out) if f.endswith('.log'))

        missing_evil = evil_in_files - evil_out_files
        assert not missing_evil, f"Evil output is missing files: {missing_evil}"

        bypassed_evil = []
        for f in evil_in_files:
            out_file = os.path.join(evil_out, f)
            if os.path.exists(out_file) and os.path.getsize(out_file) > 0:
                bypassed_evil.append(f)

        error_msgs = []
        if bypassed_evil:
            error_msgs.append(f"{len(bypassed_evil)} of {len(evil_in_files)} evil bypassed: {', '.join(bypassed_evil)}")
        if modified_clean:
            error_msgs.append(f"{len(modified_clean)} of {len(clean_in_files)} clean modified: {', '.join(modified_clean)}")

        if error_msgs:
            pytest.fail(" | ".join(error_msgs))


def _encoded_line(entry):
    return (json.dumps(entry, separators=(",", ":"), ensure_ascii=True) + "\n").encode("utf-8")


def test_sanitizer_on_generated_mixed_inputs():
    token = uuid.uuid4().hex
    safe_entries = [
        {"url": f"/api/{token}/items", "parameters": {"id": token, "page": "2"}},
        {"url": f"/search?q={token}", "parameters": {"query": f"ordinary value {token}"}},
        {"url": f"/users/{token}", "parameters": {"display": "O'Reilly", "enabled": True}},
    ]
    evil_entries = [
        {"url": f"/api/{token}/../private", "parameters": {"id": token}},
        {"url": f"/download/%2E%2e%2Fsecret-{token}", "parameters": {}},
        {"url": f"/login/{token}", "parameters": {"user": "admin' OR '1'='1"}},
        {"url": f"/report/{token}", "parameters": {"sort": f"x uNiOn SeLeCt password {token}"}},
        {"url": f"/lookup/{token}", "parameters": {"name": f"value--{token}"}},
        {"url": f"/route/{token}\u001fhidden", "parameters": {}},
        {"url": f"/params/{token}", "parameters": {"value": f"before\u0000after-{token}"}},
    ]

    mixed = [(True, e) for e in safe_entries] + [(False, e) for e in evil_entries]
    random.SystemRandom().shuffle(mixed)

    with tempfile.TemporaryDirectory(prefix=f"san-input-{token}-") as input_dir, \
         tempfile.TemporaryDirectory(prefix=f"san-output-{token}-") as output_dir:
        mixed_name = f"mixed-{token}.log"
        evil_name = f"all-bad-{token}.log"
        safe_name = f"all-good-{token}.log"

        mixed_bytes = b"".join(_encoded_line(entry) for _, entry in mixed)
        expected_mixed = b"".join(_encoded_line(entry) for safe, entry in mixed if safe)
        all_evil_bytes = b"".join(_encoded_line(entry) for entry in evil_entries)
        all_safe_bytes = b"".join(_encoded_line(entry) for entry in safe_entries)

        Path(input_dir, mixed_name).write_bytes(mixed_bytes)
        Path(input_dir, evil_name).write_bytes(all_evil_bytes)
        Path(input_dir, safe_name).write_bytes(all_safe_bytes)
        Path(input_dir, f"ignored-{token}.txt").write_text("not a log file\n", encoding="utf-8")

        result = subprocess.run(
            ["python3", SCRIPT_PATH, input_dir, output_dir],
            capture_output=True,
            text=True,
            timeout=30,
        )
        assert result.returncode == 0, f"Script failed on generated corpus:\n{result.stdout}\n{result.stderr}"

        expected = {
            mixed_name: expected_mixed,
            evil_name: b"",
            safe_name: all_safe_bytes,
        }
        for filename, expected_bytes in expected.items():
            output_path = Path(output_dir, filename)
            assert output_path.is_file(), f"Sanitizer did not create output file {filename}"
            assert output_path.read_bytes() == expected_bytes, \
                f"Incorrect filtering or byte preservation in {filename}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
