#!/bin/bash
mkdir -p /logs/verifier

# Stop the image's mock server so verification can use a controlled, instrumented server.
pkill -f '/tmp/mock_server.py' 2>/dev/null || true
sleep 0.2

cat << 'PY_EOF' > /tmp/verify_fetch_behavior.py
import hashlib
import os
import shutil
import stat
import subprocess
import threading
import time
import uuid
from http.server import BaseHTTPRequestHandler, HTTPServer

SCRIPT = "/home/user/fetch_deps.sh"
MANIFEST = "/home/user/build_manifest.bld"
LOG = "/home/user/build.log"
CACHE = "/home/user/build_cache"

state = {
    "files": {},
    "last_request": 0.0,
    "requests": [],
}
lock = threading.Lock()

class ReusableHTTPServer(HTTPServer):
    allow_reuse_address = True

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        now = time.monotonic()
        with lock:
            if now - state["last_request"] < 1.0:
                state["requests"].append((self.path, 429))
                self.send_response(429)
                self.end_headers()
                self.wfile.write(b"Too Many Requests")
                return
            state["last_request"] = now

            prefix = "/deps/"
            name = self.path[len(prefix):] if self.path.startswith(prefix) else None
            if name is not None and name in state["files"]:
                body = state["files"][name]
                status = 200
            else:
                body = b"Not Found"
                status = 404
            state["requests"].append((self.path, status))

        self.send_response(status)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):
        pass


def sha(data):
    return hashlib.sha256(data).hexdigest()


def reset_outputs():
    if os.path.lexists(LOG):
        os.remove(LOG)
    if os.path.lexists(CACHE):
        if os.path.isdir(CACHE) and not os.path.islink(CACHE):
            shutil.rmtree(CACHE)
        else:
            os.remove(CACHE)


def run_case(entries, served_files, expected_lines, expected_cached):
    reset_outputs()
    with open(MANIFEST, "w", encoding="utf-8") as f:
        for language, name, expected_hash in entries:
            f.write(f"{language}|{name}|{expected_hash}\n")

    with lock:
        state["files"] = dict(served_files)
        state["last_request"] = 0.0
        state["requests"] = []

    result = subprocess.run(
        [SCRIPT],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
        text=True,
    )
    assert result.returncode == 0, (
        f"fetch_deps.sh exited with {result.returncode}. "
        f"stdout={result.stdout!r}, stderr={result.stderr!r}"
    )

    assert os.path.isfile(LOG), "The script did not create /home/user/build.log"
    with open(LOG, "r", encoding="utf-8") as f:
        lines = [line.strip() for line in f if line.strip()]
    assert lines == expected_lines, f"Unexpected build.log contents: {lines!r}"

    assert os.path.isdir(CACHE), "The script did not create /home/user/build_cache"
    for _, name, _ in entries:
        path = os.path.join(CACHE, name)
        if name in expected_cached:
            expected = expected_cached[name]
            assert os.path.isfile(path), f"Cached dependency {name!r} is missing"
            with open(path, "rb") as f:
                actual = f.read()
            assert actual == expected, f"Cached dependency {name!r} has incorrect contents"
            assert sha(actual) == sha(expected), f"Cached dependency {name!r} has an incorrect checksum"
        else:
            assert not os.path.exists(path), f"Dependency {name!r} should not have been cached"

    with lock:
        requests = list(state["requests"])
    for _, name, _ in entries:
        path = "/deps/" + name
        assert any(p == path for p, _ in requests), f"The server was never asked for {path}"
        expected_status = 200 if name in served_files else 404
        assert any(p == path and status == expected_status for p, status in requests), (
            f"No completed HTTP {expected_status} request was made for {path}; requests={requests!r}"
        )


assert os.path.isfile(SCRIPT), f"Script {SCRIPT} does not exist."
assert os.stat(SCRIPT).st_mode & stat.S_IXUSR, f"Script {SCRIPT} is not executable."

server = ReusableHTTPServer(("127.0.0.1", 8080), Handler)
thread = threading.Thread(target=server.serve_forever, daemon=True)
thread.start()

