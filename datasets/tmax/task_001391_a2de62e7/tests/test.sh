#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import grp
import os
import pwd
import random
import re
import secrets
import shutil
import ssl
import stat
import subprocess
import time
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from threading import Thread

import pytest


def run(cmd, **kwargs):
    return subprocess.run(cmd, capture_output=True, text=True, **kwargs)


def assert_go_binary(path):
    result = run(["go", "version", "-m", path])
    assert result.returncode == 0, f"{path} is not a Go executable: {result.stderr}"


def test_prober_cli_works():
    prober_path = "/home/user/prober-cli"
    assert os.path.isfile(prober_path), f"{prober_path} does not exist"
    assert os.access(prober_path, os.X_OK), f"{prober_path} is not executable"
    assert_go_binary(prober_path)

    try:
        result = run([prober_path, "https://google.com"], timeout=10)
    except subprocess.TimeoutExpired:
        pytest.fail("Prober timed out, likely the timeout bug is not fixed.")

    assert result.returncode == 0, f"Prober failed with return code {result.returncode}, output: {result.stderr}"
    assert "STATUS: 200" in result.stdout, f"Expected STATUS: 200 OK in output, got: {result.stdout}"


def test_makefile_source_and_real_prober_behavior():
    source_dir = "/app/vendored/prober-cli"
    makefile = os.path.join(source_dir, "Makefile")
    main_go = os.path.join(source_dir, "main.go")
    assert os.path.isfile(makefile), "Vendored Makefile is missing"
    assert os.path.isfile(main_go), "Vendored Go source is missing"

    dry = run(["make", "-n", "build"], cwd=source_dir)
    assert dry.returncode == 0, f"Makefile build target is invalid: {dry.stderr}"
    assert "go build" in dry.stdout, "Makefile build target does not build the Go source"
    assert "cli.go" not in dry.stdout, "Makefile still references the nonexistent cli.go"

    with open(main_go, "r") as f:
        source = f.read()
    assert "Nanosecond" not in source, "The hardcoded nanosecond timeout bug remains in the Go source"

    built = run(["make", "-B", "build"], cwd=source_dir, timeout=30)
    assert built.returncode == 0, f"Vendored prober does not build: {built.stdout}\n{built.stderr}"
    vendored_binary = os.path.join(source_dir, "prober")
    assert os.path.isfile(vendored_binary) and os.access(vendored_binary, os.X_OK)
    assert_go_binary(vendored_binary)

    status_code = random.choice([201, 202, 204, 206, 207])

    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            if self.path == "/slow":
                time.sleep(6.5)
                try:
                    self.send_response(200)
                    self.end_headers()
                except (BrokenPipeError, ConnectionResetError):
                    pass
            else:
                self.send_response(status_code)
                self.end_headers()
        def log_message(self, *args):
            pass

    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    thread = Thread(target=server.serve_forever, daemon=True)
    thread.start()
    port = server.server_address[1]
    try:
        for binary in (vendored_binary, "/home/user/prober-cli"):
            result = run([binary, f"http://127.0.0.1:{port}/status/{secrets.token_hex(8)}"], timeout=3)
            assert result.returncode == 0, f"{binary} did not perform the controlled HTTP request: {result.stderr}"
            assert f"STATUS: {status_code}" in result.stdout, f"{binary} did not report the server's derived status: {result.stdout}"

        start = time.monotonic()
        result = run([vendored_binary, f"http://127.0.0.1:{port}/slow"], timeout=8)
        elapsed = time.monotonic() - start
        assert result.returncode != 0, "Vendored prober did not fail when its request exceeded the default timeout"
        assert 4.2 <= elapsed <= 7.5, f"Default timeout is not approximately five seconds (elapsed {elapsed:.2f}s)"
    finally:
        server.shutdown()
        server.server_close()


