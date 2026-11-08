#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import re
import secrets
import stat
import subprocess
import tempfile

SANITIZER = "/home/user/sanitizer"
SOURCE = "/home/user/sanitizer.cpp"
PROCESS_SCRIPT = "/home/user/process_logs.sh"
LOG_FILE = "/home/user/alerts/sanitized_ssh.log"


def run_filter(input_data):
    result = subprocess.run(
        [SANITIZER], input=input_data, text=True, capture_output=True, timeout=10
    )
    assert result.returncode == 0, f"Sanitizer exited with {result.returncode}: {result.stderr}"
    return result.stdout


def test_sanitizer_artifacts_exist():
    assert os.path.isfile(SOURCE), f"Sanitizer source not found at {SOURCE}"
    assert os.path.isfile(SANITIZER), f"Sanitizer binary not found at {SANITIZER}"
    assert os.access(SANITIZER, os.X_OK), "Sanitizer is not executable"


def test_sanitizer_evil_corpus():
    sanitizer_path = SANITIZER
    assert os.path.exists(sanitizer_path), "Sanitizer binary not found at /home/user/sanitizer"
    assert os.access(sanitizer_path, os.X_OK), "Sanitizer is not executable"

    evil_files = glob.glob("/app/corpus/evil/*")
    assert len(evil_files) > 0, "No evil corpus files found"

    bypassed_files = []
    for filepath in evil_files:
        with open(filepath, "r") as f:
            input_data = f.read()

        result = subprocess.run([sanitizer_path], input=input_data, text=True, capture_output=True)
        if result.stdout.strip() != "":
            bypassed_files.append(os.path.basename(filepath))

    if bypassed_files:
        assert False, f"{len(bypassed_files)} of {len(evil_files)} evil bypassed: {', '.join(bypassed_files)}"


def test_sanitizer_clean_corpus():
    sanitizer_path = SANITIZER
    assert os.path.exists(sanitizer_path), "Sanitizer binary not found at /home/user/sanitizer"
    assert os.access(sanitizer_path, os.X_OK), "Sanitizer is not executable"

    clean_files = glob.glob("/app/corpus/clean/*")
    assert len(clean_files) > 0, "No clean corpus files found"

    modified_files = []
    for filepath in clean_files:
        with open(filepath, "r") as f:
            input_data = f.read()

        result = subprocess.run([sanitizer_path], input=input_data, text=True, capture_output=True)
        if result.stdout != input_data:
            modified_files.append(os.path.basename(filepath))

    if modified_files:
        assert False, f"{len(modified_files)} of {len(clean_files)} clean modified: {', '.join(modified_files)}"


def test_sanitizer_randomized_behavior():
    token = secrets.token_hex(16)
    clean = [
        f"Sep 11 01:02:03|203.0.113.9|publickey|Accepted|SHA256:{token}",
        f"Sep 11 01:02:04|203.0.113.10|password|Failed|NONE;${token}&x>y<z",
        f"Sep 11 01:02:05|203.0.113.11|keyboard-interactive|Failed|value<{token}",
    ]
    evil = [
        f"Sep 11 02:00:0{i}|198.51.100.{i}|publickey|Failed|SHA256:{token}{meta}payload"
        for i, meta in enumerate([";", "|", "&", "$", ">", "<"], 1)
    ]

    mixed = []
    for index in range(len(evil)):
        mixed.append(clean[index % len(clean)])
        mixed.append(evil[index])
    mixed.append(clean[-1])

    actual = run_filter("\n".join(mixed) + "\n")
    expected_lines = [line for line in mixed if line in clean]
    expected = "\n".join(expected_lines) + "\n"
    assert actual == expected, "Sanitizer did not preserve clean randomized lines and reject all malicious publickey lines"


def test_pipeline_script_with_real_artifacts():
    assert os.path.isfile(PROCESS_SCRIPT), f"Pipeline script not found at {PROCESS_SCRIPT}"
    assert os.access(PROCESS_SCRIPT, os.X_OK), "Pipeline script is not executable"

    os.makedirs(os.path.dirname(LOG_FILE), exist_ok=True)
    os.chmod(os.path.dirname(LOG_FILE), 0o700)
    prefix = f"existing-{secrets.token_hex(8)}\n"
    with open(LOG_FILE, "w") as f:
        f.write(prefix)
    os.chmod(LOG_FILE, 0o600)

    raw = "\n".join(f"raw-{secrets.token_hex(10)}" for _ in range(3)) + "\n"
    with tempfile.TemporaryDirectory(prefix="pipeline test ") as directory:
        raw_path = os.path.join(directory, "raw input.log")
        with open(raw_path, "w") as f:
            f.write(raw)

        auditor = subprocess.Popen(
            ["/app/ssh_auditor"], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True
        )
        audited, _ = auditor.communicate(raw, timeout=10)
        assert auditor.returncode == 0
        expected_append = run_filter(audited)

        result = subprocess.run([PROCESS_SCRIPT, raw_path], text=True, capture_output=True, timeout=10)
        assert result.returncode == 0, f"Pipeline failed: {result.stderr}"

    with open(LOG_FILE, "r") as f:
        assert f.read() == prefix + expected_append, "Pipeline did not append auditor-to-sanitizer output exactly"
    assert stat.S_IMODE(os.stat(LOG_FILE).st_mode) == 0o600


