#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import importlib.metadata
import json
import os
import random
import re
import secrets
import shutil
import subprocess
import tempfile

import pytest

SCRIPT = "/home/user/process_configs.sh"


def test_yq_fixed():
    """Verify the vendored yq source was repaired, installed, and actually works."""
    try:
        result = subprocess.run(["yq", "--version"], capture_output=True, text=True, check=True)
    except FileNotFoundError:
        pytest.fail("yq executable not found in PATH.")
    except subprocess.CalledProcessError as e:
        pytest.fail(f"yq failed to run. It may not be fixed correctly. Stderr: {e.stderr}")

    assert result.stdout.strip() or result.stderr.strip(), "yq --version produced no version output"
    assert importlib.metadata.version("yq") == "3.2.2", "The vendored yq package was not installed"

    source = "/app/yq/yq/__init__.py"
    assert os.path.isfile(source), "Vendored yq source is missing"
    with open(source, encoding="utf-8") as f:
        source_text = f.read()
    assert "import argparse" in source_text, "The argparse import in vendored yq was not repaired"
    assert "argaprse" not in source_text, "The deliberate yq import corruption remains"

    functional = subprocess.run(
        ["yq", "-r", ".service.port"],
        input='service:\n  port: 4317\n',
        capture_output=True,
        text=True,
    )
    assert functional.returncode == 0, f"Installed yq cannot parse YAML: {functional.stderr}"
    assert functional.stdout.strip() == "4317", "Installed yq returned an incorrect parsed value"


def test_script_exists_and_executable():
    """Verify the ingestion script exists and is executable."""
    assert os.path.isfile(SCRIPT), f"Script {SCRIPT} does not exist."
    assert os.access(SCRIPT, os.X_OK), f"Script {SCRIPT} is not executable."


def test_adversarial_corpus():
    """Preserve the original fixed-corpus assertions."""
    clean_dir = "/app/corpus/clean"
    evil_dir = "/app/corpus/evil"

    assert os.path.isdir(clean_dir), f"Clean corpus dir {clean_dir} missing."
    assert os.path.isdir(evil_dir), f"Evil corpus dir {evil_dir} missing."

    with tempfile.TemporaryDirectory() as input_dir, tempfile.TemporaryDirectory() as output_dir:
        clean_files = os.listdir(clean_dir)
        evil_files = os.listdir(evil_dir)

        for f in clean_files:
            shutil.copy(os.path.join(clean_dir, f), os.path.join(input_dir, f"a_clean_{f}"))
        for f in evil_files:
            shutil.copy(os.path.join(evil_dir, f), os.path.join(input_dir, f"z_evil_{f}"))

        result = subprocess.run(["bash", SCRIPT, input_dir, output_dir], capture_output=True, text=True)
        assert result.returncode == 0, (
            f"Script failed with return code {result.returncode}.\n"
            f"Stdout: {result.stdout}\nStderr: {result.stderr}"
        )

        output_files = set(os.listdir(output_dir))
        bypassed_evil = [f for f in evil_files if f"z_evil_{f}" in output_files]
        modified_clean = [f for f in clean_files if f"a_clean_{f}" not in output_files]

        errors = []
        if bypassed_evil:
            errors.append(f"{len(bypassed_evil)} of {len(evil_files)} evil bypassed: {', '.join(bypassed_evil)}")
        if modified_clean:
            errors.append(f"{len(modified_clean)} of {len(clean_files)} clean modified/rejected: {', '.join(modified_clean)}")
        if errors:
            pytest.fail(" | ".join(errors))


def make_wrapper(directory):
    wrapper = os.path.join(directory, "make")
    code = r'''#!/usr/bin/env python3
import json
import os
import shutil
import sys

args = sys.argv[1:]
with open(os.environ["MAKE_AUDIT_ARGS"], "w", encoding="utf-8") as f:
    json.dump(args, f)

workdir = os.getcwd()
makefile = None
i = 0
while i < len(args):
    arg = args[i]
    if arg in ("-C", "--directory") and i + 1 < len(args):
        workdir = os.path.abspath(os.path.join(workdir, args[i + 1]))
        i += 2
        continue
    if arg.startswith("--directory="):
        workdir = os.path.abspath(os.path.join(workdir, arg.split("=", 1)[1]))
    if arg in ("-f", "--file", "--makefile") and i + 1 < len(args):
        makefile = args[i + 1]
        i += 2
        continue
    if arg.startswith("--file=") or arg.startswith("--makefile="):
        makefile = arg.split("=", 1)[1]
    elif arg.startswith("-f") and len(arg) > 2:
        makefile = arg[2:]
    i += 1

candidates = []
if makefile and makefile != "-":
    candidates.append(makefile if os.path.isabs(makefile) else os.path.join(workdir, makefile))
else:
    candidates.extend(os.path.join(workdir, name) for name in ("GNUmakefile", "makefile", "Makefile"))
for candidate in candidates:
    if os.path.isfile(candidate):
        shutil.copyfile(candidate, os.environ["MAKE_AUDIT_FILE"])
        break

if os.environ.get("MAKE_AUDIT_NOOP") == "1":
    sys.exit(0)
os.execv("/usr/bin/make", ["make"] + args)
'''
    with open(wrapper, "w", encoding="utf-8") as f:
        f.write(code)
    os.chmod(wrapper, 0o755)
    return wrapper