def test_sanitizer_adversarial_corpus():
    sanitizer_path = "/home/user/sanitizer"
    source_path = "/home/user/sanitizer.go"
    assert os.path.isfile(source_path), f"{source_path} does not exist"
    assert os.path.isfile(sanitizer_path), f"{sanitizer_path} does not exist"
    assert os.access(sanitizer_path, os.X_OK), f"{sanitizer_path} is not executable"
    assert_go_binary(sanitizer_path)

    evil_path = "/app/url_corpus/evil/ssrf_urls.txt"
    with open(evil_path, "r") as f:
        evil_urls = [line.strip() for line in f if line.strip()]

    bypassed_evil = []
    for url in evil_urls:
        result = run([sanitizer_path], input=url + "\n")
        if result.stdout.strip():
            bypassed_evil.append(url)

    clean_path = "/app/url_corpus/clean/valid_urls.txt"
    with open(clean_path, "r") as f:
        clean_urls = [line.strip() for line in f if line.strip()]

    modified_clean = []
    for url in clean_urls:
        result = run([sanitizer_path], input=url + "\n")
        if result.stdout.strip() != url:
            modified_clean.append(url)

    errors = []
    if bypassed_evil:
        errors.append(f"{len(bypassed_evil)} of {len(evil_urls)} evil bypassed: {', '.join(bypassed_evil)}")
    if modified_clean:
        errors.append(f"{len(modified_clean)} of {len(clean_urls)} clean modified: {', '.join(modified_clean)}")
    assert not errors, " | ".join(errors)

    a, b, c = [random.randint(1, 250) for _ in range(3)]
    token = secrets.token_hex(8)
    dynamic_evil = [
        f"http://127.{a}.{b}.{c}:{random.randint(1000, 65000)}/{token}",
        "https://[::1]/" + token,
        f"http://169.254.{b}.{c}/{token}",
        "https://[fe80::1234]/" + token,
        f"http://10.{a}.{b}.{c}/{token}",
        f"https://172.{random.randint(16,31)}.{b}.{c}/{token}",
        f"http://192.168.{b}.{c}/{token}",
        f"gopher://11.{a}.{b}.{c}/{token}",
        f"ftp://23.{a}.{b}.{c}/{token}",
        f"http://public.example@127.{a}.{b}.{c}/{token}",
    ]
    dynamic_clean = [
        f"http://11.{a}.{b}.{c}:{random.randint(1000,65000)}/{token}?x=1#frag",
        f"https://23.{c}.{a}.{b}/{token}",
        f"https://[2606:4700:4700::1111]/{token}",
        f"HTTP://example.com/{token}?Case=Preserved",
        f"https://user:pass@example.net:{random.randint(1000,65000)}/{token}",
    ]
    mixed = dynamic_clean[:2] + dynamic_evil[:4] + dynamic_clean[2:] + dynamic_evil[4:]
    result = run([sanitizer_path], input="\n".join(mixed) + "\n", timeout=5)
    assert result.returncode == 0, f"Sanitizer failed: {result.stderr}"
    assert result.stdout.splitlines() == dynamic_clean, (
        "Sanitizer failed randomized URL/IP validation or did not preserve safe URLs exactly. "
        f"Expected {dynamic_clean}, got {result.stdout.splitlines()}"
    )


def test_expect_script_really_generates_certificates():
    exp_path = "/home/user/auto_cert.exp"
    assert os.path.isfile(exp_path), "auto_cert.exp is missing"
    with open(exp_path, "r") as f:
        text = f.read()
    assert "/app/scripts/gen_cert.sh" in text, "auto_cert.exp does not execute gen_cert.sh"
    assert re.search(r"expect", text, re.I), "auto_cert.exp does not wait for the interactive prompt"
    assert re.search(r"send", text, re.I) and "sre-secure" in text, "auto_cert.exp does not send the required passphrase"

    cert = "/home/user/server.crt"
    key = "/home/user/server.key"
    backups = []
    for path in (cert, key):
        backup = path + ".verifier-backup"
        if os.path.exists(backup):
            os.unlink(backup)
        if os.path.exists(path):
            os.rename(path, backup)
            backups.append((path, backup))

    success = False
    try:
        result = run(["runuser", "-u", "user", "--", "expect", exp_path], timeout=20)
        assert result.returncode == 0, f"auto_cert.exp failed: {result.stdout}\n{result.stderr}"
        assert os.path.isfile(cert) and os.path.isfile(key), "auto_cert.exp did not generate server.crt and server.key"
        cert_pub = run(["openssl", "x509", "-in", cert, "-pubkey", "-noout"])
        key_pub = run(["openssl", "pkey", "-in", key, "-pubout"])
        assert cert_pub.returncode == 0, f"Generated certificate is invalid: {cert_pub.stderr}"
        assert key_pub.returncode == 0, f"Generated private key is invalid: {key_pub.stderr}"
        assert cert_pub.stdout.strip() == key_pub.stdout.strip(), "Generated certificate and private key do not match"
        success = True
    finally:
        if not success:
            for path in (cert, key):
                if os.path.exists(path):
                    os.unlink(path)
            for path, backup in backups:
                os.rename(backup, path)
        else:
            for _, backup in backups:
                if os.path.exists(backup):
                    os.unlink(backup)