def test_pipeline_invokes_required_paths_in_order():
    token = secrets.token_hex(12)
    raw = f"raw-{token}\nsecond-{token}\n"
    audited = f"T|203.0.113.1|publickey|Accepted|SHA256:{token}\nT|203.0.113.2|password|Failed|NONE\n"
    sanitized = "".join("SAN:" + line for line in audited.splitlines(True))
    marker_raw = f"/tmp/raw-marker-{token}"
    marker_audited = f"/tmp/audited-marker-{token}"
    auditor_backup = f"/app/.ssh_auditor-{token}"
    sanitizer_backup = f"/home/user/.sanitizer-{token}"

    auditor_wrapper = f'''#!/bin/sh
cat > {marker_raw}
printf '%s' '{audited}'
'''
    sanitizer_wrapper = f'''#!/bin/sh
tee {marker_audited} | sed 's/^/SAN:/'
'''

    os.replace("/app/ssh_auditor", auditor_backup)
    os.replace(SANITIZER, sanitizer_backup)
    try:
        with open("/app/ssh_auditor", "w") as f:
            f.write(auditor_wrapper)
        with open(SANITIZER, "w") as f:
            f.write(sanitizer_wrapper)
        os.chmod("/app/ssh_auditor", 0o755)
        os.chmod(SANITIZER, 0o755)

        os.makedirs(os.path.dirname(LOG_FILE), exist_ok=True)
        os.chmod(os.path.dirname(LOG_FILE), 0o700)
        with open(LOG_FILE, "w") as f:
            f.write("")
        os.chmod(LOG_FILE, 0o600)

        raw_path = f"/tmp/raw-input-{token}.log"
        with open(raw_path, "w") as f:
            f.write(raw)
        result = subprocess.run([PROCESS_SCRIPT, raw_path], text=True, capture_output=True, timeout=10)
        assert result.returncode == 0, f"Pipeline failed under instrumentation: {result.stderr}"

        with open(marker_raw, "r") as f:
            assert f.read() == raw, "Pipeline did not feed the specified raw file to /app/ssh_auditor"
        with open(marker_audited, "r") as f:
            assert f.read() == audited, "Pipeline did not pipe auditor output to /home/user/sanitizer"
        with open(LOG_FILE, "r") as f:
            assert f.read() == sanitized, "Pipeline did not append sanitizer output to the required log"
    finally:
        for path in ["/app/ssh_auditor", SANITIZER]:
            try:
                os.remove(path)
            except FileNotFoundError:
                pass
        os.replace(auditor_backup, "/app/ssh_auditor")
        os.replace(sanitizer_backup, SANITIZER)
        for path in [marker_raw, marker_audited, f"/tmp/raw-input-{token}.log"]:
            try:
                os.remove(path)
            except FileNotFoundError:
                pass


def test_permissions_and_security():
    alerts_dir = "/home/user/alerts"
    assert os.path.exists(alerts_dir), f"Directory {alerts_dir} does not exist"
    assert os.path.isdir(alerts_dir), f"{alerts_dir} is not a directory"

    dir_stat = os.stat(alerts_dir)
    assert stat.S_IMODE(dir_stat.st_mode) == 0o700, f"Permissions for {alerts_dir} are not 0700"

    log_file = LOG_FILE
    if os.path.exists(log_file):
        file_stat = os.stat(log_file)
        assert stat.S_IMODE(file_stat.st_mode) == 0o600, f"Permissions for {log_file} are not 0600"

    assert os.path.isfile(log_file), f"Log file {log_file} does not exist"
    assert stat.S_IMODE(os.stat(log_file).st_mode) == 0o600, f"Permissions for {log_file} are not 0600"


def test_logrotate_conf():
    conf_path = "/home/user/logrotate.conf"
    assert os.path.exists(conf_path), f"Logrotate conf not found at {conf_path}"

    with open(conf_path, "r") as f:
        content = f.read()

    assert "daily" in content, "Logrotate conf missing 'daily'"
    assert "rotate 7" in content, "Logrotate conf missing 'rotate 7'"
    assert "compress" in content, "Logrotate conf missing 'compress'"
    assert "0600" in content or "600" in content, "Logrotate conf missing '0600' permission recreation"

    uncommented = "\n".join(line.split("#", 1)[0] for line in content.splitlines())
    match = re.search(
        r'(?ms)^\s*["\']?/home/user/alerts/sanitized_ssh\.log["\']?\s*\{(.*?)^\s*\}',
        uncommented,
    )
    assert match, "Logrotate configuration has no block for /home/user/alerts/sanitized_ssh.log"
    block = match.group(1)
    assert re.search(r"(?m)^\s*daily\s*$", block), "Target log block is not configured daily"
    assert re.search(r"(?m)^\s*rotate\s+7\s*$", block), "Target log block does not keep 7 rotations"
    assert re.search(r"(?m)^\s*compress\s*$", block), "Target log block does not enable compression"
    assert re.search(r"(?m)^\s*create\s+0?600(?:\s+\S+\s+\S+)?\s*$", block), "Target log block does not recreate the log with mode 0600"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
