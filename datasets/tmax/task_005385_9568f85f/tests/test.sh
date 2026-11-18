#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "requests:requests"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/verify_proxy.py
import http.cookies
import http.server
import os
import secrets
import signal
import socketserver
import subprocess
import threading
import time
import traceback
import urllib.parse

import requests

PROXY = "http://127.0.0.1:9000"
LEGACY = "http://127.0.0.1:8080"
OLD_PASSWORD = "v1nt4g3_p4ssw0rd"
NEW_PASSWORD = "SuperSafeRotated99"
legacy_was_stopped = False
fake_server = None
original_proxy_pids = set()


def assert_true(value, message):
    if not value:
        raise AssertionError(message)


def proc_exe(pid):
    try:
        return os.path.realpath(os.readlink(f"/proc/{pid}/exe"))
    except OSError:
        return None


def pids_for_executable(path):
    wanted = os.path.realpath(path)
    result = set()
    for name in os.listdir("/proc"):
        if name.isdigit() and proc_exe(name) == wanted:
            result.add(int(name))
    return result


def listening_socket_inodes(port, required_addr=None):
    result = set()
    port_hex = f"{port:04X}"
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    addr, found_port = fields[1].rsplit(":", 1)
                    if found_port.upper() != port_hex or fields[3] != "0A":
                        continue
                    if required_addr is not None and addr.upper() != required_addr.upper():
                        continue
                    result.add(fields[9])
        except FileNotFoundError:
            pass
    return result


def pids_owning_inodes(inodes):
    result = set()
    wanted = {f"socket:[{inode}]" for inode in inodes}
    if not wanted:
        return result
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        fd_dir = f"/proc/{name}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    if os.readlink(os.path.join(fd_dir, fd)) in wanted:
                        result.add(int(name))
                        break
                except OSError:
                    pass
        except OSError:
            pass
    return result


def listener_pids(port, required_addr=None):
    return pids_owning_inodes(listening_socket_inodes(port, required_addr))


def wait_until(predicate, timeout=5):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            value = predicate()
            if value:
                return value
        except Exception:
            pass
        time.sleep(0.05)
    return None


def direct_legacy_probe():
    marker = secrets.token_hex(5)
    response = requests.post(
        f"{LEGACY}/login?redirect=/probe-{marker}",
        data={"username": "admin", "password": OLD_PASSWORD},
        allow_redirects=False,
        timeout=2,
    )
    return response.status_code == 302 and response.headers.get("Location") == f"/probe-{marker}" and "session_id=deadbeef12345678" in response.headers.get("Set-Cookie", "")


def stop_legacy():
    global legacy_was_stopped
    pids = pids_for_executable("/app/legacy_auth")
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    time.sleep(0.15)
    for pid in pids_for_executable("/app/legacy_auth"):
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    assert_true(wait_until(lambda: not listening_socket_inodes(8080), 3), "Could not temporarily release the legacy backend port")
    legacy_was_stopped = True