def test_tls_certificates_and_server():
    assert os.path.isfile("/home/user/server.crt"), "server.crt is missing"
    assert os.path.isfile("/home/user/server.key"), "server.key is missing"

    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    try:
        req = urllib.request.Request("https://127.0.0.1:8443/health")
        with urllib.request.urlopen(req, context=ctx, timeout=5) as response:
            assert response.status == 200, f"Expected status 200, got {response.status}"
    except Exception as e:
        pytest.fail(f"Failed to connect to HTTPS server on 127.0.0.1:8443/health: {e}")


def test_monitor_pipeline_executes_and_appends_results():
    monitor = "/home/user/monitor.sh"
    sanitizer = "/home/user/sanitizer"
    prober = "/home/user/prober-cli"
    urls_path = "/home/user/test_urls.txt"
    log_path = "/var/log/prober.log"
    assert os.path.isfile(monitor), "monitor.sh is missing"

    with open(monitor, "r") as f:
        script = f.read()
    assert sanitizer in script, "monitor.sh does not invoke /home/user/sanitizer"
    assert prober in script, "monitor.sh does not invoke /home/user/prober-cli"
    assert log_path in script and ">>" in script, "monitor.sh does not append results to /var/log/prober.log"

    token = secrets.token_hex(10)
    safe = [f"http://11.{random.randint(1,250)}.{random.randint(1,250)}.{random.randint(1,250)}/{token}",
            f"https://example.com/{token}"]
    blocked = [f"http://10.{random.randint(1,250)}.1.2/{token}", f"https://127.0.0.1/{token}"]
    corpus = [safe[0], blocked[0], safe[1], blocked[1]]

    prober_backup = prober + ".verifier-real"
    urls_backup = urls_path + ".verifier-backup"
    call_log = "/tmp/prober-calls-" + token
    if os.path.exists(call_log):
        os.unlink(call_log)
    open(call_log, "w").close()
    os.chown(call_log, pwd.getpwnam("user").pw_uid, pwd.getpwnam("user").pw_gid)

    had_urls = os.path.exists(urls_path)
    if had_urls:
        os.rename(urls_path, urls_backup)
    os.rename(prober, prober_backup)
    before_size = os.path.getsize(log_path)
    try:
        with open(urls_path, "w") as f:
            f.write("\n".join(corpus) + "\n")
        os.chown(urls_path, pwd.getpwnam("user").pw_uid, pwd.getpwnam("user").pw_gid)
        with open(prober, "w") as f:
            f.write("#!/bin/bash\n")
            f.write("last=\"${!#}\"\n")
            f.write(f"printf '%s\\n' \"$last\" >> {call_log}\n")
            f.write(f"printf 'VERIFIER-{token} STATUS: 200 URL=%s\\n' \"$last\"\n")
        os.chmod(prober, 0o755)

        result = run(["runuser", "-u", "user", "--", "bash", monitor], timeout=15)
        assert result.returncode == 0, f"monitor.sh failed: {result.stdout}\n{result.stderr}"
        with open(call_log, "r") as f:
            calls = f.read().splitlines()
        assert calls == safe, f"monitor.sh did not probe every and only sanitized URL: expected {safe}, got {calls}"
        assert os.path.getsize(log_path) > before_size, "monitor.sh did not append to prober.log"
        with open(log_path, "r", errors="replace") as f:
            contents = f.read()
        for url in safe:
            assert f"VERIFIER-{token} STATUS: 200 URL={url}" in contents, f"Result for {url} was not appended to prober.log"
        for url in blocked:
            assert url not in contents[before_size:], f"Blocked URL {url} reached the prober/log"
    finally:
        if os.path.exists(prober):
            os.unlink(prober)
        os.rename(prober_backup, prober)
        if os.path.exists(urls_path):
            os.unlink(urls_path)
        if had_urls and os.path.exists(urls_backup):
            os.rename(urls_backup, urls_path)
        if os.path.exists(call_log):
            os.unlink(call_log)


def test_log_file_permissions_group_and_owner():
    log_path = "/var/log/prober.log"
    assert os.path.isfile(log_path), f"{log_path} does not exist"
    st = os.stat(log_path)
    perms = stat.S_IMODE(st.st_mode)
    assert perms == 0o640, f"Expected permissions 640 (0o640), got {oct(perms)}"
    try:
        group_name = grp.getgrgid(st.st_gid).gr_name
    except KeyError:
        group_name = str(st.st_gid)
    assert group_name == "sre-logs", f"Expected group sre-logs, got {group_name}"
    try:
        owner_name = pwd.getpwuid(st.st_uid).pw_name
    except KeyError:
        owner_name = str(st.st_uid)
    assert owner_name == "user", f"Expected owner user, got {owner_name}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
