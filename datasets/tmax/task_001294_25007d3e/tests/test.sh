#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import hashlib
import json
import os
import random
import re
import socketserver
import string
import subprocess
import tempfile
import threading
import http.server
import pytest

VENDOR = "/app/vendor/libsectoken-1.2.0"


def test_makefile_builds_fixed_library():
    """The repaired Makefile must actually build the vendored shared library."""
    makefile = os.path.join(VENDOR, "Makefile")
    assert os.path.isfile(makefile), "Vendored Makefile is missing."
    result = subprocess.run(
        ["make", "-B"], cwd=VENDOR, capture_output=True, text=True, timeout=30
    )
    assert result.returncode == 0, f"Vendored library build failed:\n{result.stdout}\n{result.stderr}"
    so_path = os.path.join(VENDOR, "libsectoken.so")
    assert os.path.isfile(so_path), "Makefile did not produce libsectoken.so."


def test_libsectoken_installed():
    """Verify that the fixed libsectoken package is installed and uses the built library."""
    try:
        import libsectoken
    except ImportError:
        pytest.fail("libsectoken is not installed or importable. The build/install process failed.")

    module_path = os.path.realpath(getattr(libsectoken, "__file__", ""))
    assert module_path and not module_path.startswith(VENDOR + os.sep), (
        "libsectoken is only importable from the vendor source tree; it was not installed."
    )
    assert callable(getattr(libsectoken, "generate_and_validate", None)), (
        "Installed libsectoken lacks generate_and_validate."
    )
    assert bool(libsectoken.generate_and_validate("same-token", "same-token")) is True
    assert bool(libsectoken.generate_and_validate("same-token", "different-token")) is False

    vendor_so = os.path.join(VENDOR, "libsectoken.so")
    vendor_hash = hashlib.sha256(open(vendor_so, "rb").read()).digest()
    mapped = set()
    with open("/proc/self/maps", "r") as maps:
        for line in maps:
            path = line.split()[-1] if line.split() else ""
            if path.endswith("/libsectoken.so") and os.path.isfile(path):
                mapped.add(path)
    assert mapped, "Calling the installed package did not load libsectoken.so."
    assert any(hashlib.sha256(open(path, "rb").read()).digest() == vendor_hash for path in mapped), (
        "The installed package did not load the repaired vendored shared library."
    )


def _strip_c_comments_and_strings(source):
    source = re.sub(r"/\*.*?\*/", " ", source, flags=re.S)
    source = re.sub(r"//[^\n]*", " ", source)
    source = re.sub(r'"(?:\\.|[^"\\])*"', '""', source)
    source = re.sub(r"'(?:\\.|[^'\\])*'", "''", source)
    return source


def test_c_code_timing_leak_fixed():
    """Verify that validation is implemented without variable-time comparison calls."""
    c_file = os.path.join(VENDOR, "src/validate.c")
    if not os.path.isfile(c_file):
        pytest.fail(f"C source file {c_file} is missing.")

    with open(c_file, "r") as f:
        content = f.read()

    # Preserve the original heuristic assertion.
    if "strcmp(" in content and "CRYPTO_memcmp" not in content and "^" not in content:
        pass

    code = _strip_c_comments_and_strings(content)
    assert not re.search(r"\b(?:strcmp|strncmp|memcmp)\s*\(", code), (
        "validate_token still calls a variable-time comparison routine."
    )
    assert "^" in code and re.search(r"\b(?:for|while)\s*\(", code), (
        "No constant-time XOR accumulation loop was found in validate.c."
    )

    so_path = os.path.join(VENDOR, "libsectoken.so")
    lib = ctypes.CDLL(so_path)
    validate = lib.validate_token
    validate.argtypes = [ctypes.c_char_p, ctypes.c_char_p]
    validate.restype = ctypes.c_int
    for left, right, expected in [
        (b"", b"", 1),
        (b"a", b"a", 1),
        (b"a", b"b", 0),
        (b"short", b"shorter", 0),
        (b"prefix-difference-1", b"prefix-difference-2", 0),
        (b"x" * 512, b"x" * 512, 1),
        (b"x" * 511 + b"a", b"x" * 511 + b"b", 0),
    ]:
        assert bool(validate(left, right)) is bool(expected)


