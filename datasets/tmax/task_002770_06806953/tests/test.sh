#!/bin/bash
set -e
mkdir -p /logs/verifier

OPENSSL_BIN="$(command -v openssl)"
NGINX_BIN="$(command -v nginx)"
OPENSSL_REAL="${OPENSSL_BIN}.verifier-real"
NGINX_REAL="${NGINX_BIN}.verifier-real"

restore_tools() {
    if [ -e "$OPENSSL_REAL" ]; then
        rm -f "$OPENSSL_BIN"
        mv "$OPENSSL_REAL" "$OPENSSL_BIN"
    fi
    if [ -e "$NGINX_REAL" ]; then
        rm -f "$NGINX_BIN"
        mv "$NGINX_REAL" "$NGINX_BIN"
    fi
}
trap restore_tools EXIT

mv "$OPENSSL_BIN" "$OPENSSL_REAL"
mv "$NGINX_BIN" "$NGINX_REAL"

cat > "$OPENSSL_BIN" <<EOF
#!/usr/bin/python3
import fcntl, json, os, subprocess, sys
real = "$OPENSSL_REAL"
log = "/tmp/verifier-openssl.jsonl"
def target(fd):
    try:
        return os.readlink("/proc/self/fd/%d" % fd)
    except OSError:
        return ""
