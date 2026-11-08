#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import re
import shutil
import stat
import subprocess
import tempfile

import pytest

BINARY = "/home/user/src/audit_processor"
SOURCE = "/home/user/src/audit_processor.cpp"
SCRIPT = "/home/user/deploy.sh"
DEPLOY_ROOT = "/home/user/deploy"
LOG = "/home/user/deploy.log"
EXPECTED_LOG = "Staging: SUCCESS\nProd: SUCCESS\n"


def run_binary(binary, args):
    return subprocess.run([binary] + args, capture_output=True, text=True, timeout=10)


def assert_binary_logic(binary):
    with tempfile.NamedTemporaryFile() as secure_file:
        os.chmod(secure_file.name, 0o600)
        result = run_binary(binary, [secure_file.name])
        assert result.returncode == 0, f"Expected exit code 0 for 0600 file, got {result.returncode}"
        assert result.stdout.strip() == "SECURE", f"Expected 'SECURE' output, got '{result.stdout.strip()}'"

    for mode in (0o000, 0o400, 0o644, 0o601, 0o660, 0o1600):
        with tempfile.NamedTemporaryFile() as insecure_file:
            os.chmod(insecure_file.name, mode)
            result = run_binary(binary, [insecure_file.name])
            assert result.returncode == 1, f"Expected exit code 1 for mode {mode:o}, got {result.returncode}"
            assert result.stdout.strip() == "INSECURE", (
                f"Expected 'INSECURE' for mode {mode:o}, got '{result.stdout.strip()}'"
            )

    missing = "/tmp/does_not_exist_xyz123"
    try:
        os.unlink(missing)
    except FileNotFoundError:
        pass
    result_missing = run_binary(binary, [missing])
    assert result_missing.returncode == 1, "Expected exit code 1 for missing file."
    assert (result_missing.stdout + result_missing.stderr).strip(), "Missing file must print an error."

    result_no_args = run_binary(binary, [])
    assert result_no_args.returncode == 1, "Expected exit code 1 when no path is provided."
    assert (result_no_args.stdout + result_no_args.stderr).strip(), "Wrong argument count must print an error."

    with tempfile.NamedTemporaryFile() as first, tempfile.NamedTemporaryFile() as second:
        os.chmod(first.name, 0o600)
        os.chmod(second.name, 0o600)
        result_two_args = run_binary(binary, [first.name, second.name])
    assert result_two_args.returncode == 1, "Expected exit code 1 when two paths are provided."
    assert (result_two_args.stdout + result_two_args.stderr).strip(), "Wrong argument count must print an error."


def assert_deployed_state():
    assert os.path.isfile(LOG), f"Log file {LOG} does not exist."
    with open(LOG, "r") as f:
        content = f.read().strip()
    expected = "Staging: SUCCESS\nProd: SUCCESS"
    assert content == expected, f"Log content mismatch. Expected:\n{expected}\nGot:\n{content}"

    source_bytes = open(BINARY, "rb").read()
    for env in ("staging", "prod_a", "prod_b"):
        directory = os.path.join(DEPLOY_ROOT, env)
        assert os.path.isdir(directory), f"Directory {directory} does not exist."

        bin_path = os.path.join(directory, "audit_processor")
        cfg_path = os.path.join(directory, "config.txt")

        assert os.path.isfile(bin_path), f"Binary missing in {env}: {bin_path}"
        assert stat.S_IMODE(os.stat(bin_path).st_mode) == 0o500, f"Binary in {env} must have 0500 permissions."
        with open(bin_path, "rb") as f:
            assert f.read() == source_bytes, f"Binary in {env} was not copied from {BINARY}."

        assert os.path.isfile(cfg_path), f"Config missing in {env}: {cfg_path}"
        assert stat.S_IMODE(os.stat(cfg_path).st_mode) == 0o600, f"Config in {env} must have 0600 permissions."
        with open(cfg_path, "r") as f:
            cfg_content = f.read().strip()
        assert cfg_content == "v1", f"Config in {env} must contain 'v1'."


def deployment_snapshot():
    result = {}
    for env in ("staging", "prod_a", "prod_b"):
        for name in ("audit_processor", "config.txt"):
            path = os.path.join(DEPLOY_ROOT, env, name)
            with open(path, "rb") as f:
                data = f.read()
            result[path] = (hashlib.sha256(data).hexdigest(), stat.S_IMODE(os.stat(path).st_mode))
    with open(LOG, "rb") as f:
        result[LOG] = hashlib.sha256(f.read()).hexdigest()
    return result


def test_01_binary_exists_and_executable():
    assert os.path.isfile(BINARY), f"Binary {BINARY} does not exist."
    assert os.access(BINARY, os.X_OK), f"Binary {BINARY} is not executable."
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", "audit_processor must be a compiled executable."


def test_02_source_uses_stat_and_builds():
    assert os.path.isfile(SOURCE), f"Source file {SOURCE} does not exist."
    source_text = open(SOURCE, "r").read()
    assert re.search(r"(?<![A-Za-z0-9_])(?:::)?stat\s*\(", source_text), (
        "The C++ source must call the stat system call."
    )

    with tempfile.TemporaryDirectory() as td:
        rebuilt = os.path.join(td, "audit_processor")
        build = subprocess.run(
            ["g++", SOURCE, "-o", rebuilt], capture_output=True, text=True, timeout=30
        )
        assert build.returncode == 0, f"The submitted C++ source does not compile with g++:\n{build.stderr}"
        assert_binary_logic(rebuilt)