try:
    # Use unpredictable names and contents so pre-created logs and arbitrary cache files cannot pass.
    token = uuid.uuid4().hex
    good1 = "alpha_" + token
    good2 = "beta_" + token
    bad = "bad_" + token
    missing = "missing_" + token
    body1 = os.urandom(41)
    body2 = os.urandom(57)
    bad_body = os.urandom(49)
    wrong_hash = sha(b"different expected data" + os.urandom(16))
    if wrong_hash == sha(bad_body):
        wrong_hash = "0" * 64

    run_case(
        [
            ("PYTHON", good1, sha(body1)),
            ("RUST", good2, sha(body2)),
            ("JS", bad, wrong_hash),
            ("GO", missing, sha(os.urandom(23))),
        ],
        {good1: body1, good2: body2, bad: bad_body},
        [
            "SUCCESS: " + good1,
            "SUCCESS: " + good2,
            "CHECKSUM_FAILED: " + bad,
            "NOT_FOUND: " + missing,
        ],
        {good1: body1, good2: body2},
    )

    # Re-run the shipped manifest case, retaining the original verifier's assertions.
    requests_body = b"print('requests')\n"
    serde_body = b"fn serde() {}\n"
    lodash_body = b"function lodash() {}\n"
    original_entries = [
        ("PYTHON", "requests", "e134621c5040669b7bb6933bb3e31ecbaea2b3c20c02fb367e9f390d40e4ab7d"),
        ("RUST", "serde", "f22f281e59273c524e4c29ea76d2036c0a0058b297bcf95da4e8c1050e8200dd"),
        ("JS", "lodash", "0" * 64),
        ("GO", "gin", "not_real_will_404"),
    ]
    assert sha(requests_body) == original_entries[0][2]
    assert sha(serde_body) == original_entries[1][2]

    run_case(
        original_entries,
        {"requests": requests_body, "serde": serde_body, "lodash": lodash_body},
        [
            "SUCCESS: requests",
            "SUCCESS: serde",
            "CHECKSUM_FAILED: lodash",
            "NOT_FOUND: gin",
        ],
        {"requests": requests_body, "serde": serde_body},
    )
finally:
    server.shutdown()
    server.server_close()
    thread.join(timeout=2)
PY_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import stat

def test_script_exists_and_executable():
    script_path = "/home/user/fetch_deps.sh"
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."
    st = os.stat(script_path)
    assert st.st_mode & stat.S_IXUSR, f"Script {script_path} is not executable."

def test_build_log_content():
    log_path = "/home/user/build.log"
    assert os.path.isfile(log_path), f"Log file {log_path} does not exist."

    with open(log_path, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    expected_lines = [
        "SUCCESS: requests",
        "SUCCESS: serde",
        "CHECKSUM_FAILED: lodash",
        "NOT_FOUND: gin"
    ]

    assert lines == expected_lines, f"Log file {log_path} contents do not match expected output. Got: {lines}"

def test_build_cache_contents():
    cache_dir = "/home/user/build_cache"
    assert os.path.isdir(cache_dir), f"Cache directory {cache_dir} does not exist."

    requests_path = os.path.join(cache_dir, "requests")
    serde_path = os.path.join(cache_dir, "serde")
    lodash_path = os.path.join(cache_dir, "lodash")
    gin_path = os.path.join(cache_dir, "gin")

    assert os.path.isfile(requests_path), f"Dependency {requests_path} is missing."
    assert os.path.isfile(serde_path), f"Dependency {serde_path} is missing."
    assert not os.path.exists(lodash_path), f"Dependency {lodash_path} should not exist."
    assert not os.path.exists(gin_path), f"Dependency {gin_path} should not exist."

    with open(requests_path, "rb") as f:
        requests_data = f.read()
    with open(serde_path, "rb") as f:
        serde_data = f.read()
    assert requests_data == b"print('requests')\n"
    assert serde_data == b"fn serde() {}\n"
    assert hashlib.sha256(requests_data).hexdigest() == "e134621c5040669b7bb6933bb3e31ecbaea2b3c20c02fb367e9f390d40e4ab7d"
    assert hashlib.sha256(serde_data).hexdigest() == "f22f281e59273c524e4c29ea76d2036c0a0058b297bcf95da4e8c1050e8200dd"
TEST_EOF

if python3 /tmp/verify_fetch_behavior.py && python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
