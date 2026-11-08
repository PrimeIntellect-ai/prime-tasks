#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pwd
import random
import re
import socket
import string
import subprocess
import tempfile
import urllib.error
import urllib.request
import uuid

import pytest

CLASSIFIER = "/home/user/classifier.py"
NGINX_CONFIG = "/home/user/nginx/nginx.conf"


def fetch(url):
    req = urllib.request.Request(url, headers={"X-Verification-Nonce": uuid.uuid4().hex})
    with urllib.request.urlopen(req, timeout=3) as response:
        return response.getcode(), response.read()


def listening_socket_inodes(port):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table, "r", encoding="ascii") as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) < 10 or fields[3] != "0A":
                        continue
                    if int(fields[1].rsplit(":", 1)[1], 16) == port:
                        inodes.add(fields[9])
        except FileNotFoundError:
            pass
    return inodes


def socket_owner_pids(inodes):
    owners = set()
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                match = re.fullmatch(r"socket:\[(\d+)\]", target)
                if match and match.group(1) in inodes:
                    owners.add(int(entry))
                    break
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue
    return owners


def process_info(pid):
    with open(f"/proc/{pid}/status", "r", encoding="utf-8") as f:
        status = f.read()
    uid_match = re.search(r"^Uid:\s+(\d+)", status, re.MULTILINE)
    with open(f"/proc/{pid}/cmdline", "rb") as f:
        cmdline = f.read().replace(b"\0", b" ").decode("utf-8", "replace")
    with open(f"/proc/{pid}/comm", "r", encoding="utf-8") as f:
        comm = f.read().strip()
    return int(uid_match.group(1)), cmdline, comm


def test_nginx_proxy_fixed():
    """Retain the original 200 check and verify that the listener is the requested Nginx proxy."""
    url = "http://127.0.0.1:9090/"
    try:
        proxy_status, proxy_body = fetch(url)
    except urllib.error.HTTPError as e:
        pytest.fail(f"Nginx returned HTTP error: {e.code}")
    except urllib.error.URLError as e:
        pytest.fail(f"Failed to connect to Nginx at {url}. Is it running? Error: {e.reason}")
    except Exception as e:
        pytest.fail(f"Unexpected error when testing Nginx: {e}")
    assert proxy_status == 200, f"Expected Nginx to return 200 OK, got {proxy_status}"

    backend_status, backend_body = fetch("http://127.0.0.1:8080/")
    assert backend_status == 200, "The specified backend on port 8080 did not return 200"
    assert proxy_body == backend_body, "Port 9090 did not return the backend response body"

    assert os.path.isfile(NGINX_CONFIG), f"Missing Nginx config: {NGINX_CONFIG}"
    user_record = pwd.getpwnam("user")

    def demote():
        os.setgroups([])
        os.setgid(user_record.pw_gid)
        os.setuid(user_record.pw_uid)

    checked = subprocess.run(
        ["/usr/sbin/nginx", "-T", "-c", NGINX_CONFIG],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=5,
        preexec_fn=demote,
        env={"PATH": "/usr/sbin:/usr/bin:/sbin:/bin", "HOME": user_record.pw_dir},
    )
    rendered = checked.stdout + "\n" + checked.stderr
    assert checked.returncode == 0, f"Nginx configuration is invalid:\n{rendered}"
    assert re.search(r"proxy_pass\s+http://127\.0\.0\.1:8080\s*;", rendered), \
        "The supplied config does not proxy to 127.0.0.1:8080"

    inodes = listening_socket_inodes(9090)
    assert inodes, "No process is listening on port 9090"
    owners = socket_owner_pids(inodes)
    assert owners, "Could not identify the process listening on port 9090"

    owner_info = []
    for pid in owners:
        try:
            owner_info.append(process_info(pid))
        except (FileNotFoundError, ProcessLookupError):
            pass
    assert any(uid == user_record.pw_uid and (comm == "nginx" or "nginx" in cmd)
               for uid, cmd, comm in owner_info), \
        "Port 9090 is not served by Nginx running as user"

    matching_master = False
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        try:
            uid, cmd, comm = process_info(int(entry))
        except (FileNotFoundError, ProcessLookupError, PermissionError):
            continue
        if (uid == user_record.pw_uid and (comm == "nginx" or "nginx" in cmd)
                and NGINX_CONFIG in cmd and "master process" in cmd):
            matching_master = True
            break
    assert matching_master, "Nginx was not started as user with /home/user/nginx/nginx.conf"


def test_classifier_script_exists():
    assert os.path.isfile(CLASSIFIER), f"Classifier script not found at {CLASSIFIER}"


