#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import os
import socket
import ssl
import stat
import subprocess
import time
import uuid

import pytest

BASE = "/home/user/investigation"


def test_stolen_creds_extracted():
    creds_file = "/home/user/investigation/stolen_creds.txt"
    assert os.path.isfile(creds_file), f"File {creds_file} does not exist. Did you extract the credentials?"

    with open(creds_file, 'r') as f:
        content = f.read().strip()

    assert content == "admin:SuperSecret123!", f"Extracted credentials do not match the expected value. Found: {content}"


def test_worker_remediated():
    worker_file = "/home/user/investigation/worker.py"
    assert os.path.isfile(worker_file), f"File {worker_file} is missing."

    with open(worker_file, 'r') as f:
        content = f.read()

    # Check that environment variables are being read
    assert "DB_USER" in content, "worker.py does not appear to read DB_USER from the environment."
    assert "DB_PASS" in content, "worker.py does not appear to read DB_PASS from the environment."

    # Check that command line arguments are removed
    assert "--user" not in content, "worker.py still contains '--user' argument parsing."
    assert "--pass" not in content, "worker.py still contains '--pass' argument parsing."


def test_processor_remediated():
    processor_file = "/home/user/investigation/processor.py"
    assert os.path.isfile(processor_file), f"File {processor_file} is missing."

    with open(processor_file, 'r') as f:
        content = f.read()

    # Check that the credentials are no longer passed as command line arguments
    assert "--user" not in content, "processor.py still passes '--user' as a command line argument."
    assert "--pass" not in content, "processor.py still passes '--pass' as a command line argument."

    # Use AST to verify subprocess.Popen is called with env
    try:
        tree = ast.parse(content)
    except SyntaxError as e:
        pytest.fail(f"processor.py has a syntax error: {e}")

    popen_found = False
    env_passed = False

    for node in ast.walk(tree):
        if isinstance(node, ast.Call):
            if isinstance(node.func, ast.Attribute) and node.func.attr == 'Popen':
                popen_found = True
                for kw in node.keywords:
                    if kw.arg == 'env':
                        env_passed = True
                        break

    assert popen_found, "processor.py no longer calls subprocess.Popen."
    assert env_passed, "processor.py calls subprocess.Popen but does not pass the 'env' keyword argument to inject environment variables."


def test_tls_artifacts_are_valid_rsa_pair():
    cert = os.path.join(BASE, "cert.pem")
    key = os.path.join(BASE, "key.pem")
    for path in (cert, key):
        assert os.path.isfile(path), f"Required TLS artifact is missing: {path}"
        assert stat.S_ISREG(os.stat(path).st_mode), f"TLS artifact is not a regular file: {path}"

    subprocess.run(["openssl", "x509", "-in", cert, "-noout"], check=True,
                   stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=5)
    subprocess.run(["openssl", "rsa", "-in", key, "-check", "-noout"], check=True,
                   stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=5)
    subprocess.run(["openssl", "verify", "-CAfile", cert, cert], check=True,
                   stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=5)

    cert_pub = subprocess.check_output(
        ["bash", "-c", f"openssl x509 -in {cert!s} -pubkey -noout | openssl pkey -pubin -outform DER"],
        timeout=5,
    )
    key_pub = subprocess.check_output(
        ["openssl", "pkey", "-in", key, "-pubout", "-outform", "DER"], timeout=5
    )
    assert cert_pub == key_pub, "cert.pem and key.pem do not form a matching key pair."
    with open(key, "rb") as f:
        assert b"ENCRYPTED" not in f.read(), "key.pem must be unencrypted."


def test_interceptor_really_serves_tls_and_prints_raw_headers():
    interceptor = os.path.join(BASE, "interceptor.py")
    cert = os.path.join(BASE, "cert.pem")
    assert os.path.isfile(interceptor), "interceptor.py is missing."
    subprocess.run(["python3", "-m", "py_compile", interceptor], check=True, timeout=5)

    # Fail rather than accidentally testing an unrelated pre-existing listener.
    probe = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    probe.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        probe.bind(("127.0.0.1", 8443))
    except OSError as exc:
        pytest.fail(f"Port 8443 was already occupied before interceptor.py was started: {exc}")
    finally:
        probe.close()

    token = uuid.uuid4().hex
    request = (
        f"GET /audit-{token} HTTP/1.1\r\n"
        "Host: localhost:8443\r\n"
        f"X-Audit-Token: {token}\r\n"
        "Connection: close\r\n\r\n"
    ).encode()
    proc = subprocess.Popen(
        ["python3", "-u", interceptor], cwd=BASE,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True
    )
    output = ""
    try:
        deadline = time.time() + 5
        connected = False
        while time.time() < deadline:
            if proc.poll() is not None:
                break
            try:
                raw = socket.create_connection(("127.0.0.1", 8443), timeout=0.5)
                connected = True
                break
            except OSError:
                time.sleep(0.1)
        assert connected, "interceptor.py did not listen on localhost:8443."

        context = ssl.create_default_context()
        context.check_hostname = False
        context.verify_mode = ssl.CERT_NONE
        with context.wrap_socket(raw, server_hostname="localhost") as tls:
            peer_der = tls.getpeercert(binary_form=True)
            with open(cert, "r") as f:
                expected_der = ssl.PEM_cert_to_DER_cert(f.read())
            assert peer_der == expected_der, "interceptor.py did not serve the generated cert.pem."
            tls.sendall(request)
            try:
                tls.recv(4096)
            except (OSError, socket.timeout):
                pass
        time.sleep(0.5)
    finally:
        if proc.poll() is None:
            proc.terminate()
        try:
            output, _ = proc.communicate(timeout=3)
        except subprocess.TimeoutExpired:
            proc.kill()
            output, _ = proc.communicate(timeout=2)

    assert f"GET /audit-{token} HTTP/1.1" in output, "Interceptor did not print the raw HTTP request line."
    assert f"X-Audit-Token: {token}".lower() in output.lower(), "Interceptor did not print the raw request headers."


