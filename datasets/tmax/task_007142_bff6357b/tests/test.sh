#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import shlex
import signal
import sqlite3
import subprocess
import tempfile
import time


def expected_rows():
    return [("mailer", "mail"), ("webadmin", "wheel")]


def validate_database(db_path):
    assert os.path.isfile(db_path), f"Database file {db_path} does not exist."
    conn = sqlite3.connect(db_path)
    try:
        cursor = conn.cursor()
        cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='users';")
        assert cursor.fetchone() is not None, "Table 'users' does not exist in the database."

        cursor.execute("PRAGMA table_info(users)")
        schema = cursor.fetchall()
        assert len(schema) == 3, f"Expected exactly three users columns, got {schema}."
        normalized = [(row[1], row[2].upper(), row[5]) for row in schema]
        assert normalized == [
            ("id", "INTEGER", 1),
            ("username", "TEXT", 0),
            ("group_name", "TEXT", 0),
        ], f"Unexpected users table schema: {schema}."

        cursor.execute("SELECT username, group_name FROM users ORDER BY username")
        rows = cursor.fetchall()
        assert rows == expected_rows(), f"Expected users {expected_rows()}, but got {rows}."
    finally:
        conn.close()


def test_directories_exist():
    for directory in ["/home/user/data", "/home/user/tls", "/home/user/web"]:
        assert os.path.isdir(directory), f"Directory {directory} does not exist."


def test_sqlite_database():
    validate_database("/home/user/data/users.db")


def test_setup_users_script_executes_and_recreates_database():
    script = "/home/user/setup_users.py"
    db_path = "/home/user/data/users.db"
    assert os.path.isfile(script), f"User setup script {script} does not exist."

    for path in [db_path, db_path + "-wal", db_path + "-shm", db_path + "-journal"]:
        if os.path.exists(path):
            os.remove(path)

    result = subprocess.run(
        ["python3", script], capture_output=True, text=True, timeout=15
    )
    assert result.returncode == 0, (
        f"setup_users.py failed with status {result.returncode}: "
        f"{result.stderr or result.stdout}"
    )
    validate_database(db_path)


def run_checked(args):
    return subprocess.run(args, capture_output=True, text=True, timeout=15)


def test_tls_certificates():
    cert_path = "/home/user/tls/cert.pem"
    key_path = "/home/user/tls/key.pem"

    assert os.path.isfile(cert_path), f"Certificate file {cert_path} does not exist."
    assert os.path.isfile(key_path), f"Key file {key_path} does not exist."

    result = run_checked(["openssl", "x509", "-in", cert_path, "-noout", "-subject"])
    assert result.returncode == 0, "Failed to read certificate with openssl."
    assert "CN = localhost" in result.stdout or "CN=localhost" in result.stdout, \
        "Certificate Common Name (CN) is not 'localhost'."

    key_check = run_checked(["openssl", "pkey", "-in", key_path, "-check", "-noout"])
    assert key_check.returncode == 0, f"Private key is invalid: {key_check.stderr}"

    cert_text = run_checked(["openssl", "x509", "-in", cert_path, "-noout", "-text"])
    assert cert_text.returncode == 0, "Could not inspect the TLS certificate."
    assert "Public Key Algorithm: rsaEncryption" in cert_text.stdout, "Certificate key is not RSA."
    assert "Public-Key: (2048 bit)" in cert_text.stdout, "Certificate RSA key is not 2048-bit."

    verify = run_checked(["openssl", "verify", "-CAfile", cert_path, cert_path])
    assert verify.returncode == 0, f"Certificate is not valid as a self-signed certificate: {verify.stderr}"

    cert_pub = subprocess.run(
        ["openssl", "x509", "-in", cert_path, "-pubkey", "-noout"],
        capture_output=True, timeout=15
    )
    key_pub = subprocess.run(
        ["openssl", "pkey", "-in", key_path, "-pubout"],
        capture_output=True, timeout=15
    )
    assert cert_pub.returncode == 0 and key_pub.returncode == 0, "Could not derive public keys."
    assert cert_pub.stdout == key_pub.stdout, "Certificate and private key do not match."


