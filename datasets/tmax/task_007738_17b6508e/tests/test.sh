#!/bin/bash
mkdir -p /logs/verifier
echo "0" > /logs/verifier/reward.txt

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import re
import shlex
import stat
import subprocess
import uuid


def test_phase1_run_auth_sh():
    """Verify run_auth.sh passes password via environment variable, not CLI."""
    path = "/home/user/run_auth.sh"
    assert os.path.isfile(path), f"File {path} is missing."

    with open(path, "r") as f:
        content = f.read()

    # Preserve the original source assertions.
    assert "AUTH_SECRET" in content, f"File {path} must set or export the AUTH_SECRET environment variable."
    assert "--password" not in content, f"File {path} must NOT pass the password via the --password command-line argument."
    assert re.search(r"python3\s+/home/user/auth_service\.py\s+--user", content), f"File {path} must still call the python script with the --user argument."

    # Replace the service briefly with a probe so the wrapper's actual argv and
    # environment can be observed without relying on source text.
    service = "/home/user/auth_service.py"
    assert os.path.isfile(service), f"File {service} is missing."
    with open(service, "rb") as f:
        original = f.read()
    original_mode = stat.S_IMODE(os.stat(service).st_mode)
    probe_output = f"/tmp/run_auth_probe_{uuid.uuid4().hex}.json"
    probe = f'''import json, os, sys
with open({probe_output!r}, "w") as f:
    json.dump({{"argv": sys.argv[1:], "secret": os.environ.get("AUTH_SECRET")}}, f)
'''
    username = "user " + uuid.uuid4().hex
    password = "pw " + uuid.uuid4().hex + " ; $() *"

    try:
        with open(service, "w") as f:
            f.write(probe)
        env = os.environ.copy()
        env.pop("AUTH_SECRET", None)
        result = subprocess.run(
            [path, username, password], env=env, text=True,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10
        )
        assert result.returncode == 0, f"run_auth.sh failed: {result.stderr}"
        assert os.path.isfile(probe_output), "run_auth.sh did not execute /home/user/auth_service.py."
        with open(probe_output) as f:
            observed = json.load(f)
        assert observed["argv"] == ["--user", username], (
            f"Authentication service received unsafe or incorrect arguments: {observed['argv']}"
        )
        assert observed["secret"] == password, "run_auth.sh did not pass $2 through AUTH_SECRET exactly."
    finally:
        with open(service, "wb") as f:
            f.write(original)
        os.chmod(service, original_mode)
        if os.path.exists(probe_output):
            os.unlink(probe_output)


def test_phase1_auth_service_py():
    """Verify auth_service.py reads and uses the password from the environment."""
    path = "/home/user/auth_service.py"
    assert os.path.isfile(path), f"File {path} is missing."

    with open(path, "r") as f:
        content = f.read()

    # Preserve the original source assertions.
    assert re.search(r"import\s+os\b", content), f"File {path} must import the 'os' module to read environment variables."
    assert re.search(r"os\.environ(?:\[['\"]AUTH_SECRET['\"]\]|\.get\(['\"]AUTH_SECRET['\"]\))", content), f"File {path} must read 'AUTH_SECRET' from os.environ."

    username = "probe_" + uuid.uuid4().hex
    env = os.environ.copy()
    env["AUTH_SECRET"] = "secret"
    good = subprocess.run(
        ["python3", path, "--user", username], env=env, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10
    )
    assert good.returncode == 0, f"auth_service.py failed with an environment password: {good.stderr}"
    assert good.stdout.strip() == "Success", "AUTH_SECRET=secret must authenticate successfully."

    env["AUTH_SECRET"] = "wrong_" + uuid.uuid4().hex
    bad = subprocess.run(
        ["python3", path, "--user", username], env=env, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10
    )
    assert bad.returncode == 0, f"auth_service.py failed while checking a bad password: {bad.stderr}"
    assert bad.stdout.strip() == "Failure", "A wrong AUTH_SECRET must fail authentication."

    # A command-line password must not override the environment value. Rejection
    # of --password is also acceptable.
    cli = subprocess.run(
        ["python3", path, "--user", username, "--password", "secret"],
        env=env, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10
    )
    assert cli.returncode != 0 or cli.stdout.strip() != "Success", (
        "auth_service.py still accepts the credential from --password instead of AUTH_SECRET."
    )