def test_rotate_tokens_fuzz_equivalence():
    """Fuzz the CLI against both the legacy executable and independently derived answers."""
    oracle_path = "/opt/legacy/rotate_tokens_ref"
    agent_script = "/home/user/rotate_tokens.py"

    if not os.path.isfile(agent_script):
        pytest.fail(f"Agent script {agent_script} does not exist.")
    if not os.path.isfile(oracle_path):
        pytest.fail(f"Oracle binary {oracle_path} does not exist.")
    assert open(agent_script, "rb").read() != open(oracle_path, "rb").read(), (
        "rotate_tokens.py is a byte-identical copy of the reference executable."
    )

    random.seed(42)
    alphanumeric = string.ascii_letters + string.digits

    for _ in range(1000):
        seed_len = random.randint(8, 32)
        seed = ''.join(random.choice(alphanumeric) for _ in range(seed_len))
        user_id = str(random.randint(1, 100000))
        expected = hashlib.sha256(seed.encode()).hexdigest() + user_id

        try:
            oracle_res = subprocess.run(
                [oracle_path, seed, user_id], capture_output=True, text=True,
                check=True, timeout=2
            )
            oracle_out = oracle_res.stdout.strip()
        except subprocess.CalledProcessError as e:
            pytest.fail(f"Oracle failed on input seed='{seed}', user_id='{user_id}': {e.stderr}")

        try:
            agent_res = subprocess.run(
                ["python3", agent_script, seed, user_id], capture_output=True,
                text=True, check=True, timeout=2
            )
            agent_out = agent_res.stdout.strip()
        except subprocess.CalledProcessError as e:
            pytest.fail(f"Agent script failed on input seed='{seed}', user_id='{user_id}': {e.stderr}")

        assert oracle_out == expected
        assert agent_out == oracle_out, (
            f"Output mismatch for seed='{seed}', user_id='{user_id}'.\n"
            f"Expected (Oracle): {oracle_out}\nGot (Agent): {agent_out}"
        )
        assert re.fullmatch(r"[0-9a-f]{64}[0-9]+", agent_out)


def test_rotate_tokens_uses_libsectoken():
    """Run the CLI with an instrumented libsectoken module and require an API call."""
    agent_script = "/home/user/rotate_tokens.py"
    with tempfile.TemporaryDirectory() as fake_dir:
        marker = os.path.join(fake_dir, "called.json")
        fake_module = os.path.join(fake_dir, "libsectoken.py")
        with open(fake_module, "w") as f:
            f.write(
                "import json, os\n"
                "def generate_and_validate(a, b):\n"
                "    with open(os.environ['LIBSECTOKEN_CALL_MARKER'], 'w') as out:\n"
                "        json.dump([a, b], out)\n"
                "    return a == b\n"
            )
        env = os.environ.copy()
        env["PYTHONPATH"] = fake_dir + os.pathsep + env.get("PYTHONPATH", "")
        env["LIBSECTOKEN_CALL_MARKER"] = marker
        seed, user_id = "LibraryUsageProbe", "7319"
        result = subprocess.run(
            ["python3", agent_script, seed, user_id], capture_output=True,
            text=True, env=env, timeout=5
        )
        assert result.returncode == 0, result.stderr
        assert result.stdout.strip() == hashlib.sha256(seed.encode()).hexdigest() + user_id
        assert os.path.isfile(marker), "rotate_tokens.py never called libsectoken."
        args = json.load(open(marker))
        assert isinstance(args, list) and len(args) == 2


def test_audit_services_script_exists():
    """Verify that the bash script for auditing services exists."""
    script_path = "/home/user/audit_services.sh"
    assert os.path.isfile(script_path), f"Audit script {script_path} is missing."
    assert os.access(script_path, os.X_OK), f"Audit script {script_path} is not executable."


class _AuditHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        body = self.server.audit_body.encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/plain")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass


class _Server(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True
    allow_reuse_address = True


def _start_audit_server(body, used):
    rng = random.SystemRandom()
    for _ in range(500):
        port = rng.randint(1000, 5000)
        if port in used:
            continue
        try:
            server = _Server(("127.0.0.1", port), _AuditHandler)
        except OSError:
            continue
        server.audit_body = body
        used.add(port)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        return server, port
    pytest.fail("Could not allocate a test port in the required audit range.")


def test_audit_services_discovers_vulnerable_ports():
    """Execute the audit against unpredictable vulnerable and benign services."""
    script_path = "/home/user/audit_services.sh"
    log_path = "/home/user/vulnerable_ports.log"
    used = set()
    servers = []
    vulnerable = set()
    benign = set()
    try:
        for body, is_vulnerable in [
            ("service=accounts\nendpoint=/api/v1/auth\n", True),
            ("ok: routes include [/health, /api/v1/auth, /metrics]\n", True),
            ("service=accounts\nendpoint=/api/v2/auth\n", False),
            ("healthy service with no legacy authentication route\n", False),
        ]:
            server, port = _start_audit_server(body, used)
            servers.append(server)
            (vulnerable if is_vulnerable else benign).add(port)

        if os.path.exists(log_path):
            os.remove(log_path)
        result = subprocess.run(
            [script_path], cwd="/home/user", capture_output=True, text=True, timeout=60
        )
        assert result.returncode == 0, f"Audit script failed:\n{result.stdout}\n{result.stderr}"
        assert os.path.isfile(log_path), "Audit script did not create vulnerable_ports.log."

        lines = [line.strip() for line in open(log_path) if line.strip()]
        assert all(re.fullmatch(r"[0-9]+", line) for line in lines), (
            "The audit log must contain one numeric port per line."
        )
        found = {int(line) for line in lines}
        assert vulnerable <= found, f"Audit missed vulnerable ports: {sorted(vulnerable - found)}"
        assert not (benign & found), f"Audit falsely reported benign ports: {sorted(benign & found)}"
    finally:
        for server in servers:
            server.shutdown()
            server.server_close()


def test_vulnerable_ports_log_exists():
    """Verify that the vulnerable_ports.log exists."""
    log_path = "/home/user/vulnerable_ports.log"
    assert os.path.isfile(log_path), f"Log file {log_path} is missing. Did the agent run the audit script?"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