def listening_inodes(port):
    result = set()
    for table in ["/proc/net/tcp", "/proc/net/tcp6"]:
        try:
            with open(table) as handle:
                next(handle)
                for line in handle:
                    fields = line.split()
                    local = fields[1]
                    state = fields[3]
                    if state == "0A" and int(local.rsplit(":", 1)[1], 16) == port:
                        result.add(fields[9])
        except FileNotFoundError:
            pass
    return result


def kill_existing_port_users(port):
    targets = listening_inodes(port)
    if not targets:
        return
    for entry in os.listdir("/proc"):
        if not entry.isdigit() or int(entry) == os.getpid():
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    link = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                match = re.fullmatch(r"socket:\[(\d+)\]", link)
                if match and match.group(1) in targets:
                    os.kill(int(entry), signal.SIGTERM)
                    break
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass
    time.sleep(0.5)


def process_listens_on_ipv4_loopback(pid, port):
    owned = set()
    fd_dir = f"/proc/{pid}/fd"
    try:
        for fd in os.listdir(fd_dir):
            try:
                link = os.readlink(f"{fd_dir}/{fd}")
            except OSError:
                continue
            match = re.fullmatch(r"socket:\[(\d+)\]", link)
            if match:
                owned.add(match.group(1))
    except (FileNotFoundError, PermissionError):
        return False

    try:
        with open("/proc/net/tcp") as handle:
            next(handle)
            for line in handle:
                fields = line.split()
                address, port_hex = fields[1].split(":")
                if (fields[3] == "0A" and fields[9] in owned and
                        int(port_hex, 16) == port and address == "0100007F"):
                    return True
    except FileNotFoundError:
        pass
    return False


def test_app_py_ssl_logic_and_live_https_service():
    app_path = "/home/user/web/app.py"
    assert os.path.isfile(app_path), f"Web server script {app_path} does not exist."

    with open(app_path, "r") as handle:
        content = handle.read()
    assert "ssl.SSLContext" in content or "ssl.wrap_socket" in content, \
        "Web server script does not appear to use the ssl module for HTTPS."

    kill_existing_port_users(9443)
    proc = subprocess.Popen(
        ["python3", app_path],
        cwd="/home/user/web",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        start_new_session=True,
    )
    header_path = None
    try:
        response = None
        with tempfile.NamedTemporaryFile(delete=False) as header_file:
            header_path = header_file.name

        deadline = time.time() + 10
        while time.time() < deadline:
            if proc.poll() is not None:
                stderr = proc.stderr.read().decode(errors="replace")
                raise AssertionError(f"app.py exited before serving HTTPS: {stderr}")
            response = subprocess.run(
                ["curl", "--insecure", "--silent", "--show-error", "--max-time", "2",
                 "--dump-header", header_path, "https://127.0.0.1:9443/"],
                capture_output=True,
            )
            if response.returncode == 0:
                break
            time.sleep(0.2)

        assert response is not None and response.returncode == 0, \
            f"Could not query app.py over HTTPS: {response.stderr.decode(errors='replace')}"
        assert proc.poll() is None, "app.py did not remain running as the web server."
        assert process_listens_on_ipv4_loopback(proc.pid, 9443), \
            "app.py is not listening specifically on IPv4 127.0.0.1:9443."
        assert response.stdout == b'{"status": "ok"}', \
            f"Unexpected response payload: {response.stdout!r}"

        with open(header_path, "rb") as handle:
            headers = handle.read().decode("iso-8859-1")
        header_blocks = [block for block in re.split(r"\r?\n\r?\n", headers) if block.strip()]
        final_headers = header_blocks[-1]
        lines = final_headers.splitlines()
        assert lines and re.match(r"^HTTP/\S+\s+200(?:\s|$)", lines[0]), \
            f"Root path did not return HTTP 200: {lines[0] if lines else headers}"
        parsed = {}
        for line in lines[1:]:
            if ":" in line:
                name, value = line.split(":", 1)
                parsed[name.strip().lower()] = value.strip().lower()
        assert parsed.get("content-type") == "application/json", \
            f"Expected Content-Type application/json, got {parsed.get('content-type')!r}."
    finally:
        if header_path and os.path.exists(header_path):
            os.remove(header_path)
        if proc.poll() is None:
            os.killpg(proc.pid, signal.SIGTERM)
            try:
                proc.wait(timeout=3)
            except subprocess.TimeoutExpired:
                os.killpg(proc.pid, signal.SIGKILL)
                proc.wait(timeout=3)


