#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import os
import random
import re
import stat
import string
import subprocess
from pathlib import Path


def test_pexpect_setup_fixed():
    setup_path = Path("/app/pexpect-4.8.0/setup.py")
    assert setup_path.is_file(), f"Vendored setup.py not found at {setup_path}"
    source = setup_path.read_text()
    assert "PEXPECT_INSTALL_TOKEN" not in source
    assert "legacy_admin_override" not in source
    assert "Missing INSTALL_TOKEN" not in source
    compile(source, str(setup_path), "exec")


def test_pexpect_installed():
    """Verify the real pexpect 4.8.0 package is installed and functional."""
    python_bin = "/home/user/venv/bin/python"
    assert os.path.isfile(python_bin), f"Virtual environment Python not found at {python_bin}"

    result = subprocess.run(
        [python_bin, "-c", "import pexpect; print(pexpect.__version__)"],
        capture_output=True,
        text=True
    )
    assert result.returncode == 0, f"Failed to import pexpect: {result.stderr}"
    assert result.stdout.strip() == "4.8.0", f"Expected pexpect version 4.8.0, got {result.stdout.strip()}"

    probe = r'''
import importlib.metadata
import os
import secrets
import sys
from pathlib import Path
import pexpect

assert pexpect.__version__ == "4.8.0"
module = Path(pexpect.__file__).resolve()
prefix = Path(sys.prefix).resolve()
assert str(module).startswith(str(prefix) + os.sep), (module, prefix)
dist = importlib.metadata.distribution("pexpect")
assert dist.version == "4.8.0"
assert module.parent == Path(dist.locate_file("pexpect")).resolve()

token = "probe_" + secrets.token_hex(12)
program = "import sys; print('READY', flush=True); s=input(); print('ECHO:'+s, flush=True)"
child = pexpect.spawn(sys.executable, ["-u", "-c", program], encoding="utf-8", timeout=5)
child.expect_exact("READY\r\n")
child.sendline(token)
child.expect_exact("ECHO:" + token + "\r\n")
child.expect(pexpect.EOF)
child.close()
assert child.exitstatus == 0, child.exitstatus
'''
    result = subprocess.run(
        [python_bin, "-I", "-c", probe], capture_output=True, text=True, timeout=15
    )
    assert result.returncode == 0, f"Installed pexpect failed functional checks:\n{result.stdout}\n{result.stderr}"


def test_sanitise_users_adversarial_corpus(tmp_path):
    """Retain the original corpus checks."""
    script_path = "/home/user/sanitise_users.py"
    assert os.path.isfile(script_path), f"Sanitiser script not found at {script_path}"

    evil_files = glob.glob("/app/tests/corpus/evil/*.json")
    clean_files = glob.glob("/app/tests/corpus/clean/*.json")
    assert len(evil_files) > 0, "No evil corpus files found."
    assert len(clean_files) > 0, "No clean corpus files found."

    evil_bypassed = []
    clean_modified = []
    for evil_file in evil_files:
        output_file = tmp_path / f"out_evil_{os.path.basename(evil_file)}"
        result = subprocess.run(["python3", script_path, evil_file, str(output_file)], capture_output=True, text=True)
        assert result.returncode == 0, f"Script failed on {evil_file}: {result.stderr}"
        assert output_file.is_file(), f"Output file not created for {evil_file}"
        try:
            out_data = json.loads(output_file.read_text())
        except json.JSONDecodeError:
            out_data = None
        if out_data != []:
            evil_bypassed.append(os.path.basename(evil_file))

    for clean_file in clean_files:
        output_file = tmp_path / f"out_clean_{os.path.basename(clean_file)}"
        result = subprocess.run(["python3", script_path, clean_file, str(output_file)], capture_output=True, text=True)
        assert result.returncode == 0, f"Script failed on {clean_file}: {result.stderr}"
        assert output_file.is_file(), f"Output file not created for {clean_file}"
        in_data = json.loads(Path(clean_file).read_text())
        try:
            out_data = json.loads(output_file.read_text())
        except json.JSONDecodeError:
            out_data = None
        if out_data != in_data:
            clean_modified.append(os.path.basename(clean_file))

    errors = []
    if evil_bypassed:
        errors.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_modified:
        errors.append(f"{len(clean_modified)} of {len(clean_files)} clean modified: {', '.join(clean_modified)}")
    assert not errors, " | ".join(errors)


