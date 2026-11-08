#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import configparser
import datetime
import os
import pwd
import re
import shlex
import socket
import ssl
import subprocess
import time
import uuid

import pytest

BASE = "/home/user/microservices"
SUPERVISOR_CONF = BASE + "/supervisord.conf"
NGINX_CONF = BASE + "/nginx.conf"
CERT = BASE + "/certs/cert.pem"
KEY = BASE + "/certs/key.pem"


def run(args, timeout=10, input_data=None):
    return subprocess.run(
        args, input=input_data, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        timeout=timeout, check=True
    )


def proc_info(pid):
    with open(f"/proc/{pid}/status") as f:
        status = f.read()
    with open(f"/proc/{pid}/cmdline", "rb") as f:
        cmdline = f.read().replace(b"\0", b" ").decode(errors="replace").strip()
    ppid = int(re.search(r"^PPid:\s+(\d+)$", status, re.M).group(1))
    uid = int(re.search(r"^Uid:\s+(\d+)", status, re.M).group(1))
    return ppid, uid, cmdline


def supervisorctl(*args):
    return run(["supervisorctl", "-c", SUPERVISOR_CONF, *args]).stdout.decode()


def program_pid(name):
    value = supervisorctl("pid", name).strip()
    assert value.isdigit() and int(value) > 1, f"No live PID reported for {name}: {value!r}"
    pid = int(value)
    assert os.path.isdir(f"/proc/{pid}"), f"Reported {name} PID does not exist"
    return pid


def test_tls_certificates_exist():
    cert_path = "/home/user/microservices/certs/cert.pem"
    key_path = "/home/user/microservices/certs/key.pem"
    assert os.path.isfile(cert_path), f"Certificate file missing: {cert_path}"
    assert os.path.isfile(key_path), f"Key file missing: {key_path}"


def test_tls_certificates_are_valid_and_match():
    cert_text = run(["openssl", "x509", "-in", CERT, "-noout", "-text"]).stdout.decode()
    assert re.search(r"Public-Key:\s*\(2048 bit\)", cert_text), "Certificate is not RSA 2048-bit"
    assert "rsaEncryption" in cert_text, "Certificate does not contain an RSA public key"

    dates = run(["openssl", "x509", "-in", CERT, "-noout", "-dates"]).stdout.decode()
    not_before = re.search(r"notBefore=(.+)", dates).group(1).strip()
    not_after = re.search(r"notAfter=(.+)", dates).group(1).strip()
    fmt = "%b %d %H:%M:%S %Y %Z"
    start = datetime.datetime.strptime(not_before, fmt).replace(tzinfo=datetime.timezone.utc)
    end = datetime.datetime.strptime(not_after, fmt).replace(tzinfo=datetime.timezone.utc)
    now = datetime.datetime.now(datetime.timezone.utc)
    assert start <= now <= end, "Certificate is not currently valid"
    assert datetime.timedelta(days=364, hours=23) <= end - start <= datetime.timedelta(days=365, hours=1), "Certificate validity is not 365 days"

    key_check = run(["openssl", "pkey", "-in", KEY, "-noout", "-text"]).stdout.decode()
    assert "2048 bit" in key_check, "Private key is not 2048-bit"
    cert_pub = run(["openssl", "x509", "-in", CERT, "-pubkey", "-noout"]).stdout
    key_pub = run(["openssl", "pkey", "-in", KEY, "-pubout"]).stdout
    assert cert_pub == key_pub, "Certificate and private key do not match"


def test_nginx_config_content():
    conf_path = "/home/user/microservices/nginx.conf"
    assert os.path.isfile(conf_path), f"Nginx config missing: {conf_path}"

    with open(conf_path, "r") as f:
        content = f.read()

    assert re.search(r"listen\s+8443\s+ssl", content) or re.search(r"listen\s+.*8443.*ssl", content), "Nginx config missing 'listen 8443 ssl'"
    assert "cert.pem" in content, "Nginx config missing cert.pem reference"
    assert "key.pem" in content, "Nginx config missing key.pem reference"
    assert "root /home/user/microservices/www" in content or "root\s+/home/user/microservices/www" in content, "Nginx config missing correct root directive"
    assert "nginx.pid" in content, "Nginx config missing pid directive"
    assert "nginx_access.log" in content, "Nginx config missing access_log directive"
    assert "nginx_error.log" in content, "Nginx config missing error_log directive"


def test_nginx_effective_configuration():
    result = run(["nginx", "-t", "-T", "-c", NGINX_CONF])
    effective = (result.stdout + result.stderr).decode()
    assert re.search(r"^\s*listen\s+[^;]*\b8443\b[^;]*\bssl\b[^;]*;", effective, re.M)
    assert re.search(r"^\s*ssl_certificate\s+/home/user/microservices/certs/cert\.pem\s*;", effective, re.M)
    assert re.search(r"^\s*ssl_certificate_key\s+/home/user/microservices/certs/key\.pem\s*;", effective, re.M)
    assert re.search(r"^\s*root\s+/home/user/microservices/www\s*;", effective, re.M)
    assert re.search(r"^\s*pid\s+/home/user/microservices/nginx\.pid\s*;", effective, re.M)
    assert re.search(r"^\s*access_log\s+/home/user/microservices/nginx_access\.log(?:\s+[^;]+)?\s*;", effective, re.M)
    assert re.search(r"^\s*error_log\s+/home/user/microservices/nginx_error\.log(?:\s+[^;]+)?\s*;", effective, re.M)