def run_classifier(path):
    return subprocess.run(
        ["python3", CLASSIFIER, path],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=3,
    ).returncode


def test_classifier_accuracy():
    """Retain evaluation of the supplied corpora."""
    clean_dir = "/app/corpus/clean/"
    evil_dir = "/app/corpus/evil/"

    assert os.path.isfile(CLASSIFIER), f"Classifier script missing at {CLASSIFIER}"
    assert os.path.isdir(clean_dir), f"Clean corpus missing at {clean_dir}"
    assert os.path.isdir(evil_dir), f"Evil corpus missing at {evil_dir}"

    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir)
                   if os.path.isfile(os.path.join(clean_dir, f))]
    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir)
                  if os.path.isfile(os.path.join(evil_dir, f))]
    assert clean_files, "No files found in clean corpus directory."
    assert evil_files, "No files found in evil corpus directory."

    failed_clean = [os.path.basename(p) for p in clean_files if run_classifier(p) != 0]
    failed_evil = [os.path.basename(p) for p in evil_files if run_classifier(p) != 1]
    errors = []
    if failed_evil:
        errors.append(f"{len(failed_evil)} of {len(evil_files)} evil bypassed: {', '.join(failed_evil)}")
    if failed_clean:
        errors.append(f"{len(failed_clean)} of {len(clean_files)} clean modified/rejected: {', '.join(failed_clean)}")
    if errors:
        pytest.fail(" | ".join(errors))


def expected_result(raw):
    normalized = raw.replace("\r\n", "\n")
    head, separator, body = normalized.partition("\n\n")
    headers = {}
    for line in head.split("\n")[1:]:
        if ":" in line:
            name, value = line.split(":", 1)
            headers.setdefault(name.strip().lower(), []).append(value.strip())
    user_agent = " ".join(headers.get("user-agent", []))
    ua_evil = re.search(r"(?<![A-Za-z0-9_])sqlmap(?![A-Za-z0-9_])", user_agent) is not None
    body_evil = re.search(r"\bDROP\b", body, re.IGNORECASE) is not None
    union_evil = re.search(r"\bUNION SELECT\b", body, re.IGNORECASE) is not None
    return 1 if ua_evil or body_evil or union_evil else 0


def test_classifier_hidden_requests():
    """Exercise fresh, unlabeled paths and derive answers from each raw request."""
    nonce = uuid.uuid4().hex
    requests = [
        f"GET /{nonce} HTTP/1.1\r\nHost: localhost\r\nUser-Agent: Browser/1.0\r\n\r\n",
        f"GET /{nonce} HTTP/1.1\nHost: localhost\nuser-agent: audit sqlmap/2.0\n\n",
        "POST /submit HTTP/1.1\r\nHost: localhost\r\nUser-Agent: curl/8\r\n\r\nplease dRoP table accounts",
        "POST /submit HTTP/1.1\nHost: localhost\nUser-Agent: curl/8\n\nvalue=uNiOn SeLeCt password",
        "POST /submit HTTP/1.1\r\nHost: localhost\r\nUser-Agent: xsqlmapper\r\nX-Note: DROP UNION SELECT\r\n\r\nsqlmap is harmless here",
        "POST /submit HTTP/1.1\nHost: localhost\nUser-Agent: Browser\n\nDROPLET and reunion selected",
    ]

    alphabet = string.ascii_letters + string.digits
    for _ in range(24):
        token = "".join(random.SystemRandom().choice(alphabet) for _ in range(24))
        kind = random.SystemRandom().choice(("clean", "ua", "drop", "union"))
        ua = f"Client/{token}"
        body = f"message={token}"
        if kind == "ua":
            ua = f"scanner sqlmap/{token}"
        elif kind == "drop":
            body += " ; DrOp table sessions"
        elif kind == "union":
            body += " UnIoN SeLeCt secret"
        requests.append(
            f"POST /api/{token} HTTP/1.1\r\nHost: localhost\r\nUser-Agent: {ua}\r\n"
            f"Content-Length: {len(body)}\r\n\r\n{body}"
        )

    random.SystemRandom().shuffle(requests)
    with tempfile.TemporaryDirectory(prefix="request-evaluation-") as directory:
        failures = []
        for raw in requests:
            path = os.path.join(directory, uuid.uuid4().hex)
            with open(path, "w", encoding="utf-8", newline="") as f:
                f.write(raw)
            expected = expected_result(raw)
            actual = run_classifier(path)
            if actual != expected:
                failures.append((os.path.basename(path), expected, actual))
        assert not failures, f"Classifier failed hidden requests: {failures}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
