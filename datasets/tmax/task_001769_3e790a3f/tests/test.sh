#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import datetime
import os
import random
import re
import shutil
import socket
import ssl
import string
import subprocess
import tempfile
import time
import urllib.request
import uuid


def oracle_token(value):
    result = subprocess.run(["/app/legacy_prov_hash", value], capture_output=True, text=True)
    assert result.returncode == 0, f"Oracle failed on input {value!r}"
    assert result.stderr == ""
    return result.stdout.rstrip("\n")


def test_fuzz_equivalence():
    oracle_path = "/app/legacy_prov_hash"
    agent_path = "/home/user/new_prov_hash.py"

    assert os.path.exists(oracle_path), f"Oracle missing at {oracle_path}"
    assert os.path.isfile(agent_path), f"Agent script missing at {agent_path}"

    random.seed(42)
    charset = string.ascii_letters + string.digits + "_-"

    for _ in range(100):
        length = random.randint(1, 128)
        test_input = "".join(random.choice(charset) for _ in range(length))

        oracle_res = subprocess.run([oracle_path, test_input], capture_output=True, text=True)
        assert oracle_res.returncode == 0, f"Oracle failed on input {test_input}"
        oracle_out = oracle_res.stdout.strip()

        agent_res = subprocess.run(["python3", agent_path, test_input], capture_output=True, text=True)
        assert agent_res.returncode == 0, f"Agent script failed on input {test_input}. Error: {agent_res.stderr}"
        agent_out = agent_res.stdout.strip()

        assert oracle_out == agent_out, f"Mismatch on input '{test_input}'. Oracle: '{oracle_out}', Agent: '{agent_out}'"
        assert agent_res.stdout == oracle_res.stdout, f"Output was not byte-for-byte identical for {test_input!r}"
        assert agent_res.stderr == "", f"Agent wrote unexpected stderr for {test_input!r}"


def parse_log_line(line, expected_branch, expected_token, started, finished):
    match = re.fullmatch(
        r"\[(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z)\] BRANCH:"
        + re.escape(expected_branch)
        + r" TOKEN:"
        + re.escape(expected_token),
        line,
    )
    assert match, f"Malformed hook log line: {line!r}"
    parsed = datetime.datetime.strptime(match.group(1), "%Y-%m-%dT%H:%M:%SZ").replace(
        tzinfo=datetime.timezone.utc
    ).timestamp()
    assert started - 5 <= parsed <= finished + 5, f"Hook timestamp is not current: {match.group(1)}"


def test_git_repo_and_hook():
    repo_path = "/home/user/provision_repo.git"
    hook_path = os.path.join(repo_path, "hooks/post-receive")
    log_path = "/home/user/logs/provision.log"

    assert os.path.isdir(repo_path), f"Git repo missing at {repo_path}"
    assert subprocess.run(["git", "--git-dir", repo_path, "rev-parse", "--is-bare-repository"], capture_output=True, text=True).stdout.strip() == "true"
    assert os.path.isfile(hook_path), f"post-receive hook missing at {hook_path}"
    assert os.access(hook_path, os.X_OK), f"post-receive hook is not executable"

    # Preserve the real push test from the original verifier.
    with tempfile.TemporaryDirectory() as tmpdir:
        clone_dir = os.path.join(tmpdir, "clone")
        subprocess.run(["git", "clone", repo_path, clone_dir], check=True, capture_output=True)
        test_file = os.path.join(clone_dir, "test.txt")
        with open(test_file, "w") as f:
            f.write("test")
        subprocess.run(["git", "config", "user.name", "Test User"], cwd=clone_dir, check=True)
        subprocess.run(["git", "config", "user.email", "test@example.com"], cwd=clone_dir, check=True)
        subprocess.run(["git", "add", "test.txt"], cwd=clone_dir, check=True)
        subprocess.run(["git", "commit", "-m", "test commit"], cwd=clone_dir, check=True)
        branch_name = f"test-branch-{random.randint(1000, 9999)}"
        subprocess.run(["git", "push", "origin", f"HEAD:refs/heads/{branch_name}"], cwd=clone_dir, check=True, capture_output=True)

        assert os.path.isfile(log_path), f"Log file not created at {log_path}"
        with open(log_path, "r") as f:
            logs = f.read()
        assert branch_name in logs, f"Branch name {branch_name} not found in logs"
        assert "TOKEN:" in logs, "TOKEN: not found in logs"

    # Exercise one hook invocation containing multiple refs with PATH intentionally unusable.
    # This validates ref iteration and the requirement that invoked paths be absolute.
    branches = [f"audit-{uuid.uuid4().hex[:10]}", f"feature-{uuid.uuid4().hex[:10]}"]
    updates = "".join(
        f"{'0' * 40} {'1' * 40} refs/heads/{branch}\n" for branch in branches
    )
    before = os.path.getsize(log_path) if os.path.exists(log_path) else 0
    started = time.time()
    result = subprocess.run(
        [hook_path],
        input=updates,
        text=True,
        capture_output=True,
        env={"PATH": "/nonexistent", "HOME": "/home/user"},
    )
    finished = time.time()
    assert result.returncode == 0, f"Hook failed with sanitized PATH: {result.stderr}"

    with open(log_path, "r") as f:
        f.seek(before)
        new_lines = [line.rstrip("\n") for line in f.readlines()]
    assert len(new_lines) == 2, f"Expected exactly one log line per pushed ref, got {new_lines!r}"
    for line, branch in zip(new_lines, branches):
        parse_log_line(line, branch, oracle_token(branch), started, finished)


