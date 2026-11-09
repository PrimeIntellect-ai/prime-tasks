#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import secrets
import string
import subprocess
from pathlib import Path

import pytest

PROJECT = Path("/home/user/dropper")
CARGO_TOML = PROJECT / "Cargo.toml"
GUARD = Path("/home/user/guard.bin")
ENCRYPTED = Path("/home/user/encrypted.dat")
EXFIL = Path("/home/user/exfil.txt")


def build_dropper():
    assert CARGO_TOML.is_file(), f"Rust project not found. Expected Cargo.toml at {CARGO_TOML}"
    rust_sources = list(PROJECT.rglob("*.rs"))
    assert rust_sources, "Rust project contains no .rs source files"

    metadata_result = subprocess.run(
        ["cargo", "metadata", "--format-version=1", "--no-deps"],
        cwd=PROJECT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=60,
    )
    assert metadata_result.returncode == 0, metadata_result.stderr
    metadata = json.loads(metadata_result.stdout)
    root_manifest = str(CARGO_TOML.resolve())
    root_packages = [p for p in metadata["packages"] if str(Path(p["manifest_path"]).resolve()) == root_manifest]
    assert len(root_packages) == 1, "Could not identify the root Cargo package"
    root_package = root_packages[0]

    build_result = subprocess.run(
        ["cargo", "build", "--bins", "--message-format=json-render-diagnostics"],
        cwd=PROJECT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=180,
    )
    assert build_result.returncode == 0, build_result.stdout + build_result.stderr

    artifacts = []
    for line in build_result.stdout.splitlines():
        try:
            message = json.loads(line)
        except json.JSONDecodeError:
            continue
        if (message.get("reason") == "compiler-artifact"
                and message.get("package_id") == root_package["id"]
                and "bin" in message.get("target", {}).get("kind", [])
                and message.get("executable")):
            artifacts.append(message)

    assert artifacts, "Cargo did not produce a binary executable"
    default_run = root_package.get("default_run")
    if default_run:
        artifacts = [a for a in artifacts if a["target"]["name"] == default_run]
    assert len(artifacts) == 1, "Project must have one runnable binary or set package.default-run"

    executable = Path(artifacts[0]["executable"])
    assert executable.is_file(), f"Built executable does not exist: {executable}"
    assert executable.read_bytes()[:4] == b"\x7fELF", "Built dropper is not an ELF executable"
    return executable


def make_guard(key: bytes):
    assert len(key) == 16
    pad_len = random.randint(17, 511)
    source = f'''#include <stdio.h>
__attribute__((used)) const unsigned char padding[{pad_len}] = {{1}};
__attribute__((used)) const unsigned char secret_key[] = "KEY_START:{key.decode('ascii')}";
int main(void) {{ puts("benign guard"); return 0; }}
'''
    source_path = Path("/tmp/verifier_guard.c")
    output_path = Path("/tmp/verifier_guard.bin")
    source_path.write_text(source, encoding="utf-8")
    result = subprocess.run(
        ["gcc", "-O0", "-fno-toplevel-reorder", str(source_path), "-o", str(output_path)],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=60,
    )
    assert result.returncode == 0, result.stderr
    data = output_path.read_bytes()
    marker = b"KEY_START:" + key
    assert marker in data, "Verifier failed to construct guard ELF"
    GUARD.write_bytes(data)
    GUARD.chmod(0o755)


def install_case(key: bytes, script: bytes):
    make_guard(key)
    ciphertext = bytes(value ^ key[index % len(key)] for index, value in enumerate(script))
    ENCRYPTED.write_bytes(ciphertext)


def run_dropper(executable: Path, extra_environment=None):
    if EXFIL.exists():
        EXFIL.unlink()
    environment = os.environ.copy()
    environment["USER"] = "verifier-host-user"
    environment["HOME"] = "/verifier/host/home"
    if extra_environment:
        environment.update(extra_environment)
    result = subprocess.run(
        [str(executable)],
        cwd=PROJECT,
        env=environment,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, f"Dropper failed:\nstdout: {result.stdout}\nstderr: {result.stderr}"
    assert EXFIL.is_file(), f"Output file {EXFIL} does not exist."


EXECUTABLE = build_dropper()
ORIGINAL_FLAG = "FLAG{Ev4s10n_P4yl04d_D3l1v3r3d}"
original_key = b"A1b2C3d4E5f6G7h8"
original_script = f'''#!/bin/bash
if [ "$ISOLATION_MODE" = "active" ]; then
    if [ -z "$USER" ] && [ -z "$HOME" ]; then
        echo "{ORIGINAL_FLAG}"
    else
        echo "FAILED: Environment not fully cleared."
    fi
else
    echo "FAILED: ISOLATION_MODE not active."
fi
'''.encode("utf-8")
install_case(original_key, original_script)
run_dropper(EXECUTABLE)


def test_dropper_project_exists():
    cargo_toml_path = "/home/user/dropper/Cargo.toml"
    assert os.path.isfile(cargo_toml_path), f"Rust project not found. Expected Cargo.toml at {cargo_toml_path}"


def test_exfil_txt_exists():
    exfil_path = "/home/user/exfil.txt"
    assert os.path.isfile(exfil_path), f"Output file {exfil_path} does not exist."


def test_exfil_txt_content():
    exfil_path = "/home/user/exfil.txt"
    assert os.path.isfile(exfil_path), f"Output file {exfil_path} does not exist."
    with open(exfil_path, "r", encoding="utf-8") as f:
        content = f.read().strip()
    expected_flag = "FLAG{Ev4s10n_P4yl04d_D3l1v3r3d}"
    assert content == expected_flag, f"Expected '{expected_flag}' in {exfil_path}, but got '{content}'"


def test_dynamic_extraction_decryption_execution_and_isolation():
    alphabet = string.ascii_letters + string.digits
    key = "".join(secrets.choice(alphabet) for _ in range(16)).encode("ascii")
    inherited_name = "HOST_SECRET_" + "".join(secrets.choice(string.ascii_uppercase) for _ in range(12))
    inherited_value = secrets.token_hex(18)
    left = secrets.randbelow(8000) + 1000
    right = secrets.randbelow(8000) + 1000
    expected = f"RESULT:{left * right + left - right}"
    script = f'''#!/bin/bash
if [ "$ISOLATION_MODE" != "active" ] || [ -n "${{USER+x}}" ] || [ -n "${{HOME+x}}" ] || [ -n "${{{inherited_name}+x}}" ]; then
    echo "FAILED: child environment was not isolated"
    exit 0
fi
left={left}
right={right}
printf 'RESULT:%s\\n' "$((left * right + left - right))"
'''.encode("utf-8")
    install_case(key, script)
    run_dropper(EXECUTABLE, {inherited_name: inherited_value})
    content = EXFIL.read_text(encoding="utf-8").strip()
    assert content == expected, f"Expected dynamically produced output '{expected}', got '{content}'"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
