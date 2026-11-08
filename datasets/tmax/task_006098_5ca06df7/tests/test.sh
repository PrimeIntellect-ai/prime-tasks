#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import shutil
import subprocess
from collections import Counter

STAGED_CONFIGS_DIR = "/home/user/staged_configs"
RAW_CONFIGS_DIR = "/home/user/raw_configs"
STORE_DIR = "/home/user/store"
DEPLOY_DIR = "/home/user/deploy"
LOG_FILE = "/home/user/deployment_report.log"
RUST_PROJECT_DIR = "/home/user/config_deployer"


def expected_transformation(raw):
    output = []
    for line in raw.splitlines(keepends=True):
        if line.endswith(b"\r\n"):
            body, ending = line[:-2], b"\r\n"
        elif line.endswith(b"\n") or line.endswith(b"\r"):
            body, ending = line[:-1], line[-1:]
        else:
            body, ending = line, b""

        if body == b"HOST=localhost":
            body = b"HOST=127.0.0.1"
        elif body == b"DEBUG=true":
            body = b"LOG_LEVEL=debug"
        output.append(body + ending)
    return b"".join(output)


def test_staged_configs_exist_and_transformed():
    assert os.path.exists(STAGED_CONFIGS_DIR), f"Directory {STAGED_CONFIGS_DIR} does not exist."
    assert os.path.isdir(STAGED_CONFIGS_DIR), f"{STAGED_CONFIGS_DIR} is not a directory."

    for i in range(1, 21):
        filename = f"config_{i:02d}.ini"
        raw_path = os.path.join(RAW_CONFIGS_DIR, filename)
        filepath = os.path.join(STAGED_CONFIGS_DIR, filename)
        assert os.path.isfile(raw_path), f"Raw file {raw_path} does not exist."
        assert os.path.exists(filepath), f"File {filepath} does not exist."
        assert os.path.isfile(filepath), f"{filepath} is not a file."

        with open(raw_path, "rb") as f:
            raw_content = f.read()
        with open(filepath, "rb") as f:
            staged_bytes = f.read()

        assert staged_bytes == expected_transformation(raw_content), \
            f"{filepath} does not preserve the raw file with only the required exact-line replacements."

        content = staged_bytes.decode("utf-8")
        assert "HOST=127.0.0.1" in content, f"'HOST=127.0.0.1' missing in {filepath}"
        assert "LOG_LEVEL=debug" in content, f"'LOG_LEVEL=debug' missing in {filepath}"
        assert "HOST=localhost" not in content, f"'HOST=localhost' still present in {filepath}"
        assert "DEBUG=true" not in content, f"'DEBUG=true' still present in {filepath}"


def test_rust_project_exists_and_program_runs():
    assert os.path.exists(RUST_PROJECT_DIR), f"Rust project directory {RUST_PROJECT_DIR} does not exist."
    cargo_toml = os.path.join(RUST_PROJECT_DIR, "Cargo.toml")
    assert os.path.exists(cargo_toml), f"Cargo.toml missing in {RUST_PROJECT_DIR}."

    subprocess.run(
        ["cargo", "build", "--release"],
        cwd=RUST_PROJECT_DIR,
        check=True,
        timeout=120,
    )

    for path in (STORE_DIR, DEPLOY_DIR):
        if os.path.lexists(path):
            if os.path.isdir(path) and not os.path.islink(path):
                shutil.rmtree(path)
            else:
                os.unlink(path)
    if os.path.lexists(LOG_FILE):
        os.unlink(LOG_FILE)

    subprocess.run(
        ["cargo", "run", "--release", "--quiet"],
        cwd=RUST_PROJECT_DIR,
        check=True,
        timeout=120,
    )


def test_deploy_and_store_directories_exist():
    assert os.path.exists(STORE_DIR), f"Directory {STORE_DIR} does not exist."
    assert os.path.isdir(STORE_DIR), f"{STORE_DIR} is not a directory."
    assert os.path.exists(DEPLOY_DIR), f"Directory {DEPLOY_DIR} does not exist."
    assert os.path.isdir(DEPLOY_DIR), f"{DEPLOY_DIR} is not a directory."


def test_hard_links_and_store_files():
    for i in range(1, 21):
        basename = f"config_{i:02d}.ini"
        staged_path = os.path.join(STAGED_CONFIGS_DIR, basename)
        deploy_path = os.path.join(DEPLOY_DIR, basename)

        assert os.path.exists(deploy_path), f"Deployed file {deploy_path} does not exist."

        size = os.path.getsize(staged_path)
        store_filename = f"config_{i:02d}_{size}.ini"
        store_path = os.path.join(STORE_DIR, store_filename)

        assert os.path.exists(store_path), f"Stored file {store_path} does not exist."

        deploy_stat = os.stat(deploy_path)
        store_stat = os.stat(store_path)

        assert deploy_stat.st_ino == store_stat.st_ino, \
            f"{deploy_path} and {store_path} are not hard links (different inodes)."
        assert deploy_stat.st_dev == store_stat.st_dev, \
            f"{deploy_path} and {store_path} are not on the same filesystem."

        with open(staged_path, "rb") as f:
            staged_content = f.read()
        with open(store_path, "rb") as f:
            store_content = f.read()
        with open(deploy_path, "rb") as f:
            deploy_content = f.read()

        assert store_content == staged_content, \
            f"Stored file {store_path} does not equal staged file {staged_path}."
        assert deploy_content == staged_content, \
            f"Deployed file {deploy_path} does not equal staged file {staged_path}."


def test_deployment_report_log():
    assert os.path.exists(LOG_FILE), f"Log file {LOG_FILE} does not exist."

    with open(LOG_FILE, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 20, f"Expected 20 lines in {LOG_FILE}, found {len(lines)}."

    pattern = re.compile(r"^LINKED config_\d{2}\.ini -> store/config_\d{2}_\d+\.ini$")
    for line in lines:
        assert pattern.match(line), f"Log line format incorrect: '{line}'"

    expected_lines = []
    for i in range(1, 21):
        basename = f"config_{i:02d}.ini"
        size = os.path.getsize(os.path.join(STAGED_CONFIGS_DIR, basename))
        expected_lines.append(
            f"LINKED {basename} -> store/config_{i:02d}_{size}.ini"
        )

    assert Counter(lines) == Counter(expected_lines), \
        "Deployment report does not contain exactly one correct entry for every staged file."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