def active_config_lines(content):
    return [re.sub(r"\s+#.*$", "", line).strip() for line in content.splitlines()
            if re.sub(r"\s+#.*$", "", line).strip()]


def test_logrotate_config():
    conf_path = "/home/user/logrotate.conf"
    assert os.path.isfile(conf_path), f"logrotate config missing at {conf_path}"
    with open(conf_path, "r") as f:
        content = f.read()

    assert "daily" in content, "logrotate config missing 'daily'"
    assert "rotate 5" in content, "logrotate config missing 'rotate 5'"
    assert "/home/user/logs/provision.log" in content, "logrotate config missing log path"

    match = re.search(r"(?:^|\n)\s*/home/user/logs/provision\.log\s*\{([^}]*)\}", content, re.S)
    assert match, "No logrotate stanza for /home/user/logs/provision.log"
    directives = active_config_lines(match.group(1))
    assert "daily" in directives, "Provision log stanza is not configured daily"
    assert any(re.fullmatch(r"rotate\s+5", line) for line in directives), "Provision log stanza does not retain exactly 5 backups"

    # Determine compression as configured globally before the stanza and then in the stanza.
    compression = False
    for line in active_config_lines(content[:match.start()]):
        if line == "compress":
            compression = True
        elif line == "nocompress":
            compression = False
    for line in directives:
        if line == "compress":
            compression = True
        elif line == "nocompress":
            compression = False
    assert not compression, "Provision log rotations must be uncompressed"


def test_crontab():
    res = subprocess.run(["crontab", "-l"], capture_output=True, text=True)
    assert res.returncode == 0, "Failed to read crontab"
    crontab_content = res.stdout
    assert "logrotate" in crontab_content, "logrotate not found in crontab"
    assert "/home/user/logrotate.conf" in crontab_content, "logrotate config path not found in crontab"

    lines = [line.strip() for line in crontab_content.splitlines() if line.strip() and not line.lstrip().startswith("#")]
    path_indices = [i for i, line in enumerate(lines) if re.fullmatch(r"PATH\s*=\s*.+", line)]
    assert path_indices, "Crontab does not explicitly define PATH"
    path_value = lines[path_indices[0]].split("=", 1)[1].strip()
    assert path_value and all(part.startswith("/") for part in path_value.split(":")), "Crontab PATH must contain absolute directories"

    jobs = []
    for i, line in enumerate(lines):
        match = re.match(r"^0\s+0\s+\*\s+\*\s+\*\s+(.+)$", line)
        if match:
            jobs.append((i, match.group(1)))
    assert jobs, "No cron job is scheduled for midnight every day"
    valid_jobs = []
    for index, command in jobs:
        first_word = command.split()[0] if command.split() else ""
        if first_word == "/usr/sbin/logrotate" and re.search(r"(?:^|\s)/home/user/logrotate\.conf(?:\s|$)", command):
            valid_jobs.append((index, command))
    assert valid_jobs, "Midnight job must invoke /usr/sbin/logrotate with /home/user/logrotate.conf"
    assert path_indices[0] < valid_jobs[0][0], "PATH must be defined before the cron job"


def nginx_descendants(root_pid):
    descendants = {root_pid}
    changed = True
    while changed:
        changed = False
        for name in os.listdir("/proc"):
            if not name.isdigit():
                continue
            try:
                fields = open(f"/proc/{name}/stat").read().split()
                pid, ppid = int(fields[0]), int(fields[3])
            except (OSError, ValueError, IndexError):
                continue
            if ppid in descendants and pid not in descendants:
                descendants.add(pid)
                changed = True
    return descendants


def listening_inodes(port):
    result = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        with open(table) as f:
            next(f)
            for line in f:
                fields = line.split()
                if int(fields[1].split(":")[1], 16) == port and fields[3] == "0A":
                    result.add(fields[9])
    return result


