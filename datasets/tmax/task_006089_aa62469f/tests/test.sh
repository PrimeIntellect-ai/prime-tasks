#!/bin/bash
mkdir -p /logs/verifier

cleanup() {
    pkill -f '/home/user/backend.py' 2>/dev/null || true
    nginx -p /home/user/nginx -c /home/user/nginx/conf/nginx.conf -s stop 2>/dev/null || true
    pkill -x nginx 2>/dev/null || true
}

if (
    set -e
    trap cleanup EXIT

    cleanup

    # Exercise the required script from a clean task state, then verify that
    # four additional executions make no changes to the relevant state.
    python3 <<'PY'
import hashlib
import os
import shutil
import stat
import subprocess

script = "/home/user/idempotent_setup.py"
passwd = "/home/user/mock_passwd"
cert_dir = "/home/user/nginx/certs"

assert os.path.isfile(script), f"{script} is missing or is not a regular file"
with open(script, "rb") as f:
    source = f.read()
assert source, f"{script} is empty"
compile(source, script, "exec")

with open(passwd, "w", encoding="utf-8") as f:
    f.write(
        "root:x:0:0:root:/root:/bin/bash\n"
        "bin:x:2:2:bin:/bin:/usr/sbin/nologin\n"
        "user:x:1000:1000:User:/home/user:/bin/bash\n"
    )

if os.path.lexists(cert_dir):
    if os.path.isdir(cert_dir) and not os.path.islink(cert_dir):
        shutil.rmtree(cert_dir)
    else:
        os.unlink(cert_dir)


def run_script():
    subprocess.run(
        ["runuser", "-u", "user", "--", "python3", script],
        check=True,
        timeout=60,
    )


def entry_state(path):
    st = os.lstat(path)
    base = (
        stat.S_IFMT(st.st_mode), stat.S_IMODE(st.st_mode), st.st_uid, st.st_gid,
        st.st_size, st.st_mtime_ns, st.st_ctime_ns,
    )
    if stat.S_ISREG(st.st_mode):
        with open(path, "rb") as f:
            return base + (hashlib.sha256(f.read()).hexdigest(),)
    if stat.S_ISLNK(st.st_mode):
        return base + (os.readlink(path),)
    return base


def snapshot():
    result = {"mock_passwd": entry_state(passwd)}
    assert os.path.isdir(cert_dir) and not os.path.islink(cert_dir)
    result["certs/."] = entry_state(cert_dir)
    for root, dirs, files in os.walk(cert_dir, followlinks=False):
        for name in sorted(dirs + files):
            path = os.path.join(root, name)
            rel = os.path.relpath(path, cert_dir)
            result["certs/" + rel] = entry_state(path)
    return result

run_script()
first = snapshot()
for _ in range(4):
    run_script()
assert snapshot() == first, "Running idempotent_setup.py repeatedly changed the configured state"
PY

    cat <<'TEST_EOF' > /tmp/test_final_state.py
import datetime
import os
import re
import subprocess

EXPECTED_USER = "nginx_user:x:1005:1005:Nginx Dummy User:/home/user/nginx:/bin/false"
CRT = "/home/user/nginx/certs/server.crt"
KEY = "/home/user/nginx/certs/server.key"


def openssl(*args, input_data=None):
    return subprocess.run(
        ["openssl", *args], input=input_data, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, check=True, timeout=20
    ).stdout


def test_mock_passwd_updated():
    file_path = "/home/user/mock_passwd"
    assert os.path.isfile(file_path), f"{file_path} is missing."
    with open(file_path, "r") as f:
        content = f.read()
    assert EXPECTED_USER in content, f"'{EXPECTED_USER}' not found in {file_path}."
    count = content.count(EXPECTED_USER)
    assert count == 1, f"Expected exactly 1 occurrence of the nginx_user line in {file_path}, found {count}."
    assert sum(line == EXPECTED_USER for line in content.splitlines()) == 1


def test_tls_certs_exist():
    assert os.path.isfile(CRT) and not os.path.islink(CRT), f"TLS certificate {CRT} is missing."
    assert os.path.isfile(KEY) and not os.path.islink(KEY), f"TLS private key {KEY} is missing."
    assert os.path.getsize(CRT) > 0, f"TLS certificate {CRT} is empty."
    assert os.path.getsize(KEY) > 0, f"TLS private key {KEY} is empty."


def test_tls_certificate_and_key_are_valid():
    cert_text = openssl("x509", "-in", CRT, "-noout", "-text").decode()
    assert re.search(r"Public-Key:\s*\(2048 bit\)", cert_text), "Certificate is not 2048-bit RSA"

    subject = openssl("x509", "-in", CRT, "-noout", "-subject", "-nameopt", "RFC2253").decode().strip()
    issuer = openssl("x509", "-in", CRT, "-noout", "-issuer", "-nameopt", "RFC2253").decode().strip()
    assert subject == "subject=CN=localhost", f"Unexpected certificate subject: {subject}"
    assert issuer.replace("issuer=", "", 1) == subject.replace("subject=", "", 1), "Certificate is not self-signed"
    openssl("verify", "-CAfile", CRT, CRT)

    dates = openssl("x509", "-in", CRT, "-noout", "-dates").decode().splitlines()
    values = dict(line.split("=", 1) for line in dates)
    fmt = "%b %d %H:%M:%S %Y GMT"
    not_before = datetime.datetime.strptime(values["notBefore"], fmt).replace(tzinfo=datetime.timezone.utc)
    not_after = datetime.datetime.strptime(values["notAfter"], fmt).replace(tzinfo=datetime.timezone.utc)
    assert not_after - not_before == datetime.timedelta(days=365), "Certificate is not valid for 365 days"
    now = datetime.datetime.now(datetime.timezone.utc)
    assert not_before <= now <= not_after, "Certificate is not currently valid"

    key_text = openssl("pkey", "-in", KEY, "-noout", "-text").decode()
    assert re.search(r"(?:Private-Key|RSA Private-Key):\s*\(2048 bit", key_text), "Private key is not 2048-bit RSA"
    openssl("pkey", "-in", KEY, "-check", "-noout")
    cert_pub = openssl("x509", "-in", CRT, "-pubkey", "-noout")
    key_pub = openssl("pkey", "-in", KEY, "-pubout")
    assert cert_pub == key_pub, "Certificate and private key do not match"


def test_nginx_conf_fixed():
    file_path = "/home/user/nginx/conf/nginx.conf"
    assert os.path.isfile(file_path), f"{file_path} is missing."
    with open(file_path, "r") as f:
        content = f.read()
    assert "proxy_pass http://127.0.0.1:8000;" in content, "nginx.conf does not contain the corrected proxy_pass directive pointing to port 8000."
    assert "proxy_pass http://127.0.0.1:9999;" not in content, "nginx.conf still contains the misconfigured proxy_pass directive pointing to port 9999."


def test_proxy_test_log():
    file_path = "/home/user/proxy_test.log"
    assert os.path.isfile(file_path), f"{file_path} is missing. Did you run the curl command and redirect output?"
    with open(file_path, "r") as f:
        content = f.read().strip()
    expected_content = "Backend Application Running!"
    assert content == expected_content, f"Expected '{expected_content}' in {file_path}, but got '{content}'."


def test_idempotent_setup_script_exists():
    file_path = "/home/user/idempotent_setup.py"
    assert os.path.isfile(file_path), f"{file_path} is missing."
TEST_EOF

    python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short

    rm -f /home/user/nginx/nginx.pid
    python3 /home/user/backend.py >/tmp/verifier_backend.log 2>&1 &
    backend_pid=$!
    backend_ok=0
    for _ in $(seq 1 30); do
        if [ "$(curl -sS --max-time 1 http://127.0.0.1:8000 2>/dev/null || true)" = "Backend Application Running!" ]; then
            backend_ok=1
            break
        fi
        kill -0 "$backend_pid" 2>/dev/null || break
        sleep 0.2
    done
    [ "$backend_ok" -eq 1 ]

    nginx -t -p /home/user/nginx -c /home/user/nginx/conf/nginx.conf
    nginx -p /home/user/nginx -c /home/user/nginx/conf/nginx.conf

    proxy_ok=0
    for _ in $(seq 1 30); do
        if curl -k -sS --max-time 2 https://127.0.0.1:8443 > /tmp/verifier_proxy_response 2>/dev/null; then
            if [ "$(cat /tmp/verifier_proxy_response)" = "Backend Application Running!" ]; then
                proxy_ok=1
                break
            fi
        fi
        sleep 0.2
    done
    [ "$proxy_ok" -eq 1 ]
); then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
