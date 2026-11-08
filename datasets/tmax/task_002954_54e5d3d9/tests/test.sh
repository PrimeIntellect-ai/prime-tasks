#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib
import importlib.machinery
import importlib.util
import json
import os
import runpy
import secrets
import shutil
import string
import subprocess
import sys
from pathlib import Path

import pytest

PROJECT = Path("/home/user/fastparser_ext")
SCRIPT = Path("/home/user/test_api.py")
OUTPUT = Path("/home/user/parsed_output.json")
REQUIRED_INPUT = "INIT_CONN|FETCH_RECORDS|UPDATE_STATE|TERMINATE|"
EXPECTED_OUTPUT = ["INIT_CONN", "FETCH_RECORDS", "UPDATE_STATE", "TERMINATE"]


def test_pyproject_toml_fixed():
    path = PROJECT / "pyproject.toml"
    assert path.is_file(), f"File {path} does not exist."

    content = path.read_text(encoding="utf-8")
    assert "setuptools-rust" in content, (
        f"The build-system requires in {path} does not seem to include 'setuptools-rust'."
    )

    import tomllib
    config = tomllib.loads(content)
    requirements = config.get("build-system", {}).get("requires", [])
    assert any(str(req).lower().replace("_", "-").startswith("setuptools-rust") for req in requirements), (
        "'setuptools-rust' must be an actual build-system requirement in pyproject.toml."
    )


def test_clean_build_and_install():
    assert (PROJECT / "src" / "lib.rs").is_file(), "The Rust source file is missing."

    for directory in (PROJECT / "target", PROJECT / "build"):
        shutil.rmtree(directory, ignore_errors=True)
    for directory in PROJECT.glob("*.egg-info"):
        shutil.rmtree(directory, ignore_errors=True)
    for path in PROJECT.rglob("*"):
        if path.is_file() and any(path.name.endswith(s) for s in importlib.machinery.EXTENSION_SUFFIXES):
            path.unlink()

    result = subprocess.run(
        [sys.executable, "-m", "pip", "install", "--force-reinstall", "--no-cache-dir", str(PROJECT)],
        cwd="/tmp",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    assert result.returncode == 0, f"A clean build/install of fastparser failed:\n{result.stdout}"


def test_fastparser_installed_and_native_parser_works():
    spec = importlib.util.find_spec("fastparser")
    assert spec is not None, "The 'fastparser' module is not installed in the Python environment."
    assert spec.origin, "The installed fastparser module has no loadable origin."
    assert any(spec.origin.endswith(s) for s in importlib.machinery.EXTENSION_SUFFIXES), (
        f"fastparser must be the compiled extension, not a Python stub; loaded origin was {spec.origin!r}."
    )

    fastparser = importlib.import_module("fastparser")
    parser = getattr(fastparser, "parse_custom_protocol", None)
    assert callable(parser), "The compiled module does not expose parse_custom_protocol."

    alphabet = string.ascii_uppercase + string.digits
    for count, trailing in ((1, False), (2, True), (5, False), (7, True)):
        tokens = [
            "T" + "".join(secrets.choice(alphabet) for _ in range(18))
            for _ in range(count)
        ]
        protocol = "|".join(tokens) + ("|" if trailing else "")
        assert parser(protocol) == tokens, (
            f"parse_custom_protocol returned the wrong tokens for {protocol!r}."
        )

    assert parser("") == []
    assert parser(REQUIRED_INPUT) == EXPECTED_OUTPUT


def test_test_api_script_exists():
    assert SCRIPT.is_file(), f"File {SCRIPT} does not exist. You were supposed to write a script here."


def test_parsed_output_json():
    fastparser = importlib.import_module("fastparser")
    real_parser = fastparser.parse_custom_protocol
    calls = []

    def recording_parser(value):
        calls.append(value)
        return real_parser(value)

    if OUTPUT.exists():
        OUTPUT.unlink()

    old_cwd = os.getcwd()
    fastparser.parse_custom_protocol = recording_parser
    try:
        os.chdir("/tmp")
        runpy.run_path(str(SCRIPT), run_name="__main__")
    finally:
        os.chdir(old_cwd)
        fastparser.parse_custom_protocol = real_parser

    assert REQUIRED_INPUT in calls, (
        "test_api.py did not call fastparser.parse_custom_protocol with the required API response."
    )
    assert OUTPUT.is_file(), f"File {OUTPUT} does not exist. Did your script run and create it?"

    try:
        with OUTPUT.open("r", encoding="utf-8") as f:
            data = json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"File {OUTPUT} is not valid JSON.")

    assert data == EXPECTED_OUTPUT, (
        f"The parsed output in {OUTPUT} is incorrect.\n"
        f"Expected: {EXPECTED_OUTPUT}\n"
        f"Got: {data}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