def test_nginx_and_tls():
    cert_path = "/home/user/tls/cert.pem"
    key_path = "/home/user/tls/key.pem"
    pid_path = "/home/user/nginx.pid"
    conf_path = "/home/user/nginx.conf"

    assert os.path.isfile(cert_path), f"TLS cert missing at {cert_path}"
    assert os.path.isfile(key_path), f"TLS key missing at {key_path}"
    assert os.path.isfile(pid_path), f"Nginx PID file missing at {pid_path}"
    assert os.path.isfile(conf_path), f"Nginx configuration missing at {conf_path}"

    with open(pid_path) as f:
        pid_text = f.read().strip()
    assert pid_text.isdigit(), "Nginx PID file does not contain a PID"
    pid = int(pid_text)
    assert os.path.isdir(f"/proc/{pid}"), "PID file does not identify a running process"
    exe = os.path.realpath(f"/proc/{pid}/exe")
    assert os.path.basename(exe) == "nginx", f"PID file identifies {exe}, not nginx"
    cmdline = open(f"/proc/{pid}/cmdline", "rb").read().replace(b"\0", b" ").decode(errors="replace")
    assert conf_path in cmdline, "Running nginx master was not started using /home/user/nginx.conf"

    with open(conf_path) as f:
        config = f.read()
    uncommented = "\n".join(re.sub(r"#.*$", "", line) for line in config.splitlines())
    assert re.search(r"\blisten\s+[^;]*8443[^;]*\bssl\b[^;]*;", uncommented), "nginx.conf lacks an SSL listener on 8443"
    assert re.search(r"\bpid\s+/home/user/nginx\.pid\s*;", uncommented), "nginx.conf does not configure the required PID file"
    assert re.search(r"\bssl_certificate\s+/home/user/tls/cert\.pem\s*;", uncommented)
    assert re.search(r"\bssl_certificate_key\s+/home/user/tls/key\.pem\s*;", uncommented)
    assert "/home/user/logs" in uncommented, "nginx.conf does not serve /home/user/logs"
    assert re.search(r"\bautoindex\s+on\s*;", uncommented), "Directory indexing is not enabled"
    syntax = subprocess.run(["/usr/sbin/nginx", "-t", "-c", conf_path], capture_output=True, text=True)
    assert syntax.returncode == 0, f"nginx.conf is invalid: {syntax.stderr}"

    inodes = listening_inodes(8443)
    assert inodes, "Nothing is listening on TCP port 8443"
    owned = False
    for process in nginx_descendants(pid):
        fd_dir = f"/proc/{process}/fd"
        try:
            links = [os.readlink(os.path.join(fd_dir, fd)) for fd in os.listdir(fd_dir)]
        except OSError:
            continue
        if any(link.startswith("socket:[") and link[8:-1] in inodes for link in links):
            owned = True
            break
    assert owned, "Port 8443 is not owned by the nginx process identified by nginx.pid"

    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE

    # Preserve the original root/directory-index response assertions.
    try:
        req = urllib.request.Request("https://127.0.0.1:8443/")
        with urllib.request.urlopen(req, context=ctx, timeout=5) as response:
            assert response.status == 200, f"Expected status 200, got {response.status}"
            body = response.read().decode("utf-8")
            assert "html" in body.lower() or "index" in body.lower(), "Nginx not serving directory index properly"
    except Exception as exc:
        assert False, f"Failed to connect to Nginx on port 8443: {exc}"

    # A fresh unpredictable file proves that the live HTTPS server exposes this exact directory.
    marker_name = f"verifier-{uuid.uuid4().hex}.txt"
    marker_value = f"logs-marker-{uuid.uuid4().hex}"
    marker_path = os.path.join("/home/user/logs", marker_name)
    with open(marker_path, "w") as f:
        f.write(marker_value)
    try:
        with urllib.request.urlopen(f"https://127.0.0.1:8443/{marker_name}", context=ctx, timeout=5) as response:
            assert response.status == 200
            assert response.read().decode() == marker_value, "HTTPS server is not serving /home/user/logs"
    finally:
        os.unlink(marker_path)

    # Ensure the certificate presented by the live listener is the required certificate file.
    with socket.create_connection(("127.0.0.1", 8443), timeout=5) as raw:
        with ctx.wrap_socket(raw, server_hostname="127.0.0.1") as tls_socket:
            served_der = tls_socket.getpeercert(binary_form=True)
    with open(cert_path) as f:
        configured_der = ssl.PEM_cert_to_DER_cert(f.read())
    assert served_der == configured_der, "Live nginx is not presenting /home/user/tls/cert.pem"

    cert_pub = subprocess.run(["openssl", "x509", "-in", cert_path, "-pubkey", "-noout"], check=True, capture_output=True).stdout
    key_pub = subprocess.run(["openssl", "pkey", "-in", key_path, "-pubout"], check=True, capture_output=True).stdout
    assert cert_pub == key_pub, "TLS certificate and private key do not match"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