def test_supervisord_config_content():
    conf_path = "/home/user/microservices/supervisord.conf"
    assert os.path.isfile(conf_path), f"Supervisord config missing: {conf_path}"

    with open(conf_path, "r") as f:
        content = f.read()

    assert "[program:webapp]" in content, "Supervisord config missing [program:webapp]"
    assert "[program:mailer]" in content, "Supervisord config missing [program:mailer]"
    assert "autorestart" in content.lower(), "Supervisord config missing autorestart directives"
    assert "supervisord.log" in content, "Supervisord config missing log directive"
    assert "supervisord.pid" in content, "Supervisord config missing pid directive"


def test_supervisord_configuration_semantics():
    cfg = configparser.RawConfigParser()
    assert cfg.read(SUPERVISOR_CONF) == [SUPERVISOR_CONF]
    assert cfg.get("supervisord", "logfile") == BASE + "/supervisord.log"
    assert cfg.get("supervisord", "pidfile") == BASE + "/supervisord.pid"

    web_cmd = shlex.split(cfg.get("program:webapp", "command"))
    mail_cmd = shlex.split(cfg.get("program:mailer", "command"))
    assert web_cmd == ["nginx", "-c", NGINX_CONF, "-g", "daemon off;"]
    assert mail_cmd == ["bash", BASE + "/mailer.sh"]
    for section in ("program:webapp", "program:mailer"):
        assert cfg.get(section, "autorestart").strip().lower() in ("true", "unexpected")


def test_processes_running():
    try:
        ps_output = subprocess.check_output(["ps", "aux"]).decode("utf-8")
    except subprocess.CalledProcessError:
        pytest.fail("Failed to execute 'ps aux'")

    assert "supervisord" in ps_output, "supervisord is not running"
    assert "nginx" in ps_output, "nginx is not running"
    assert "mailer.sh" in ps_output or "nc -l -p 8025" in ps_output, "mailer script is not running"


def test_services_are_really_managed_by_supervisord():
    actual = supervisorctl("status")
    assert re.search(r"^webapp\s+RUNNING\b", actual, re.M), actual
    assert re.search(r"^mailer\s+RUNNING\b", actual, re.M), actual

    with open(BASE + "/supervisord.pid") as f:
        supervisor_pid = int(f.read().strip())
    assert os.path.isdir(f"/proc/{supervisor_pid}"), "supervisord.pid is stale"
    _, supervisor_uid, supervisor_cmd = proc_info(supervisor_pid)
    expected_uid = pwd.getpwnam("user").pw_uid
    assert supervisor_uid == expected_uid, "supervisord is not running as the non-root user"
    assert "supervisord" in supervisor_cmd and SUPERVISOR_CONF in supervisor_cmd

    web_pid = program_pid("webapp")
    mail_pid = program_pid("mailer")
    web_ppid, web_uid, web_cmd = proc_info(web_pid)
    mail_ppid, mail_uid, mail_cmd = proc_info(mail_pid)
    assert web_ppid == supervisor_pid and mail_ppid == supervisor_pid, "Programs are not direct supervisord children"
    assert web_uid == expected_uid and mail_uid == expected_uid, "Services are not running as the current non-root user"
    assert "nginx" in web_cmd and NGINX_CONF in web_cmd and "daemon off;" in web_cmd
    assert "bash" in mail_cmd and BASE + "/mailer.sh" in mail_cmd

    with open(BASE + "/nginx.pid") as f:
        assert int(f.read().strip()) == web_pid, "nginx.pid does not identify supervised nginx master"
    assert os.path.isfile(BASE + "/nginx_access.log")
    assert os.path.isfile(BASE + "/nginx_error.log")


def test_ports_listening():
    s8443 = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    result8443 = s8443.connect_ex(('127.0.0.1', 8443))
    s8443.close()
    assert result8443 == 0, "Port 8443 (nginx) is not listening"

    s8025 = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    result8025 = s8025.connect_ex(('127.0.0.1', 8025))
    s8025.close()
    assert result8025 == 0, "Port 8025 (mailer) is not listening"


def test_nginx_serves_workspace_over_tls_with_generated_certificate():
    marker = "verifier-" + uuid.uuid4().hex
    filename = marker + ".txt"
    path = BASE + "/www/" + filename
    with open(path, "w") as f:
        f.write(marker)
    try:
        context = ssl.create_default_context()
        context.check_hostname = False
        context.verify_mode = ssl.CERT_NONE
        with socket.create_connection(("127.0.0.1", 8443), timeout=5) as raw:
            with context.wrap_socket(raw, server_hostname="localhost") as tls:
                peer_der = tls.getpeercert(binary_form=True)
                request = f"GET /{filename} HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n"
                tls.sendall(request.encode())
                chunks = []
                while True:
                    chunk = tls.recv(4096)
                    if not chunk:
                        break
                    chunks.append(chunk)
        response = b"".join(chunks)
        assert re.match(br"HTTP/1\.[01] 200\b", response), response[:200]
        assert marker.encode() in response
        expected_der = run(["openssl", "x509", "-in", CERT, "-outform", "DER"]).stdout
        assert peer_der == expected_der, "Port 8443 is not serving the generated certificate"
    finally:
        os.unlink(path)


def test_mailer_speaks_mock_smtp_protocol():
    with socket.create_connection(("127.0.0.1", 8025), timeout=5) as sock:
        sock.settimeout(5)
        response = sock.recv(1024)
    assert response.startswith(b"220 Mock SMTP Ready"), response


def test_status_log_content():
    log_path = "/home/user/status.log"
    assert os.path.isfile(log_path), f"Status log missing: {log_path}"

    with open(log_path, "r") as f:
        content = f.read()

    assert re.search(r"webapp\s+RUNNING", content), "Status log does not show webapp as RUNNING"
    assert re.search(r"mailer\s+RUNNING", content), "Status log does not show mailer as RUNNING"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
