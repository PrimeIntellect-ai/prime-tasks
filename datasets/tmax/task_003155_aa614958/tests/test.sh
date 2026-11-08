#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import hashlib
import json
import os
import re
import secrets
import shutil
import subprocess
import tempfile

import pytest

USER = "user"
CONFIG_DIR = "/home/user/secure_configs"
PROJECT_DIR = "/home/user/fs_monitor"
BINARY = "/home/user/fs_monitor/target/release/fs_monitor"
REPORT = "/home/user/audit_report.json"


def run_as_user(command, **kwargs):
    return subprocess.run(
        ["runuser", "-u", USER, "--"] + command,
        **kwargs,
    )


def expected_report(files):
    return {
        "files": [
            {"name": name, "hash": hashlib.sha256(content).hexdigest()}
            for name, content in sorted(files.items())
        ]
    }


def load_report():
    try:
        with open(REPORT, "r", encoding="utf-8") as f:
            return json.load(f)
    except json.JSONDecodeError:
        pytest.fail("audit_report.json is not valid JSON.")


def run_monitor_and_check(files):
    if os.path.exists(REPORT):
        os.unlink(REPORT)

    result = run_as_user(
        [BINARY],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )
    assert result.returncode == 0, (
        "Compiled monitor failed when executed: "
        + result.stderr.decode("utf-8", errors="replace")
    )
    assert os.path.isfile(REPORT), "Monitor did not create /home/user/audit_report.json."
    assert load_report() == expected_report(files), (
        "Monitor report does not contain the sorted, dynamically computed hashes "
        "for every file in secure_configs."
    )


def replace_configs(files):
    os.makedirs(CONFIG_DIR, exist_ok=True)
    for entry in os.scandir(CONFIG_DIR):
        if entry.is_dir(follow_symlinks=False):
            shutil.rmtree(entry.path)
        else:
            os.unlink(entry.path)
    for name, content in files.items():
        with open(os.path.join(CONFIG_DIR, name), "wb") as f:
            f.write(content)
        os.chmod(os.path.join(CONFIG_DIR, name), 0o644)


def test_network_script():
    script_path = "/home/user/harden_net.sh"
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."

    with open(script_path, "r", encoding="utf-8") as f:
        content = f.read()

    assert re.search(
        r"(?m)^\s*ip\s+route\s+add\s+blackhole\s+203\.0\.113\.0/24\s*(?:#.*)?$",
        content,
    ), "Blackhole route command missing as an actual shell command."
    assert re.search(
        r"(?m)^\s*ip\s+link\s+set\s+(?:dev\s+)?eth0\s+mtu\s+1400\s*(?:#.*)?$",
        content,
    ), "MTU command missing as an actual shell command."

    token = secrets.token_hex(24)
    with tempfile.TemporaryDirectory(prefix="net-verifier-") as fake_dir:
        fake_ip = os.path.join(fake_dir, "ip")
        with open(fake_ip, "w", encoding="utf-8") as f:
            f.write(
                "#!/usr/bin/python3\n"
                "import json, sys\n"
                f"print({token!r} + json.dumps(sys.argv[1:]), flush=True)\n"
            )
        os.chmod(fake_dir, 0o755)
        os.chmod(fake_ip, 0o755)

        env = os.environ.copy()
        env["PATH"] = fake_dir + ":/usr/bin:/bin"
        result = run_as_user(
            ["/bin/bash", script_path],
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=20,
        )

    assert result.returncode == 0, (
        "Network script failed under a harmless ip-command shim: "
        + result.stderr.decode("utf-8", errors="replace")
    )
    calls = []
    for line in result.stdout.decode("utf-8", errors="replace").splitlines():
        if line.startswith(token):
            calls.append(json.loads(line[len(token):]))

    assert ["route", "add", "blackhole", "203.0.113.0/24"] in calls, (
        "Network script does not execute the required blackhole route command."
    )
    assert (
        ["link", "set", "dev", "eth0", "mtu", "1400"] in calls
        or ["link", "set", "eth0", "mtu", "1400"] in calls
    ), "Network script does not execute the required MTU command."