def test_03_binary_logic():
    assert_binary_logic(BINARY)


def test_04_deploy_script_executes_gates_and_is_idempotent():
    assert os.path.isfile(SCRIPT), f"Deploy script {SCRIPT} does not exist."
    assert os.access(SCRIPT, os.X_OK), f"Deploy script {SCRIPT} is not executable."

    original_binary = open(BINARY, "rb").read()
    original_mode = stat.S_IMODE(os.stat(BINARY).st_mode)
    marker = "/tmp/audit_staging_execution_marker"
    shutil.rmtree(DEPLOY_ROOT, ignore_errors=True)
    for path in (LOG, marker):
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass

    fake = (
        "#!/bin/sh\n"
        f"printf '%s' \"$0\" > {marker}\n"
        "printf 'INSECURE\\n'\n"
        "exit 1\n"
    ).encode()

    try:
        with open(BINARY, "wb") as f:
            f.write(fake)
        os.chmod(BINARY, 0o755)

        subprocess.run([SCRIPT], capture_output=True, text=True, timeout=30)

        assert os.path.isfile(marker), "deploy.sh did not execute the staged audit_processor."
        with open(marker, "r") as f:
            executed_as = f.read()
        assert executed_as == "/home/user/deploy/staging/audit_processor", (
            "The audit check must be run through the binary copied into staging."
        )

        for env in ("staging", "prod_a", "prod_b"):
            assert os.path.isdir(os.path.join(DEPLOY_ROOT, env)), f"deploy.sh did not create {env}."
        for env in ("prod_a", "prod_b"):
            assert not os.path.exists(os.path.join(DEPLOY_ROOT, env, "audit_processor")), (
                f"deploy.sh rolled out to {env} even though staging returned INSECURE."
            )
            assert not os.path.exists(os.path.join(DEPLOY_ROOT, env, "config.txt")), (
                f"deploy.sh created the {env} config even though staging returned INSECURE."
            )
        if os.path.exists(LOG):
            assert open(LOG, "r").read().strip() != "Staging: SUCCESS\nProd: SUCCESS", (
                "deploy.sh logged success even though staging returned INSECURE."
            )
    finally:
        with open(BINARY, "wb") as f:
            f.write(original_binary)
        os.chmod(BINARY, original_mode)

    # Seed incorrect existing state. A real deployment run must overwrite it.
    for env in ("staging", "prod_a", "prod_b"):
        directory = os.path.join(DEPLOY_ROOT, env)
        os.makedirs(directory, exist_ok=True)
        with open(os.path.join(directory, "audit_processor"), "wb") as f:
            f.write(b"stale binary")
        os.chmod(os.path.join(directory, "audit_processor"), 0o777)
        with open(os.path.join(directory, "config.txt"), "w") as f:
            f.write("old configuration\n")
        os.chmod(os.path.join(directory, "config.txt"), 0o666)
    with open(LOG, "w") as f:
        f.write("old log entry that must be overwritten\n")

    first = subprocess.run([SCRIPT], capture_output=True, text=True, timeout=30)
    assert first.returncode == 0, f"deploy.sh failed during a valid rollout:\n{first.stderr}"
    assert_deployed_state()
    first_snapshot = deployment_snapshot()

    # A second run must overwrite rather than append to the log and produce the same state.
    with open(LOG, "w") as f:
        f.write("sentinel that must not survive\n")
    second = subprocess.run([SCRIPT], capture_output=True, text=True, timeout=30)
    assert second.returncode == 0, f"deploy.sh failed on its second run:\n{second.stderr}"
    assert_deployed_state()
    assert deployment_snapshot() == first_snapshot, "Repeated deployment did not produce the same final state."


def test_05_deploy_script_exists():
    assert os.path.isfile(SCRIPT), f"Deploy script {SCRIPT} does not exist."


def test_06_deploy_log():
    assert os.path.isfile(LOG), f"Log file {LOG} does not exist."
    with open(LOG, "r") as f:
        content = f.read().strip()
    expected = "Staging: SUCCESS\nProd: SUCCESS"
    assert content == expected, f"Log content mismatch. Expected:\n{expected}\nGot:\n{content}"


def test_07_deploy_directories():
    dirs = [
        "/home/user/deploy/staging",
        "/home/user/deploy/prod_a",
        "/home/user/deploy/prod_b",
    ]
    for directory in dirs:
        assert os.path.isdir(directory), f"Directory {directory} does not exist."


def test_08_deployed_files_permissions_and_content():
    envs = ["staging", "prod_a", "prod_b"]
    for env in envs:
        bin_path = f"/home/user/deploy/{env}/audit_processor"
        cfg_path = f"/home/user/deploy/{env}/config.txt"

        assert os.path.isfile(bin_path), f"Binary missing in {env}: {bin_path}"
        st_bin = os.stat(bin_path)
        assert stat.S_IMODE(st_bin.st_mode) == 0o500, f"Binary in {env} must have 0500 permissions."

        assert os.path.isfile(cfg_path), f"Config missing in {env}: {cfg_path}"
        st_cfg = os.stat(cfg_path)
        assert stat.S_IMODE(st_cfg.st_mode) == 0o600, f"Config in {env} must have 0600 permissions."

        with open(cfg_path, "r") as f:
            content = f.read().strip()
        assert content == "v1", f"Config in {env} must contain 'v1'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