def docker_instructions(content):
    logical = []
    current = ""
    for raw in content.splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        current += (" " if current else "") + line
        if current.endswith("\\"):
            current = current[:-1].rstrip()
        else:
            logical.append(current)
            current = ""
    if current:
        logical.append(current)
    return logical


def test_dockerfile():
    dockerfile_path = "/home/user/web/Dockerfile"
    assert os.path.isfile(dockerfile_path), f"Dockerfile {dockerfile_path} does not exist."

    with open(dockerfile_path, "r") as handle:
        content = handle.read()

    assert "FROM python:3.10-slim" in content, "Dockerfile does not use python:3.10-slim as the base image."
    assert "USER appuser" in content, "Dockerfile does not switch to USER appuser."
    assert "EXPOSE 9443" in content, "Dockerfile does not EXPOSE port 9443."

    instructions = docker_instructions(content)
    assert any(re.match(r"(?i)^FROM\s+python:3\.10-slim(?:\s|$)", line) for line in instructions), \
        "Dockerfile base image instruction is invalid."

    user_creation_indexes = [i for i, line in enumerate(instructions) if
        re.match(r"(?i)^RUN\s+", line) and
        re.search(r"(?:^|[;&|]\s*|\s)(?:useradd|adduser)\b[^;&|]*\bappuser\b", line, re.I)]
    user_indexes = [i for i, line in enumerate(instructions) if re.match(r"(?i)^USER\s+appuser\s*$", line)]
    assert user_creation_indexes, "Dockerfile does not create the appuser account."
    assert user_indexes, "Dockerfile does not contain a valid USER appuser instruction."
    assert min(user_creation_indexes) < max(user_indexes), "appuser must be created before switching to it."

    copy_ok = False
    for line in instructions:
        if not re.match(r"(?i)^COPY\s+", line):
            continue
        try:
            tokens = shlex.split(line)
        except ValueError:
            continue
        args = [token for token in tokens[1:] if not token.startswith("--")]
        if len(args) >= 2:
            sources, destination = args[:-1], args[-1]
            if any(source in ("app.py", "./app.py") for source in sources) and \
                    destination in ("/app", "/app/", "/app/app.py"):
                copy_ok = True
    assert copy_ok, "Dockerfile does not COPY app.py into /app/."

    assert any(re.match(r"(?i)^EXPOSE\s+9443(?:/tcp)?\s*$", line) for line in instructions), \
        "Dockerfile does not contain a valid EXPOSE 9443 instruction."
    cmd_lines = [line for line in instructions if re.match(r"(?i)^CMD\s+", line)]
    assert cmd_lines, "Dockerfile does not set a CMD."
    assert any(re.search(r"\bpython(?:3(?:\.10)?)?\b", line, re.I) and
               re.search(r"(?:^|[/\"'\s,])app\.py(?:[\"'\s,\]]|$)", line)
               for line in cmd_lines), "Dockerfile CMD does not run app.py with Python."


def test_verification_log():
    log_path = "/home/user/verification.log"
    assert os.path.isfile(log_path), f"Verification log {log_path} does not exist."

    with open(log_path, "r") as handle:
        content = handle.read().strip()
    assert '{"status": "ok"}' in content, \
        "Verification log does not contain the exact expected JSON payload."

    with open(log_path, "rb") as handle:
        raw = handle.read()
    assert raw == b'{"status": "ok"}', \
        f"verification.log is not the exact curl standard output: {raw!r}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