def restore_legacy():
    global legacy_was_stopped
    if not legacy_was_stopped:
        return
    if not pids_for_executable("/app/legacy_auth"):
        subprocess.Popen(
            ["/app/legacy_auth"],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
    assert_true(wait_until(direct_legacy_probe, 5), "The real /app/legacy_auth service was not running after verification")
    legacy_was_stopped = False


def check_cookie(response, expected_value):
    raw = response.headers.get("Set-Cookie")
    assert_true(raw is not None, "Successful login did not return Set-Cookie")
    jar = http.cookies.SimpleCookie()
    try:
        jar.load(raw)
    except http.cookies.CookieError as exc:
        raise AssertionError(f"Malformed Set-Cookie header: {raw}") from exc
    assert_true("session_id" in jar, f"Backend session cookie was not preserved: {raw}")
    morsel = jar["session_id"]
    assert_true(morsel.value == expected_value, "Proxy did not relay the backend's dynamically generated session value")
    assert_true(bool(morsel["secure"]), f"Secure attribute missing: {raw}")
    assert_true(bool(morsel["httponly"]), f"HttpOnly attribute missing: {raw}")
    assert_true(morsel["samesite"].lower() == "strict", f"SameSite=Strict attribute missing: {raw}")


def main():
    global fake_server, original_proxy_pids

    # Verify the required processes and bindings before replacing the backend with
    # a challenge server. In particular, port 8080 must really belong to the
    # supplied executable, and the proxy must use the required IPv4 wildcard bind.
    legacy_pids = pids_for_executable("/app/legacy_auth")
    assert_true(legacy_pids, "/app/legacy_auth is not running")
    backend_owners = listener_pids(8080, "0100007F")
    assert_true(legacy_pids & backend_owners, "/app/legacy_auth is not the process listening on 127.0.0.1:8080")
    assert_true(direct_legacy_probe(), "The running legacy backend does not behave as the supplied service")

    wildcard_inodes = listening_socket_inodes(9000, "00000000")
    assert_true(wildcard_inodes, "The proxy is not listening on the required IPv4 address 0.0.0.0:9000")
    original_proxy_pids = pids_owning_inodes(wildcard_inodes)
    assert_true(original_proxy_pids, "Could not identify the process listening on 0.0.0.0:9000")

    challenge = secrets.token_hex(12)
    cookie_value = "dyn_" + secrets.token_hex(16)
    proof = "backend_" + secrets.token_hex(16)
    records = []
    records_lock = threading.Lock()

    class ReusableThreadingServer(socketserver.ThreadingMixIn, http.server.HTTPServer):
        daemon_threads = True
        allow_reuse_address = True

    class Handler(http.server.BaseHTTPRequestHandler):
        protocol_version = "HTTP/1.1"

        def log_message(self, fmt, *args):
            pass

        def handle_any(self):
            length = int(self.headers.get("Content-Length", "0"))
            body = self.rfile.read(length) if length else b""
            with records_lock:
                records.append((self.command, self.path, dict(self.headers), body))

            parsed = urllib.parse.urlsplit(self.path)
            query = urllib.parse.parse_qs(parsed.query, keep_blank_values=True)
            form = urllib.parse.parse_qs(body.decode("utf-8", "replace"), keep_blank_values=True)
            valid = form.get("username") == ["admin"] and form.get("password") == [OLD_PASSWORD]

            if valid:
                redirect = query.get("redirect", ["/"])[0]
                self.send_response(302)
                self.send_header("Location", redirect)
                self.send_header("Set-Cookie", f"session_id={cookie_value}; Path=/")
                payload = b""
            else:
                self.send_response(401)
                payload = ("rejected-by-real-backend-" + challenge).encode()
                self.send_header("Content-Type", "text/plain")

            self.send_header("X-Backend-Proof", proof)
            self.send_header("Content-Length", str(len(payload)))
            self.send_header("Connection", "close")
            self.end_headers()
            if payload:
                self.wfile.write(payload)
            self.close_connection = True

        do_GET = handle_any
        do_POST = handle_any
        do_PUT = handle_any
        do_DELETE = handle_any
        do_PATCH = handle_any

    stop_legacy()
    fake_server = ReusableThreadingServer(("127.0.0.1", 8080), Handler)
    thread = threading.Thread(target=fake_server.serve_forever, daemon=True)
    thread.start()

    def post(path, password):
        return requests.post(
            PROXY + path,
            data={"username": "admin", "password": password},
            allow_redirects=False,
            timeout=5,
        )

    # Rotated credentials must be translated and the response must come from the
    # backend. The unpredictable cookie and proof prevent fixed-response servers.
    evil_host = f"evil-{secrets.token_hex(6)}.example"
    malicious_path = f"/login?redirect=https://{evil_host}/steal"
    response = post(malicious_path, NEW_PASSWORD)
    assert_true(response.status_code == 302, f"Rotated credentials returned {response.status_code}, expected 302")
    assert_true(response.headers.get("Location") == "/dashboard", "Absolute https redirect was not sanitized")
    assert_true(response.headers.get("X-Backend-Proof") == proof, "Response was not relayed from the backend")
    check_cookie(response, cookie_value)

    network_path = f"/login?redirect=//{evil_host}/other"
    response = post(network_path, NEW_PASSWORD)
    assert_true(response.status_code == 302, "Rotated credentials failed for a network-path redirect")
    assert_true(response.headers.get("Location") == "/dashboard", "A //host absolute redirect was not sanitized")
    check_cookie(response, cookie_value)

    relative = f"/settings/{secrets.token_hex(8)}"
    safe_path = f"/login?redirect={relative}"
    response = post(safe_path, NEW_PASSWORD)
    assert_true(response.status_code == 302, "Rotated credentials failed for a relative redirect")
    assert_true(response.headers.get("Location") == relative, "A valid relative redirect was not preserved")
    check_cookie(response, cookie_value)

    # A non-new password must be forwarded unchanged. A randomized value proves
    # the request was not answered by a fixed 401 response.
    wrong_password = "wrong_" + secrets.token_hex(10)
    wrong_path = f"/login?redirect=/wrong-{secrets.token_hex(4)}"
    response = post(wrong_path, wrong_password)
    assert_true(response.status_code == 401, f"Wrong password returned {response.status_code}, expected backend 401")
    assert_true(response.headers.get("X-Backend-Proof") == proof, "Wrong-password request did not reach the backend")
    assert_true(response.text == "rejected-by-real-backend-" + challenge, "Backend rejection body was not relayed")

    # The instruction explicitly says every non-new password is forwarded as-is.
    # Consequently the actual old password succeeds at this legacy backend.
    old_relative = f"/old-{secrets.token_hex(7)}"
    old_path = f"/login?redirect={old_relative}"
    response = post(old_path, OLD_PASSWORD)
    assert_true(response.status_code == 302, "The old password was not forwarded as-is as required")
    assert_true(response.headers.get("Location") == old_relative, "Old-password backend redirect was not relayed")
    check_cookie(response, cookie_value)

    # Exercise ordinary proxying outside the three login cases.
    general_path = f"/api/{secrets.token_hex(8)}?q={secrets.token_hex(5)}"
    response = requests.get(PROXY + general_path, headers={"X-Challenge": challenge}, timeout=5)
    assert_true(response.status_code == 401, "General GET response status was not relayed")
    assert_true(response.headers.get("X-Backend-Proof") == proof, "General GET did not use the backend")
    assert_true(response.text == "rejected-by-real-backend-" + challenge, "General GET body was not relayed")

    with records_lock:
        snapshot = list(records)

    def records_for(path):
        return [r for r in snapshot if r[1] == path]

    for path in (malicious_path, network_path, safe_path):
        matches = records_for(path)
        assert_true(matches, f"Backend never received request target {path}")
        form = urllib.parse.parse_qs(matches[-1][3].decode("utf-8", "replace"))
        assert_true(form.get("password") == [OLD_PASSWORD], "New password was not translated to the discovered legacy password")

    wrong_matches = records_for(wrong_path)
    assert_true(wrong_matches, "Wrong-password request was not forwarded")
    wrong_form = urllib.parse.parse_qs(wrong_matches[-1][3].decode("utf-8", "replace"))
    assert_true(wrong_form.get("password") == [wrong_password], "A non-new password was modified instead of being forwarded as-is")

    old_matches = records_for(old_path)
    assert_true(old_matches, "Old-password request was not forwarded")
    old_form = urllib.parse.parse_qs(old_matches[-1][3].decode("utf-8", "replace"))
    assert_true(old_form.get("password") == [OLD_PASSWORD], "Old password was not forwarded as-is")

    general_matches = records_for(general_path)
    assert_true(general_matches and general_matches[-1][0] == "GET", "General method/path forwarding failed")
    assert_true(general_matches[-1][2].get("X-Challenge") == challenge, "Ordinary request headers were not forwarded")

    fake_server.shutdown()
    fake_server.server_close()
    fake_server = None
    restore_legacy()

    assert_true(any(os.path.exists(f"/proc/{pid}") for pid in original_proxy_pids), "The proxy process did not remain running")
    assert_true(listening_socket_inodes(9000, "00000000"), "The proxy stopped listening on 0.0.0.0:9000")
    restored_pids = pids_for_executable("/app/legacy_auth")
    assert_true(restored_pids & listener_pids(8080, "0100007F"), "The legacy executable is not running on 127.0.0.1:8080")

    final_relative = f"/final-{secrets.token_hex(5)}"
    final_response = post(f"/login?redirect={final_relative}", NEW_PASSWORD)
    assert_true(final_response.status_code == 302, "Proxy did not remain functional with the real legacy process")
    assert_true(final_response.headers.get("Location") == final_relative, "Final real-backend redirect was not preserved")
    check_cookie(final_response, "deadbeef12345678")


try:
    main()
except Exception:
    traceback.print_exc()
    raise
finally:
    if fake_server is not None:
        try:
            fake_server.shutdown()
            fake_server.server_close()
        except Exception:
            pass
    if legacy_was_stopped:
        try:
            restore_legacy()
        except Exception:
            traceback.print_exc()
PY_EOF

if python3 /tmp/verify_proxy.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