def test_worker_executes_using_environment():
    worker = os.path.join(BASE, "worker.py")
    subprocess.run(["python3", "-m", "py_compile", worker], check=True, timeout=5)
    user = "audit_user_" + uuid.uuid4().hex[:10]
    password = "audit_pass_" + uuid.uuid4().hex
    env = os.environ.copy()
    env["DB_USER"] = user
    env["DB_PASS"] = password
    result = subprocess.run(
        ["python3", worker], cwd=BASE, env=env, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=8
    )
    assert result.returncode == 0, f"worker.py failed when supplied DB_USER/DB_PASS in its environment:\n{result.stdout}"
    assert user in result.stdout, "worker.py did not use DB_USER from its environment."

    tree = ast.parse(open(worker, "r").read())
    constants = {n.value for n in ast.walk(tree) if isinstance(n, ast.Constant) and isinstance(n.value, str)}
    assert "DB_USER" in constants and "DB_PASS" in constants, "worker.py must access both named environment variables."


def test_processor_actually_injects_credentials_without_argv_leak():
    processor = os.path.join(BASE, "processor.py")
    worker = os.path.join(BASE, "worker.py")
    subprocess.run(["python3", "-m", "py_compile", processor], check=True, timeout=5)

    with open(worker, "rb") as f:
        original = f.read()
    original_mode = os.stat(worker).st_mode
    report = f"/tmp/processor_probe_{uuid.uuid4().hex}.json"
    probe_source = f'''import json, os, sys\nwith open({report!r}, "w") as f:\n    json.dump({{"argv": sys.argv, "user": os.environ.get("DB_USER"), "password": os.environ.get("DB_PASS")}}, f)\n'''
    try:
        with open(worker, "w") as f:
            f.write(probe_source)
        os.chmod(worker, 0o755)
        result = subprocess.run(
            ["python3", processor], cwd=BASE, text=True,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=8
        )
        assert result.returncode == 0, f"processor.py did not run successfully:\n{result.stdout}"
        assert os.path.isfile(report), "processor.py did not actually launch worker.py."
        with open(report, "r") as f:
            observed = json.load(f)
    finally:
        with open(worker, "wb") as f:
            f.write(original)
        os.chmod(worker, original_mode)
        try:
            os.remove(report)
        except FileNotFoundError:
            pass

    argv = observed["argv"][1:]
    assert "--user" not in argv and "--pass" not in argv, "processor.py still exposes credential flags in worker argv."
    assert "admin" not in argv and "SuperSecret123!" not in argv, "processor.py exposes credentials in worker argv."
    assert observed["user"] == "admin", "processor.py did not inject DB_USER into the worker environment."
    assert observed["password"] == "SuperSecret123!", "processor.py did not inject DB_PASS into the worker environment."


def test_run_env_no_longer_exposes_credentials_in_proc():
    run_env = os.path.join(BASE, "run_env.sh")
    monitor = os.path.join(BASE, "monitor.py")
    assert os.path.isfile(run_env), "run_env.sh is missing."

    with open(monitor, "rb") as f:
        original = f.read()
    original_mode = os.stat(monitor).st_mode
    captured = f"/tmp/captured_{uuid.uuid4().hex}"
    trusted_monitor = f'''import os, time\nout = {captured!r}\nfor _ in range(40):\n    for pid in [p for p in os.listdir("/proc") if p.isdigit()]:\n        try:\n            parts = open("/proc/" + pid + "/cmdline", "rb").read().split(b"\\0")\n            if any(os.path.basename(x.decode(errors="ignore")) == "worker.py" for x in parts):\n                if b"--user" in parts or b"--pass" in parts or b"admin" in parts or b"SuperSecret123!" in parts:\n                    open(out, "w").write(repr(parts))\n        except Exception:\n            pass\n    time.sleep(0.1)\n'''
    try:
        with open(monitor, "w") as f:
            f.write(trusted_monitor)
        result = subprocess.run(
            ["bash", run_env], cwd=BASE, text=True,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=12
        )
        assert result.returncode == 0, f"run_env.sh failed after remediation:\n{result.stdout}"
        assert not os.path.exists(captured), "Credentials or credential flags were observable in worker.py's /proc command line."
    finally:
        with open(monitor, "wb") as f:
            f.write(original)
        os.chmod(monitor, original_mode)
        try:
            os.remove(captured)
        except FileNotFoundError:
            pass
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
