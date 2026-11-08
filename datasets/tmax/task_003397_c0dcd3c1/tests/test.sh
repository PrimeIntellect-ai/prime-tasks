#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import stat
import subprocess
import tempfile
import uuid
from pathlib import Path

import pytest

EXPECTED_CONFIG = "LOG_DIR=/home/user/custom_logs\nSIZE=5M\nROTATIONS=3\n"


def test_provision_config():
    config_path = "/home/user/provision_config.txt"
    assert os.path.exists(config_path), f"Configuration file {config_path} does not exist."

    with open(config_path, "r") as f:
        content = f.read()

    assert "LOG_DIR=/home/user/custom_logs" in content, f"LOG_DIR not set correctly in {config_path}."
    assert "SIZE=5M" in content, f"SIZE not set correctly in {config_path}."
    assert "ROTATIONS=3" in content, f"ROTATIONS not set correctly in {config_path}."


def test_expect_script_exists():
    script_path = "/home/user/run_init.exp"
    assert os.path.exists(script_path), f"Expect script {script_path} does not exist."
    assert os.path.isfile(script_path), f"Expect script {script_path} is not a regular file."


def test_c_program_and_binary():
    source_path = "/home/user/create_dirs.c"
    binary_path = "/home/user/create_dirs"

    assert os.path.exists(source_path), f"C source file {source_path} does not exist."
    assert os.path.exists(binary_path), f"Compiled binary {binary_path} does not exist."
    assert os.access(binary_path, os.X_OK), f"Binary {binary_path} is not executable."
    assert os.path.isfile(source_path), f"C source file {source_path} is not a regular file."
    assert os.path.isfile(binary_path), f"Compiled binary {binary_path} is not a regular file."
    with open(binary_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{binary_path} is not a compiled ELF binary."


def test_filesystem_setup():
    log_dir = "/home/user/custom_logs"
    log_file = os.path.join(log_dir, "setup.log")

    assert os.path.exists(log_dir), f"Directory {log_dir} does not exist."
    assert os.path.isdir(log_dir), f"{log_dir} is not a directory."

    st = os.stat(log_dir)
    assert stat.S_IMODE(st.st_mode) == 0o755, f"Directory {log_dir} does not have 0755 permissions."

    assert os.path.exists(log_file), f"Log file {log_file} does not exist."
    assert os.path.isfile(log_file), f"{log_file} is not a regular file."


def test_logrotate_config():
    config_path = "/home/user/custom_logrotate.conf"
    assert os.path.exists(config_path), f"Logrotate config {config_path} does not exist."

    with open(config_path, "r") as f:
        content = f.read()

    clean_content = re.sub(r'#.*', '', content)

    assert re.search(r'/home/user/custom_logs/\*\.log\s*\{', clean_content), \
        f"Target pattern '/home/user/custom_logs/*.log' not found or malformed in {config_path}."
    assert re.search(r'\bsize\s+5[Mm]\b', clean_content) or re.search(r'\bmaxsize\s+5[Mm]\b', clean_content) or "5M" in clean_content, \
        f"Size directive (5M) not found in {config_path}."
    assert re.search(r'\brotate\s+3\b', clean_content), f"'rotate 3' not found in {config_path}."
    assert re.search(r'\bmissingok\b', clean_content), f"'missingok' not found in {config_path}."
    assert re.search(r'\bnomail\b', clean_content), f"'nomail' not found in {config_path}."


def test_expect_script_drives_interactive_program():
    init_path = Path("/home/user/init_fs")
    script_path = Path("/home/user/run_init.exp")
    config_path = Path("/home/user/provision_config.txt")
    backup_path = Path(f"/tmp/init_fs.backup.{uuid.uuid4().hex}")
    marker_path = Path(f"/tmp/init_fs.marker.{uuid.uuid4().hex}")

    os.replace(init_path, backup_path)
    probe = f'''#!/usr/bin/env python3
import json
from pathlib import Path
import sys

answers = []
for prompt in ["Enter log directory path: ", "Enter log rotation size limit: ", "Enter number of rotations to keep: "]:
    sys.stdout.write(prompt)
    sys.stdout.flush()
    line = sys.stdin.readline()
    if line == "":
        sys.exit(2)
    answers.append(line.rstrip("\\r\\n"))
Path({str(marker_path)!r}).write_text(json.dumps(answers))
Path("/home/user/provision_config.txt").write_text(
    "LOG_DIR=" + answers[0] + "\\nSIZE=" + answers[1] + "\\nROTATIONS=" + answers[2] + "\\n"
)
print("Configuration saved.")
'''

    try:
        init_path.write_text(probe)
        init_path.chmod(0o755)
        if config_path.exists():
            config_path.unlink()

        result = subprocess.run(
            ["expect", str(script_path)],
            cwd="/home/user",
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=15,
        )
        assert result.returncode == 0, f"Expect script failed against the interactive tool:\n{result.stdout}\n{result.stderr}"
        assert marker_path.exists(), "The expect script did not execute /home/user/init_fs."
        assert json.loads(marker_path.read_text()) == ["/home/user/custom_logs", "5M", "3"], \
            "The expect script did not send the required responses to the three prompts."
        assert config_path.read_text() == EXPECTED_CONFIG, "Interactive execution generated the wrong configuration."
    finally:
        if init_path.exists() or init_path.is_symlink():
            init_path.unlink()
        os.replace(backup_path, init_path)
        if marker_path.exists():
            marker_path.unlink()

    if config_path.exists():
        config_path.unlink()
    result = subprocess.run(
        ["expect", str(script_path)],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=15,
    )
    assert result.returncode == 0, f"Expect script failed with the real init_fs:\n{result.stdout}\n{result.stderr}"
    assert config_path.read_text() == EXPECTED_CONFIG, "The real init_fs did not generate the required configuration."


def _exercise_create_dirs(binary):
    config_path = Path("/home/user/provision_config.txt")
    with tempfile.TemporaryDirectory(prefix="verify_create_dirs_") as tmp:
        tmp_path = Path(tmp)
        target = tmp_path / "logs"
        config_path.write_text(f"SIZE=9M\nLOG_DIR={target}\nROTATIONS=8\n")

        result = subprocess.run([binary], text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10)
        assert result.returncode == 0, f"{binary} failed to create a valid configured directory: {result.stdout} {result.stderr}"
        assert target.is_dir(), f"{binary} did not parse LOG_DIR and create the configured directory."
        assert stat.S_IMODE(target.stat().st_mode) == 0o755, f"{binary} did not create the directory with mode 0755."
        setup_log = target / "setup.log"
        assert setup_log.is_file(), f"{binary} did not create setup.log in the configured directory."
        assert setup_log.stat().st_size == 0, f"{binary} did not create an empty setup.log."

        result = subprocess.run([binary], text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10)
        assert result.returncode == 0, f"{binary} did not gracefully accept an already-existing directory."

        impossible = tmp_path / "missing-parent" / "logs"
        config_path.write_text(f"LOG_DIR={impossible}\n")
        result = subprocess.run([binary], text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10)
        assert result.returncode != 0, f"{binary} reported success when mkdir failed."
        assert (result.stdout + result.stderr).strip(), f"{binary} did not print an error when mkdir failed."
        assert not impossible.exists(), f"{binary} unexpectedly created missing parent directories."

        config_path.write_text("SIZE=5M\nROTATIONS=3\n")
        result = subprocess.run([binary], text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10)
        assert result.returncode != 0, f"{binary} reported success without a LOG_DIR entry."
        assert (result.stdout + result.stderr).strip(), f"{binary} did not report the missing LOG_DIR entry."


def test_c_source_compiles_and_both_binaries_work():
    source = "/home/user/create_dirs.c"
    submitted_binary = "/home/user/create_dirs"
    config_path = Path("/home/user/provision_config.txt")

    with tempfile.TemporaryDirectory(prefix="verify_compile_") as tmp:
        rebuilt = os.path.join(tmp, "create_dirs_rebuilt")
        compile_result = subprocess.run(
            ["gcc", source, "-o", rebuilt],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=20,
        )
        assert compile_result.returncode == 0, f"create_dirs.c does not compile with gcc:\n{compile_result.stderr}"

        try:
            _exercise_create_dirs(rebuilt)
            _exercise_create_dirs(submitted_binary)
        finally:
            config_path.write_text(EXPECTED_CONFIG)

    result = subprocess.run([submitted_binary], text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10)
    assert result.returncode == 0, f"Submitted create_dirs failed for the required final configuration: {result.stdout} {result.stderr}"
    final_dir = Path("/home/user/custom_logs")
    assert final_dir.is_dir()
    assert stat.S_IMODE(final_dir.stat().st_mode) == 0o755
    assert (final_dir / "setup.log").is_file()


def test_logrotate_accepts_and_interprets_configuration():
    config_path = "/home/user/custom_logrotate.conf"
    with tempfile.TemporaryDirectory(prefix="verify_logrotate_") as tmp:
        state_path = os.path.join(tmp, "state")
        result = subprocess.run(
            ["logrotate", "--debug", "--state", state_path, config_path],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=15,
        )
    output = result.stdout + "\n" + result.stderr
    assert result.returncode == 0, f"logrotate rejected the configuration:\n{output}"

    normalized = re.sub(r"\s+", " ", output)
    pattern_pos = normalized.find("rotating pattern: /home/user/custom_logs/*.log")
    assert pattern_pos != -1, f"logrotate did not load the required log pattern:\n{output}"
    stanza_report = normalized[pattern_pos:pattern_pos + 300]
    assert "5242880 bytes" in stanza_report, f"logrotate did not interpret the required stanza as size 5M:\n{output}"
    assert "(3 rotations)" in stanza_report, f"logrotate did not interpret the required stanza as keeping 3 rotations:\n{output}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