def forbidden(data):
    text = data.decode("utf-8")
    return bool(
        re.search(r"evil_directive:\S+", text)
        or re.search(r"password:[ \t]*[A-Za-z0-9]+$", text, re.MULTILINE)
    )


def expected_files(files):
    seen = set()
    expected = {}
    for name in sorted(files):
        data = files[name]
        digest = hashlib.sha256(data).digest()
        if digest in seen:
            continue
        seen.add(digest)
        if not forbidden(data):
            expected[name] = data
    return expected


def test_randomized_rules_and_make_dag():
    """Exercise unpredictable names/content and prove output work is performed through make -j4."""
    nonce = secrets.token_hex(12)
    duplicate = f"shared:\n  token: {nonce}\n  enabled: true\n".encode()
    payloads = [
        duplicate,
        duplicate,
        f'{{"node":"{nonce}","port":{random.randint(1000, 9000)}}}\n'.encode(),
        f"service:\n  id: {nonce}\n  evil_directive:payload_{nonce}\n".encode(),
        f"database:\n  user: u{nonce}\n  password: AbC{random.randint(10000,99999)}\n".encode(),
        f"near_miss:\n  evil_directive: spaced value {nonce}\n".encode(),
        f"near_miss:\n  password: abc-{nonce}\n".encode(),
        f'{{"quoted":"password: secret_{nonce}","ok":true}}\n'.encode(),
    ]

    names = []
    while len(names) < len(payloads):
        ext = ".yaml" if len(names) % 2 == 0 else ".json"
        candidate = secrets.token_hex(7) + ext
        if candidate not in names:
            names.append(candidate)
    random.shuffle(names)
    files = dict(zip(names, payloads))
    expected = expected_files(files)

    with tempfile.TemporaryDirectory() as root:
        input_dir = os.path.join(root, "incoming-" + secrets.token_hex(5))
        output_noop = os.path.join(root, "noop-output")
        output_real = os.path.join(root, "real-output")
        bin_dir = os.path.join(root, "bin")
        os.makedirs(input_dir)
        os.makedirs(output_noop)
        os.makedirs(output_real)
        os.makedirs(bin_dir)
        make_wrapper(bin_dir)

        for name, data in files.items():
            with open(os.path.join(input_dir, name), "wb") as f:
                f.write(data)

        args_log = os.path.join(root, "make-args.json")
        makefile_log = os.path.join(root, "captured-Makefile")
        env = os.environ.copy()
        env["PATH"] = bin_dir + os.pathsep + env["PATH"]
        env["MAKE_AUDIT_ARGS"] = args_log
        env["MAKE_AUDIT_FILE"] = makefile_log
        env["MAKE_AUDIT_NOOP"] = "1"

        noop = subprocess.run(["bash", SCRIPT, input_dir, output_noop], env=env, capture_output=True, text=True)
        assert noop.returncode == 0, f"Script failed during DAG probe: {noop.stdout}\n{noop.stderr}"
        assert os.path.isfile(args_log), "The script did not invoke make through PATH"
        with open(args_log, encoding="utf-8") as f:
            make_args = json.load(f)
        assert "-j4" in make_args, f"make was not invoked with the required -j4 argument: {make_args}"
        assert os.path.isfile(makefile_log), "No generated Makefile was available when make was invoked"
        assert not (set(os.listdir(output_noop)) & set(expected)), (
            "Expected outputs were produced even though make recipes were not run; processing is not orchestrated by the DAG"
        )

        with open(makefile_log, encoding="utf-8", errors="replace") as f:
            makefile_text = f.read()
        assert re.search(r"^[^#\n][^\n]*:", makefile_text, re.MULTILINE), "Generated Makefile has no targets"
        assert input_dir in makefile_text or any(name in makefile_text for name in files), (
            "Generated Makefile does not reference the randomized input corpus"
        )

        env.pop("MAKE_AUDIT_NOOP")
        real = subprocess.run(["bash", SCRIPT, input_dir, output_real], env=env, capture_output=True, text=True)
        assert real.returncode == 0, (
            f"Script failed on randomized corpus with return code {real.returncode}.\n"
            f"Stdout: {real.stdout}\nStderr: {real.stderr}"
        )

        actual_names = set(os.listdir(output_real))
        assert actual_names == set(expected), (
            f"Wrong randomized output set. Expected {sorted(expected)}, got {sorted(actual_names)}"
        )
        for name, data in expected.items():
            with open(os.path.join(output_real, name), "rb") as f:
                assert f.read() == data, f"Output file {name} was modified"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