p = subprocess.run([real] + sys.argv[1:], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
entry = {"argv": sys.argv[1:], "stdout_len": len(p.stdout), "stderr_len": len(p.stderr),
         "stdout_target": target(1), "stderr_target": target(2)}
with open(log, "a") as f:
    fcntl.flock(f, fcntl.LOCK_EX)
    f.write(json.dumps(entry) + "\\n")
sys.stdout.buffer.write(p.stdout)
sys.stderr.buffer.write(p.stderr)
sys.exit(p.returncode)
EOF
chmod 755 "$OPENSSL_BIN"

cat > "$NGINX_BIN" <<EOF
#!/usr/bin/python3
import fcntl, json, subprocess, sys
real = "$NGINX_REAL"
p = subprocess.run([real] + sys.argv[1:], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
with open("/tmp/verifier-nginx.jsonl", "a") as f:
    fcntl.flock(f, fcntl.LOCK_EX)
    f.write(json.dumps({"argv": sys.argv[1:]}) + "\\n")
sys.stdout.buffer.write(p.stdout)
sys.stderr.buffer.write(p.stderr)
sys.exit(p.returncode)
EOF
chmod 755 "$NGINX_BIN"

cat << 'TEST_EOF' > /tmp/test_final_state.py
import datetime
import hashlib
import json
import os
import re
import secrets
import shutil
import subprocess

SCRIPT_PATH = "/home/user/setup_local_proxy.sh"
CERTS_DIR = "/home/user/certs"
CERT_PATH = os.path.join(CERTS_DIR, "cert.pem")
KEY_PATH = os.path.join(CERTS_DIR, "key.pem")
PROXY_CONF = "/home/user/proxy.conf"
DEPLOY_LOG = "/home/user/deploy.log"
OPENSSL = os.environ["OPENSSL_REAL"]
NGINX = os.environ["NGINX_REAL"]
OPENSSL_LOG = "/tmp/verifier-openssl.jsonl"
NGINX_LOG = "/tmp/verifier-nginx.jsonl"


def command(args, **kwargs):
    return subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                          text=True, check=True, **kwargs)


def read_json_lines(path):
    if not os.path.exists(path):
        return []
    with open(path) as f:
        return [json.loads(line) for line in f if line.strip()]


def option_value(args, option):
    try:
        return args[args.index(option) + 1]
    except (ValueError, IndexError):
        return None


def generation_is_silent(call):
    # Output suppressed with /dev/null is silent even though the wrapper observes
    # OpenSSL's bytes before forwarding them to the redirection.
    out_ok = call["stdout_len"] == 0 or call["stdout_target"] == "/dev/null"
    err_ok = call["stderr_len"] == 0 or call["stderr_target"] == "/dev/null"
    return out_ok and err_ok


def validate_certificate():
    subject = command([OPENSSL, "x509", "-in", CERT_PATH, "-noout",
                       "-subject", "-nameopt", "RFC2253"]).stdout.strip()
    issuer = command([OPENSSL, "x509", "-in", CERT_PATH, "-noout",
                      "-issuer", "-nameopt", "RFC2253"]).stdout.strip()
    assert subject == "subject=CN=localhost", subject
    assert issuer == "issuer=CN=localhost", issuer

    text = command([OPENSSL, "x509", "-in", CERT_PATH, "-noout", "-text"]).stdout
    assert "Public Key Algorithm: rsaEncryption" in text
    assert re.search(r"Public-Key:\s*\(2048 bit\)", text)

    dates = command([OPENSSL, "x509", "-in", CERT_PATH, "-noout",
                     "-startdate", "-enddate"]).stdout.splitlines()
    values = dict(line.split("=", 1) for line in dates)
    fmt = "%b %d %H:%M:%S %Y %Z"
    not_before = datetime.datetime.strptime(values["notBefore"], fmt)
    not_after = datetime.datetime.strptime(values["notAfter"], fmt)
    assert not_after - not_before == datetime.timedelta(days=365)

    verify = command([OPENSSL, "verify", "-CAfile", CERT_PATH, CERT_PATH])
    assert verify.stdout.strip().endswith(": OK")

    cert_pub = command([OPENSSL, "x509", "-in", CERT_PATH,
                        "-pubkey", "-noout"]).stdout
    key_pub = command([OPENSSL, "pkey", "-in", KEY_PATH,
                       "-pubout"]).stdout
    assert cert_pub == key_pub, "Certificate and private key do not match"


def validate_config():
    assert os.path.isfile(PROXY_CONF), f"Nginx config not found at {PROXY_CONF}"
    result = subprocess.run([NGINX, "-t", "-c", PROXY_CONF],
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            text=True)
    assert result.returncode == 0, result.stderr

    with open(PROXY_CONF) as f:
        content = f.read()
    assert "events" in content, "Config missing 'events' block"
    assert "http" in content, "Config missing 'http' block"
    assert "server" in content, "Config missing 'server' block"
    assert re.search(r"pid\s+/home/user/nginx\.pid\s*;", content)
    assert re.search(r"error_log\s+/home/user/error\.log\s*;", content)
    assert re.search(r"access_log\s+/home/user/access\.log\s*;", content)
    assert re.search(r"listen\s+127\.0\.0\.1:8443\s+ssl\s*;", content)
    assert re.search(r"ssl_certificate\s+/home/user/certs/cert\.pem\s*;", content)
    assert re.search(r"ssl_certificate_key\s+/home/user/certs/key\.pem\s*;", content)
    assert re.search(r"proxy_pass\s+http://127\.0\.0\.1:8080/?\s*;", content)

    uncommented = re.sub(r"#.*", "", content)
    assert not re.search(r"(?m)^\s*user\s+", uncommented), "Config contains a user directive"
    assert re.search(r"location\s+/\s*\{[^{}]*proxy_pass\s+http://127\.0\.0\.1:8080/?\s*;",
                     uncommented, re.S), "location / does not proxy to the required upstream"


def test_complete_script_behavior():
    assert os.path.isfile(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}"
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script at {SCRIPT_PATH} is not executable"
    with open(SCRIPT_PATH, "rb") as f:
        first_line = f.readline().decode("utf-8", "replace")
    assert first_line.startswith("#!") and "bash" in first_line, "Artifact is not a Bash script"

    generated_cert_hashes = []
    for _ in range(2):
        tier = "audit_" + secrets.token_hex(12)
        shutil.rmtree(CERTS_DIR, ignore_errors=True)
        for path in (PROXY_CONF, DEPLOY_LOG, "/home/user/nginx.pid",
                     "/home/user/error.log", "/home/user/access.log",
                     OPENSSL_LOG, NGINX_LOG):
            try:
                os.remove(path)
            except FileNotFoundError:
                pass

        sentinel = "preexisting-log-entry"
        with open(DEPLOY_LOG, "w") as f:
            f.write(sentinel + "\n")
        os.chown(DEPLOY_LOG, 1000, 1000)
        os.chmod(DEPLOY_LOG, 0o666)
        for log in (OPENSSL_LOG, NGINX_LOG):
            open(log, "w").close()
            os.chmod(log, 0o666)

        process = subprocess.run(
            ["runuser", "-u", "user", "--", SCRIPT_PATH],
            input=tier + "\n", stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True, timeout=45
        )
        assert process.returncode == 0, process.stderr
        output = process.stdout + process.stderr
        prompt = "Enter deployment tier: "
        assert output.count(prompt) == 1, "Prompt was not emitted exactly once"
        pos = output.index(prompt) + len(prompt)
        assert pos == len(output) or output[pos] != "\n", "Prompt had a trailing newline"

        assert os.path.isdir(CERTS_DIR)
        assert os.path.isfile(CERT_PATH)
        assert os.path.isfile(KEY_PATH)
        validate_certificate()
        validate_config()

        openssl_calls = read_json_lines(OPENSSL_LOG)
        key_generators = []
        cert_generators = []
        for call in openssl_calls:
            args = call["argv"]
            if not args:
                continue
            if args[0] in ("genrsa", "genpkey"):
                key_generators.append(call)
            if args[0] == "req" and any(
                    a == "-newkey" or a.startswith("-newkey=") for a in args):
                key_generators.append(call)
            if (args[0] == "req" and "-x509" in args) or (
                    args[0] == "x509" and ("-req" in args or "-new" in args)):
                cert_generators.append(call)
        assert key_generators, "Script did not invoke OpenSSL to generate the private key"
        assert cert_generators, "Script did not invoke OpenSSL to generate the certificate"
        for call in set(map(id, key_generators + cert_generators)):
            pass
        unique_generation_calls = []
        seen = set()
        for call in key_generators + cert_generators:
            marker = id(call)
            if marker not in seen:
                seen.add(marker)
                unique_generation_calls.append(call)
        assert all(generation_is_silent(call) for call in unique_generation_calls), \
            "OpenSSL certificate/key generation was not silent"

        nginx_calls = read_json_lines(NGINX_LOG)
        invoked_test = False
        for call in nginx_calls:
            args = call["argv"]
            if "-t" in args and option_value(args, "-c") == PROXY_CONF:
                invoked_test = True
        assert invoked_test, "The script itself did not run nginx -t -c /home/user/proxy.conf"

        fingerprint_output = command([
            OPENSSL, "x509", "-noout", "-fingerprint", "-sha256", "-in", CERT_PATH
        ]).stdout.strip()
        assert "=" in fingerprint_output
        fingerprint = fingerprint_output.split("=", 1)[1]
        with open(DEPLOY_LOG) as f:
            lines = f.read().splitlines()
        assert lines == [sentinel, f"Tier: {tier}, Cert SHA256: {fingerprint}"], lines
        assert re.match(r"^([0-9A-F]{2}:){31}[0-9A-F]{2}$", fingerprint)

        with open(CERT_PATH, "rb") as f:
            generated_cert_hashes.append(hashlib.sha256(f.read()).hexdigest())

    assert generated_cert_hashes[0] != generated_cert_hashes[1], \
        "Certificate was reused instead of freshly generated for each execution"
TEST_EOF

export OPENSSL_REAL NGINX_REAL
if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
