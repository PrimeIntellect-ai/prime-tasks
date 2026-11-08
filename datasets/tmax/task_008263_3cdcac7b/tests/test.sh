#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import json
import os
import shutil
import stat
import subprocess
import sys
import textwrap
import time
import uuid

import pytest


def test_fetch_secrets_exists():
    """Verify that the fetch_secrets.py script exists."""
    path = "/home/user/fetch_secrets.py"
    assert os.path.isfile(path), f"Expected script {path} does not exist."


def test_prod_secrets_json():
    """Verify the existence, permissions, and content of prod_secrets.json."""
    path = "/home/user/prod_secrets.json"
    assert os.path.isfile(path), f"Expected file {path} does not exist."

    st = os.stat(path)
    mode = stat.S_IMODE(st.st_mode)
    assert mode == 0o400, f"Permissions for {path} are {oct(mode)}, expected 0o400."

    with open(path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{path} does not contain valid JSON.")

    assert data.get("DB_PASS") == "VaultPass2024!", f"DB_PASS in {path} is incorrect."
    assert data.get("API_KEY") == "SecKey9988", f"API_KEY in {path} is incorrect."


def test_run_app_sh_exists():
    """Verify that the run_app.sh script exists."""
    path = "/home/user/run_app.sh"
    assert os.path.isfile(path), f"Expected script {path} does not exist."


def test_rotation_success_log():
    """Verify the existence and content of rotation_success.log."""
    path = "/home/user/rotation_success.log"
    assert os.path.isfile(path), f"Expected file {path} does not exist."

    with open(path, 'r') as f:
        content = f.read().strip()

    assert content == "ROTATION_COMPLETE_882910", f"Content of {path} is incorrect. Got: {content}"


def run_checked(cmd, cwd=None):
    return subprocess.run(
        cmd, cwd=cwd, check=True, stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL, timeout=20
    )


def make_ca_and_server_cert(directory, prefix):
    ca_key = directory / f"{prefix}_ca.key"
    ca_crt = directory / f"{prefix}_ca.crt"
    server_key = directory / f"{prefix}_server.key"
    server_csr = directory / f"{prefix}_server.csr"
    server_crt = directory / f"{prefix}_server.crt"
    ext = directory / f"{prefix}.ext"
    ext.write_text("subjectAltName=DNS:localhost,IP:127.0.0.1\n")

    run_checked([
        "openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes",
        "-keyout", str(ca_key), "-out", str(ca_crt), "-days", "2",
        "-subj", f"/CN={prefix}-test-ca"
    ])
    run_checked([
        "openssl", "req", "-newkey", "rsa:2048", "-nodes",
        "-keyout", str(server_key), "-out", str(server_csr),
        "-subj", "/CN=localhost"
    ])
    run_checked([
        "openssl", "x509", "-req", "-in", str(server_csr),
        "-CA", str(ca_crt), "-CAkey", str(ca_key), "-CAcreateserial",
        "-out", str(server_crt), "-days", "2", "-extfile", str(ext)
    ])
    return ca_crt, server_crt, server_key


def start_https_server(directory, cert, key, response_bytes):
    server_program = directory / "https_test_server.py"
    server_program.write_text(textwrap.dedent("""
        import base64
        import http.server
        import ssl
        import sys

        payload = base64.b64decode(sys.argv[3])

        class Handler(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                if self.path != '/secrets':
                    self.send_response(404)
                    self.end_headers()
                    return
                self.send_response(200)
                self.send_header('Content-Type', 'application/json')
                self.send_header('Content-Length', str(len(payload)))
                self.end_headers()
                self.wfile.write(payload)

            def log_message(self, *args):
                pass

        server = http.server.HTTPServer(('localhost', 8443), Handler)
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.load_cert_chain(sys.argv[1], sys.argv[2])
        server.socket = context.wrap_socket(server.socket, server_side=True)
        server.serve_forever()
    """))
    encoded = base64.b64encode(response_bytes).decode("ascii")
    proc = subprocess.Popen(
        [sys.executable, str(server_program), str(cert), str(key), encoded],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
    )
    for _ in range(30):
        if proc.poll() is not None:
            raise AssertionError("Test HTTPS server failed to start on port 8443")
        time.sleep(0.1)
        if proc.poll() is None and _ >= 2:
            return proc
    raise AssertionError("Test HTTPS server did not become ready")


def stop_server(proc):
    if proc is None:
        return
    proc.terminate()
    try:
        proc.wait(timeout=3)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait(timeout=3)


def test_zz_scripts_are_functional_and_secure(tmp_path):
    fetch_path = "/home/user/fetch_secrets.py"
    wrapper_path = "/home/user/run_app.sh"
    secrets_path = "/home/user/prod_secrets.json"
    log_path = "/home/user/rotation_success.log"
    ca_path = "/home/user/ca.crt"
    app_path = "/home/user/app.py"

    assert os.path.isfile(fetch_path)
    assert os.path.isfile(wrapper_path)

    # Remove any vault process left by the agent so the verifier controls the endpoint.
    if shutil.which("fuser"):
        subprocess.run(["fuser", "-k", "8443/tcp"], stdout=subprocess.DEVNULL,
                       stderr=subprocess.DEVNULL, check=False)
    else:
        subprocess.run(["pkill", "-f", "/home/user/vault_server.py"],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
    time.sleep(0.2)

    good_ca, good_cert, good_key = make_ca_and_server_cert(tmp_path, "trusted")
    _, bad_cert, bad_key = make_ca_and_server_cert(tmp_path, "untrusted")

    original_ca = open(ca_path, "rb").read()
    original_ca_mode = stat.S_IMODE(os.stat(ca_path).st_mode)
    original_app = open(app_path, "rb").read()
    original_app_mode = stat.S_IMODE(os.stat(app_path).st_mode)
    server = None

    nonce = uuid.uuid4().hex
    db_pass = f"Dyn Pass '{nonce} $;!"
    api_key = f'Dyn"Key\\{nonce} space'
    response = (json.dumps(
        {"DB_PASS": db_pass, "API_KEY": api_key},
        separators=(", ", ": ")
    ) + "\n").encode("utf-8")

    try:
        shutil.copyfile(good_ca, ca_path)

        # An untrusted certificate must not be accepted or written to disk.
        sentinel = b"DO_NOT_OVERWRITE_WITH_UNTRUSTED_DATA"
        with open(secrets_path, "wb") as f:
            f.write(sentinel)
        os.chmod(secrets_path, 0o400)
        server = start_https_server(tmp_path, bad_cert, bad_key, b'{"DB_PASS":"evil","API_KEY":"evil"}')
        try:
            subprocess.run(
                [sys.executable, fetch_path], cwd="/home/user",
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=15,
                check=False
            )
        finally:
            stop_server(server)
            server = None
        assert open(secrets_path, "rb").read() == sentinel, \
            "fetch_secrets.py accepted an HTTPS certificate not signed by /home/user/ca.crt"

        # A certificate signed by the supplied CA must work, and the raw body must
        # be saved exactly with owner-read-only permissions.
        server = start_https_server(tmp_path, good_cert, good_key, response)
        try:
            result = subprocess.run(
                [sys.executable, fetch_path], cwd="/home/user",
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=15,
                check=False
            )
        finally:
            stop_server(server)
            server = None
        assert result.returncode == 0, \
            f"fetch_secrets.py failed against a server signed by ca.crt: {result.stderr.decode(errors='replace')}"
        assert os.path.isfile(secrets_path)
        assert open(secrets_path, "rb").read() == response, \
            "prod_secrets.json was not saved exactly as received"
        assert stat.S_IMODE(os.stat(secrets_path).st_mode) == 0o400

        # Replace app.py temporarily with a randomized probe. It records the actual
        # environment it receives and emits a token unknown when the agent ran.
        probe_output = tmp_path / "observed_environment.json"
        dynamic_token = "ROTATION_DYNAMIC_" + uuid.uuid4().hex
        probe = textwrap.dedent(f"""\
            #!/usr/bin/python3
            import json
            import os
            with open({str(probe_output)!r}, 'w') as f:
                json.dump(dict(os.environ), f)
            print({dynamic_token!r})
        """)
        with open(app_path, "w") as f:
            f.write(probe)
        os.chmod(app_path, 0o755)
        if os.path.exists(log_path):
            os.unlink(log_path)

        contaminated_env = os.environ.copy()
        contaminated_env.update({
            "HOME": "/must/not/leak",
            "USER": "must-not-leak",
            "PATH": contaminated_env.get("PATH", "/usr/bin:/bin"),
            "SSH_AUTH_SOCK": "/must/not/leak.sock",
            "SECRET_LEAK_MARKER": nonce,
        })
        result = subprocess.run(
            ["/bin/bash", wrapper_path], cwd="/home/user", env=contaminated_env,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=15,
            check=False
        )
        assert result.returncode == 0, \
            f"run_app.sh failed: {result.stderr.decode(errors='replace')}"
        assert probe_output.is_file(), "run_app.sh did not execute /home/user/app.py"

        observed = json.loads(probe_output.read_text())
        assert observed.get("DB_PASS") == db_pass
        assert observed.get("API_KEY") == api_key
        extras = set(observed) - {"DB_PASS", "API_KEY", "LC_CTYPE"}
        assert not extras, f"run_app.sh leaked extra environment variables: {sorted(extras)}"
        assert os.path.isfile(log_path), "run_app.sh did not create rotation_success.log"
        assert open(log_path, "r").read().strip() == dynamic_token, \
            "rotation_success.log did not contain only the token printed by app.py"
    finally:
        stop_server(server)
        with open(ca_path, "wb") as f:
            f.write(original_ca)
        os.chmod(ca_path, original_ca_mode)
        with open(app_path, "wb") as f:
            f.write(original_app)
        os.chmod(app_path, original_app_mode)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
