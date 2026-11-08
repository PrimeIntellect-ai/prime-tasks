#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import shlex
import shutil
import signal
import subprocess
import threading
import time
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


def test_bashrc_exports():
    """Check that .bashrc contains and actually exports the required values."""
    bashrc_path = "/home/user/.bashrc"
    assert os.path.exists(bashrc_path), f"File {bashrc_path} does not exist."

    with open(bashrc_path, "r") as f:
        content = f.read()

    # Preserve the original assertions.
    assert "export APP_LB_PORT=8080" in content, "APP_LB_PORT=8080 is not exported in .bashrc"
    assert "export APP_B1_PORT=9001" in content, "APP_B1_PORT=9001 is not exported in .bashrc"
    assert "export APP_B2_PORT=9002" in content, "APP_B2_PORT=9002 is not exported in .bashrc"

    result = subprocess.run(
        ["bash", "--noprofile", "--norc", "-c",
         "source /home/user/.bashrc; printf '%s\\n%s\\n%s\\n' \"$APP_LB_PORT\" \"$APP_B1_PORT\" \"$APP_B2_PORT\""],
        capture_output=True,
        text=True,
        timeout=5,
    )
    assert result.returncode == 0, f"Could not source .bashrc: {result.stderr}"
    assert result.stdout.splitlines()[-3:] == ["8080", "9001", "9002"], "Required variables are not set correctly when .bashrc is sourced"


def parse_haproxy_config(path):
    sections = []
    current = None
    with open(path, "r") as f:
        for raw in f:
            try:
                tokens = shlex.split(raw, comments=True, posix=True)
            except ValueError as exc:
                raise AssertionError(f"Could not parse HAProxy line {raw!r}: {exc}")
            if not tokens:
                continue
            lower = [token.lower() for token in tokens]
            if lower[0] in {"global", "defaults", "frontend", "backend", "listen"}:
                current = {"kind": lower[0], "name": tokens[1] if len(tokens) > 1 else None, "directives": []}
                sections.append(current)
            else:
                assert current is not None, f"Directive outside a section: {raw.strip()}"
                current["directives"].append(tokens)
    return sections


def has_directive(section, name, *args):
    wanted = [name.lower(), *[arg.lower() for arg in args]]
    return any([token.lower() for token in directive] == wanted for directive in section["directives"])


def test_haproxy_cfg_syntax_and_contents():
    """Validate HAProxy syntax, preserve original checks, and inspect active sections."""
    cfg_path = "/home/user/haproxy.cfg"
    assert os.path.exists(cfg_path), f"HAProxy config {cfg_path} does not exist."

    result = subprocess.run(["haproxy", "-c", "-f", cfg_path], capture_output=True, text=True)
    assert result.returncode == 0, f"HAProxy config syntax error:\n{result.stderr}"

    with open(cfg_path, "r") as f:
        content = f.read()

    # Preserve the original content assertions.
    assert "app_front" in content, "Frontend 'app_front' not found in haproxy.cfg"
    assert "app_back" in content, "Backend 'app_back' not found in haproxy.cfg"
    assert "8080" in content, "Port 8080 not found in haproxy.cfg"
    assert "9001" in content, "Backend port 9001 not found in haproxy.cfg"
    assert "9002" in content, "Backend port 9002 not found in haproxy.cfg"
    assert "roundrobin" in content, "Roundrobin algorithm not specified in haproxy.cfg"
    assert "mode http" in content, "mode http not specified in haproxy.cfg"

    sections = parse_haproxy_config(cfg_path)
    fronts = [s for s in sections if s["kind"] == "frontend" and s["name"] == "app_front"]
    backs = [s for s in sections if s["kind"] == "backend" and s["name"] == "app_back"]
    assert fronts, "An active frontend named app_front is required"
    assert backs, "An active backend named app_back is required"
    front = fronts[0]
    back = backs[0]

    assert has_directive(front, "mode", "http"), "frontend app_front must use mode http"
    assert has_directive(front, "default_backend", "app_back"), "frontend app_front must route to app_back"
    assert any(len(d) >= 2 and d[0].lower() == "bind" and d[1] == "127.0.0.1:8080" for d in front["directives"]), "app_front must bind to 127.0.0.1:8080"

    assert has_directive(back, "mode", "http"), "backend app_back must use mode http"
    assert has_directive(back, "balance", "roundrobin"), "backend app_back must use roundrobin"
    assert any(len(d) >= 3 and d[0].lower() == "server" and d[1] == "backend1" and d[2] == "127.0.0.1:9001" for d in back["directives"]), "app_back must define backend1 at 127.0.0.1:9001"
    assert any(len(d) >= 3 and d[0].lower() == "server" and d[1] == "backend2" and d[2] == "127.0.0.1:9002" for d in back["directives"]), "app_back must define backend2 at 127.0.0.1:9002"

    active_directives = [d for section in sections for d in section["directives"]]
    assert not any(d[0].lower() in {"user", "group"} for d in active_directives), "Privileged user/group directives must not be used"


def test_verify_script_exists_and_executable():
    """Check that verify.sh exists and is executable."""
    script_path = "/home/user/verify.sh"
    assert os.path.exists(script_path), f"Script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."


class ReusableHTTPServer(ThreadingHTTPServer):
    allow_reuse_address = True