def test_phase2_flagged_ips():
    """Verify the IDS monitor correctly identified and sorted the supplied fixture."""
    path = "/home/user/flagged_ips.txt"
    assert os.path.isfile(path), f"File {path} is missing. Did the IDS script run and create it?"

    with open(path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_ips = ["172.16.0.2", "192.168.1.20"]
    assert lines == expected_ips, f"Contents of {path} are incorrect. Expected {expected_ips}, but got {lines}."


def test_phase2_monitor_executes_on_new_input():
    """Execute ids_monitor.py against an unrevealed traffic log."""
    script = "/home/user/ids_monitor.py"
    traffic = "/home/user/traffic.log"
    output = "/home/user/flagged_ips.txt"
    assert os.path.isfile(script), f"File {script} is missing."

    with open(traffic, "rb") as f:
        old_traffic = f.read()
    old_output = None
    if os.path.exists(output):
        with open(output, "rb") as f:
            old_output = f.read()

    octets = random.sample(range(10, 240), 4)
    ip_a, ip_b, ip_c, ip_d = [f"10.77.0.{n}" for n in octets]
    user_a = "a_" + uuid.uuid4().hex
    user_b = "b_" + uuid.uuid4().hex
    user_c1 = "c1_" + uuid.uuid4().hex
    user_c2 = "c2_" + uuid.uuid4().hex
    user_d = "d_" + uuid.uuid4().hex

    attempts = []
    def add(ip, user, status):
        attempts.append({"timestamp": 5000 + len(attempts), "ip": ip, "user": user, "status": status})

    for _ in range(3):
        add(ip_a, user_a, "failed")
    add(ip_a, user_a, "success")
    for _ in range(2):
        add(ip_b, user_b, "failed")
    add(ip_b, user_b, "success")
    for _ in range(2):
        add(ip_b, user_b, "failed")
    for _ in range(2):
        add(ip_c, user_c1, "failed")
    for _ in range(3):
        add(ip_c, user_c2, "failed")
    for _ in range(4):
        add(ip_d, user_d, "failed")

    # Derive the answer from the generated records.
    counters = {}
    flagged = set()
    for item in attempts:
        key = (item["ip"], item["user"])
        if item["status"] == "success":
            counters[key] = 0
        else:
            counters[key] = counters.get(key, 0) + 1
            if counters[key] >= 3:
                flagged.add(item["ip"])
    expected = sorted(flagged)

    try:
        with open(traffic, "w") as f:
            for item in attempts:
                f.write(json.dumps(item) + "\n")
        if os.path.exists(output):
            os.unlink(output)

        result = subprocess.run(
            ["python3", script], cwd="/home/user", text=True,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10
        )
        assert result.returncode == 0, f"ids_monitor.py failed: {result.stderr}"
        assert os.path.isfile(output), "ids_monitor.py did not create /home/user/flagged_ips.txt."
        with open(output) as f:
            actual = [line.strip() for line in f if line.strip()]
        assert actual == expected, f"IDS output for generated traffic was {actual}; expected {expected}."
    finally:
        with open(traffic, "wb") as f:
            f.write(old_traffic)
        if old_output is None:
            if os.path.exists(output):
                os.unlink(output)
        else:
            with open(output, "wb") as f:
                f.write(old_output)


def test_phase3_sandbox_cmd():
    """Verify the saved line is a syntactically valid command with exactly the required structure."""
    path = "/home/user/sandbox_cmd.txt"
    assert os.path.isfile(path), f"File {path} is missing."

    with open(path, "r") as f:
        raw = f.read()
    content = raw.strip()

    # Preserve the original assertions.
    assert "bwrap" in content, f"Command in {path} must use the 'bwrap' executable."
    assert "--ro-bind / /" in content, f"Command in {path} must bind the root filesystem as read-only (--ro-bind / /)."
    assert "--dev /dev" in content, f"Command in {path} must mount devfs (--dev /dev)."
    assert "--proc /proc" in content, f"Command in {path} must mount procfs (--proc /proc)."
    assert "--tmpfs /tmp" in content, f"Command in {path} must create a tmpfs (--tmpfs /tmp)."
    assert "--unshare-all" in content, f"Command in {path} must isolate namespaces (--unshare-all)."
    assert re.search(r"python3\s+/home/user/auth_service\.py\s+--user\s+guest", content), f"Command in {path} must execute python3 /home/user/auth_service.py --user guest inside the sandbox."

    assert len(raw.splitlines()) == 1, f"{path} must contain exactly one command line."
    try:
        argv = shlex.split(content, posix=True)
    except ValueError as exc:
        raise AssertionError(f"Command in {path} is not valid shell syntax: {exc}")

    assert len(argv) >= 5 and os.path.basename(argv[0]) == "bwrap", "The command executable must be bwrap."
    payload = argv[-4:]
    assert os.path.basename(payload[0]) == "python3" and payload[1:] == [
        "/home/user/auth_service.py", "--user", "guest"
    ], "The bwrap payload must be exactly python3 /home/user/auth_service.py --user guest."

    options = argv[1:-4]
    if options and options[-1] == "--":
        options = options[:-1]

    counts = {"ro": 0, "proc": 0, "dev": 0, "tmpfs": 0, "unshare": 0}
    i = 0
    while i < len(options):
        token = options[i]
        if token == "--unshare-all":
            counts["unshare"] += 1
            i += 1
        elif token == "--ro-bind" and options[i:i+3] == ["--ro-bind", "/", "/"]:
            counts["ro"] += 1
            i += 3
        elif token == "--proc" and options[i:i+2] == ["--proc", "/proc"]:
            counts["proc"] += 1
            i += 2
        elif token == "--dev" and options[i:i+2] == ["--dev", "/dev"]:
            counts["dev"] += 1
            i += 2
        elif token == "--tmpfs" and options[i:i+2] == ["--tmpfs", "/tmp"]:
            counts["tmpfs"] += 1
            i += 2
        else:
            raise AssertionError(f"Unexpected or malformed bwrap argument near: {options[i:]}")

    assert all(value == 1 for value in counts.values()), f"Each required sandbox option must appear exactly once: {counts}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