def test_sanitise_users_generated_cases(tmp_path):
    """Exercise unpredictable mixed inputs and derive the expected filtered list."""
    script_path = "/home/user/sanitise_users.py"
    assert os.path.isfile(script_path), f"Sanitiser script not found at {script_path}"

    rng = random.SystemRandom()
    alphabet = string.ascii_lowercase + string.digits
    nonce = ''.join(rng.choice(alphabet) for _ in range(14))

    valid = [
        {"username": f"acct-{nonce}", "home_dir": f"/home/acct-{nonce}", "shell": "/bin/bash"},
        {"username": f"svc_{nonce}", "home_dir": f"/home/services/{nonce}", "shell": "/bin/sh"},
        {"username": (nonce + "x" * 32)[:32], "home_dir": f"/home/{nonce}/data", "shell": "/usr/bin/zsh"},
    ]
    invalid = [
        {"username": f"Bad{nonce}", "home_dir": f"/home/{nonce}", "shell": "/bin/bash"},
        {"username": f"bad;{nonce}", "home_dir": f"/home/{nonce}", "shell": "/bin/bash"},
        {"username": "a" * 33, "home_dir": f"/home/{nonce}", "shell": "/bin/bash"},
        {"username": f"u-{nonce}", "home_dir": f"/tmp/{nonce}", "shell": "/bin/bash"},
        {"username": f"v-{nonce}", "home_dir": f"/home/{nonce}/../root", "shell": "/bin/sh"},
        {"username": f"w-{nonce}", "home_dir": f"/home/{nonce}\\..\\root", "shell": "/usr/bin/zsh"},
        {"username": f"x-{nonce}", "home_dir": f"/home/{nonce}", "shell": "/bin/zsh"},
        {"username": f"y-{nonce}", "home_dir": f"/home/{nonce}", "shell": "/bin/bash -c id"},
    ]

    records = valid + invalid
    rng.shuffle(records)
    expected = [record for record in records if record in valid]
    input_path = tmp_path / f"requests_{nonce}.json"
    output_path = tmp_path / f"filtered_{nonce}.json"
    input_path.write_text(json.dumps(records))

    result = subprocess.run(
        ["python3", script_path, str(input_path), str(output_path)],
        capture_output=True, text=True, timeout=10
    )
    assert result.returncode == 0, f"Sanitiser failed: {result.stderr}"
    assert output_path.is_file(), "Sanitiser did not create its requested output file"
    actual = json.loads(output_path.read_text())
    assert actual == expected, f"Expected {expected!r}, got {actual!r}"


def _active_cron_jobs(text):
    jobs = []
    for raw in text.splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", line):
            continue
        jobs.append(line)
    return jobs


def test_cron_job_loaded_and_runs():
    """Check the user's loaded crontab and execute its actual job in a cron-like environment."""
    cron_file = Path("/home/user/sync_cron")
    assert cron_file.is_file(), "Cron configuration file is missing"

    result = subprocess.run(["crontab", "-u", "user", "-l"], capture_output=True, text=True)
    assert result.returncode == 0, "Failed to read user account's crontab. Was it loaded?"
    crontab_content = result.stdout
    assert "/home/user/venv/bin/python" in crontab_content, "Crontab does not use the venv python."
    assert "/home/user/orchestrator.py" in crontab_content, "Crontab does not execute orchestrator.py."
    assert "/home/user/account_sync/output/sync.log" in crontab_content, "Crontab does not redirect output to the correct log file."

    source_jobs = _active_cron_jobs(cron_file.read_text())
    loaded_jobs = _active_cron_jobs(crontab_content)
    assert len(source_jobs) == 1, f"Expected one active job in sync_cron, got {source_jobs!r}"
    assert source_jobs[0] in loaded_jobs, "The corrected sync_cron job was not loaded for user"

    fields = source_jobs[0].split(None, 5)
    assert len(fields) == 6 and fields[:5] == ["*", "*", "*", "*", "*"], "Job must run every minute"
    command = fields[5]
    command_pattern = re.compile(
        r'''^\s*["']?/home/user/venv/bin/python["']?\s+["']?/home/user/orchestrator\.py["']?\s*(?:>>|>)\s*["']?/home/user/account_sync/output/sync\.log["']?\s+2>&1\s*$'''
    )
    assert command_pattern.fullmatch(command), f"Unexpected cron command: {command!r}"

    log_path = Path("/home/user/account_sync/output/sync.log")
    if log_path.exists():
        log_path.unlink()
    run = subprocess.run(
        ["runuser", "-u", "user", "--", "env", "-i",
         "HOME=/home/user", "USER=user", "LOGNAME=user", "PATH=/usr/bin:/bin",
         "/bin/sh", "-c", command],
        cwd="/home/user", capture_output=True, text=True, timeout=15
    )
    assert run.returncode == 0, f"Cron command failed as user: {run.stderr}"
    assert log_path.is_file(), "Cron command did not generate the required log file"
    assert "Orchestrator ran successfully" in log_path.read_text(), "Cron log lacks orchestrator output"


def test_directory_permissions():
    target_dir = "/home/user/account_sync/output"
    assert os.path.isdir(target_dir), f"Directory does not exist: {target_dir}"
    permissions = stat.S_IMODE(os.stat(target_dir).st_mode)
    assert permissions == 0o755, f"Expected permissions 0755, got {oct(permissions)}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