def start_backends(bodies, events):
    lock = threading.Lock()
    servers = []
    threads = []

    def handler_for(identity, body):
        class Handler(BaseHTTPRequestHandler):
            protocol_version = "HTTP/1.1"

            def do_GET(self):
                with lock:
                    events.append((identity, self.command, self.path, time.monotonic(), body))
                payload = body.encode()
                self.send_response(200)
                self.send_header("Content-Length", str(len(payload)))
                self.send_header("Connection", "close")
                self.end_headers()
                self.wfile.write(payload)

            def log_message(self, fmt, *args):
                pass
        return Handler

    for port, identity, body in [(9001, "B1", bodies[0]), (9002, "B2", bodies[1])]:
        server = ReusableHTTPServer(("127.0.0.1", port), handler_for(identity, body))
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        servers.append(server)
        threads.append(thread)
    return servers


def stop_backends(servers):
    for server in servers:
        server.shutdown()
        server.server_close()


def start_haproxy():
    process = subprocess.Popen(
        ["haproxy", "-db", "-f", "/home/user/haproxy.cfg"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
        text=True,
        start_new_session=True,
    )
    time.sleep(0.5)
    assert process.poll() is None, f"HAProxy failed to start: {process.stderr.read()}"
    return process


def stop_haproxy(process):
    if process.poll() is None:
        os.killpg(process.pid, signal.SIGTERM)
        try:
            process.wait(timeout=3)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            process.wait(timeout=3)


def run_verify():
    log_file = "/home/user/health_check.log"
    if os.path.exists(log_file):
        os.remove(log_file)
    result = subprocess.run(["/home/user/verify.sh"], capture_output=True, text=True, timeout=15)
    assert result.returncode == 0, f"verify.sh failed: {result.stderr}"
    assert os.path.exists(log_file), f"Log file {log_file} was not created by verify.sh."
    return log_file


def test_deployment_functionality():
    """Preserve the original end-to-end round-robin assertions."""
    events = []
    servers = start_backends(("B1", "B2"), events)
    proxy = None
    try:
        proxy = start_haproxy()
        log_file = run_verify()
        with open(log_file, "r") as f:
            lines = [line.strip() for line in f.readlines() if line.strip()]

        b1_count = lines.count("B1")
        b2_count = lines.count("B2")
        assert len(lines) == 4, f"Expected exactly 4 lines in {log_file}, found {len(lines)}."
        assert b1_count == 2, f"Expected 2 requests routed to B1, found {b1_count}."
        assert b2_count == 2, f"Expected 2 requests routed to B2, found {b2_count}."
    finally:
        if proxy is not None:
            stop_haproxy(proxy)
        stop_backends(servers)


def install_curl_tracer(trace_path):
    curl_path = os.path.realpath(shutil.which("curl"))
    real_path = curl_path + ".verifier-real"
    assert not os.path.exists(real_path), f"Unexpected existing verifier backup: {real_path}"
    os.rename(curl_path, real_path)
    wrapper = "#!/bin/bash\nprintf '%s\\0' \"$#\" \"$@\" >> " + shlex.quote(trace_path) + "\nexec " + shlex.quote(real_path) + " \"$@\"\n"
    with open(curl_path, "w") as f:
        f.write(wrapper)
    os.chmod(curl_path, 0o755)
    return curl_path, real_path


def restore_curl(curl_path, real_path):
    if os.path.exists(real_path):
        if os.path.exists(curl_path):
            os.remove(curl_path)
        os.rename(real_path, curl_path)


def read_curl_trace(trace_path):
    data = open(trace_path, "rb").read().split(b"\0")
    if data and data[-1] == b"":
        data.pop()
    invocations = []
    index = 0
    while index < len(data):
        count = int(data[index].decode())
        index += 1
        assert index + count <= len(data), "Malformed curl invocation trace"
        invocations.append([part.decode() for part in data[index:index + count]])
        index += count
    return invocations


def test_verify_script_really_uses_curl_and_waits():
    """Exercise unpredictable responses and independently observe requests and timing."""
    token1 = "B1-" + uuid.uuid4().hex
    token2 = "B2-" + uuid.uuid4().hex
    events = []
    servers = start_backends((token1, token2), events)
    proxy = None
    trace_path = "/tmp/curl-invocations.bin"
    if os.path.exists(trace_path):
        os.remove(trace_path)
    curl_path = real_path = None

    try:
        proxy = start_haproxy()
        curl_path, real_path = install_curl_tracer(trace_path)
        log_file = run_verify()

        assert len(events) == 4, f"Expected exactly four backend HTTP requests, observed {len(events)}"
        assert all(method == "GET" and path == "/health" for _, method, path, _, _ in events), "Every request must be GET /health"
        assert [identity for identity, _, _, _, _ in events].count("B1") == 2, "backend1 must receive two requests"
        assert [identity for identity, _, _, _, _ in events].count("B2") == 2, "backend2 must receive two requests"

        times = [event[3] for event in events]
        gaps = [later - earlier for earlier, later in zip(times, times[1:])]
        assert all(gap >= 0.85 for gap in gaps), f"Requests were not separated by one-second waits: {gaps}"

        expected = b"".join(event[4].encode() + b"\n" for event in events)
        with open(log_file, "rb") as f:
            actual = f.read()
        assert actual == expected, "health_check.log must contain each exact raw curl response on its own line"

        assert os.path.exists(trace_path), "verify.sh did not invoke the installed curl command"
        invocations = read_curl_trace(trace_path)
        assert len(invocations) == 4, f"Expected exactly four curl invocations, observed {len(invocations)}"
        for args in invocations:
            assert "-s" in args, f"Each curl invocation must use the -s flag; got {args}"
            assert args.count("http://127.0.0.1:8080/health") == 1, f"Each curl invocation must target the required URL; got {args}"
    finally:
        if curl_path is not None:
            restore_curl(curl_path, real_path)
        if proxy is not None:
            stop_haproxy(proxy)
        stop_backends(servers)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