def test_filesystem_setup():
    app_conf = os.path.join(CONFIG_DIR, "app.conf")
    db_conf = os.path.join(CONFIG_DIR, "db.conf")

    assert os.path.isdir(CONFIG_DIR), f"{CONFIG_DIR} missing."
    assert os.path.isfile(app_conf), f"{app_conf} missing."
    assert os.path.isfile(db_conf), f"{db_conf} missing."
    assert sorted(os.listdir(CONFIG_DIR)) == ["app.conf", "db.conf"], (
        "secure_configs must contain the two specified configuration files."
    )

    with open(app_conf, "rb") as f:
        assert f.read() == b"PORT=8080", "app.conf content is incorrect or has trailing newline."
    with open(db_conf, "rb") as f:
        assert f.read() == b"MAX_CONNS=50", "db.conf content is incorrect or has trailing newline."


def test_rust_integrity_monitor():
    cargo_toml = os.path.join(PROJECT_DIR, "Cargo.toml")
    assert os.path.isfile(cargo_toml), f"{cargo_toml} missing."
    assert glob.glob(os.path.join(PROJECT_DIR, "**", "*.rs"), recursive=True), (
        "Rust project contains no Rust source files."
    )
    assert os.path.isfile(BINARY), f"Compiled binary {BINARY} missing."
    assert os.access(BINARY, os.X_OK), f"Compiled binary {BINARY} is not executable."
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", "fs_monitor is not a compiled ELF binary."
    assert os.path.isfile(REPORT), f"Audit report {REPORT} missing."

    initial_files = {"app.conf": b"PORT=8080", "db.conf": b"MAX_CONNS=50"}
    assert load_report() == expected_report(initial_files), (
        "Initial audit report has incorrect names, ordering, or hashes."
    )

    # Remove the submitted executable and require Cargo to recreate the release binary.
    os.unlink(BINARY)
    build = run_as_user(
        ["/usr/bin/cargo", "build", "--release"],
        cwd=PROJECT_DIR,
        env={
            "HOME": "/home/user",
            "USER": USER,
            "LOGNAME": USER,
            "PATH": "/usr/bin:/bin",
        },
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=180,
    )
    assert build.returncode == 0, (
        "cargo build --release failed: "
        + build.stderr.decode("utf-8", errors="replace")
    )
    assert os.path.isfile(BINARY) and os.access(BINARY, os.X_OK), (
        "cargo build --release did not recreate the required binary."
    )
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Cargo did not produce a compiled ELF binary."

    case_one = {
        "app.conf": secrets.token_bytes(29),
        "db.conf": secrets.token_bytes(41),
        "extra-" + secrets.token_hex(5) + ".conf": secrets.token_bytes(17),
    }
    case_two = {
        "alpha-" + secrets.token_hex(4): secrets.token_bytes(13),
        "zeta-" + secrets.token_hex(4): secrets.token_bytes(67),
    }

    try:
        replace_configs(case_one)
        run_monitor_and_check(case_one)
        replace_configs(case_two)
        run_monitor_and_check(case_two)
    finally:
        replace_configs(initial_files)
        if os.path.isfile(BINARY):
            run_monitor_and_check(initial_files)


def test_scheduled_task():
    try:
        output = subprocess.check_output(
            ["crontab", "-u", USER, "-l"],
            stderr=subprocess.STDOUT,
            text=True,
        )
    except subprocess.CalledProcessError as exc:
        pytest.fail("Failed to read user crontab: " + exc.output)

    pattern = re.compile(
        r"^\s*\*/15\s+\*\s+\*\s+\*\s+\*\s+"
        r"/home/user/fs_monitor/target/release/fs_monitor\s+"
        r"2>\s*/home/user/fs_monitor_error\.log\s*$"
    )
    active_lines = [
        line for line in output.splitlines()
        if line.strip() and not line.lstrip().startswith("#")
    ]
    assert any(pattern.fullmatch(line) for line in active_lines), (
        "Cron job must use exactly the every-15-minutes schedule, execute the release "
        "binary, redirect only stderr to fs_monitor_error.log, and not redirect stdout."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
