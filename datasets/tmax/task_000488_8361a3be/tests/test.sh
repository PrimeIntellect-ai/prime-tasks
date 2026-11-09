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

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import re
import signal
import socket
import subprocess
import time
import urllib.parse

import pytest
import requests

HEADER_PATH = "/app/vendored/cxxopts/include/cxxopts.hpp"
SOURCE_PATH = "/home/user/artifact_scorer.cpp"
BINARY_PATH = "/tmp/artifact_scorer_verified"


def test_cxxopts_fixed():
    """Preserve the original check that the missing standard include was restored."""
    assert os.path.isfile(HEADER_PATH), f"Vendored header not found at {HEADER_PATH}"
    with open(HEADER_PATH, "r", encoding="utf-8") as f:
        content = f.read()
    assert "#include <string>" in content, \
        "The file cxxopts.hpp is still missing '#include <string>'."


def check_cases_with_requests(url, test_cases, require_protocol_headers=False):
    for expr, x_value, expected in test_cases:
        try:
            response = requests.post(
                url,
                data={"expr": expr, "x": format(x_value, ".17g")},
                timeout=5,
            )
        except requests.exceptions.RequestException as e:
            pytest.fail(f"Failed to connect to the server at {url} or request failed: {e}")

        assert response.status_code == 200, \
            f"Expected HTTP 200 OK, got {response.status_code} for {expr!r}"

        if require_protocol_headers:
            content_type = response.headers.get("Content-Type", "")
            assert content_type.lower().startswith("text/plain"), \
                f"Expected Content-Type: text/plain, got {content_type!r}"
            assert "Content-Length" in response.headers, "Response omitted Content-Length"
            assert int(response.headers["Content-Length"]) == len(response.content), \
                "Response Content-Length does not match its body"

        text = response.text.strip()
        assert re.fullmatch(r"[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?", text), \
            f"Expected the response body to contain solely a numerical result, got {response.text!r}"
        result = float(text)
        assert math.isclose(result, expected, rel_tol=1e-5, abs_tol=1e-6), \
            f"Evaluation failed for expr={expr!r}, x={x_value!r}. Expected {expected}, got {result}"


def test_server_running_and_evaluates_math():
    """Preserve the original port-8080 checks and hardcoded cases."""
    cases = [
        ("3*x^2+2*x-5", 4.5, 64.75),
        ("(x+2)*(x-3)", 10.0, 84.0),
        ("2*x^2+3*x-1", 5.0, 64.0),
    ]
    check_cases_with_requests("http://127.0.0.1:8080/score", cases)


def inspect_and_compile_submission():
    assert os.path.isfile(SOURCE_PATH), f"Required C++ source not found at {SOURCE_PATH}"
    with open(SOURCE_PATH, "r", encoding="utf-8", errors="replace") as f:
        source = f.read()

    assert re.search(r"#\s*include\s*[<\"][^>\"\n]*cxxopts\.hpp[>\"]", source), \
        "The submitted source does not include the vendored cxxopts header"
    assert re.search(r"\bcxxopts\s*::\s*Options\b", source), \
        "The submitted source does not construct cxxopts::Options"
    assert re.search(r"\.\s*parse\s*\(", source), \
        "The submitted source does not parse command-line arguments with cxxopts"

    compile_result = subprocess.run(
        [
            "g++", "-std=c++17", "-O2", "-pthread",
            "-I/app/vendored/cxxopts/include",
            SOURCE_PATH, "-o", BINARY_PATH,
        ],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=40,
    )
    assert compile_result.returncode == 0, \
        f"The required C++ source did not compile with the fixed cxxopts header:\n{compile_result.stdout}"

    symbols = subprocess.run(
        ["nm", "-D", BINARY_PATH],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=10,
        check=True,
    ).stdout
    for symbol in ("socket", "bind", "listen"):
        assert re.search(rf"\b{symbol}(?:@|\b)", symbols), \
            f"Compiled server does not use the POSIX {symbol} function"
    assert re.search(r"\baccept(?:4)?(?:@|\b)", symbols), \
        "Compiled server does not use the POSIX accept function"


def free_port():
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


@pytest.fixture(scope="module")
def compiled_server():
    inspect_and_compile_submission()
    port = free_port()
    process = subprocess.Popen(
        [BINARY_PATH, "--port", str(port)],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )

    deadline = time.time() + 6
    while time.time() < deadline:
        if process.poll() is not None:
            pytest.fail(f"Server compiled from {SOURCE_PATH} exited before listening")
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.2):
                break
        except OSError:
            time.sleep(0.05)
    else:
        process.kill()
        pytest.fail(f"Server compiled from {SOURCE_PATH} did not listen on --port {port}")

    yield process, port

    if process.poll() is None:
        try:
            os.killpg(process.pid, signal.SIGTERM)
            process.wait(timeout=2)
        except (ProcessLookupError, subprocess.TimeoutExpired):
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass


def generated_cases():
    """Create verifier-time expressions and derive their answers independently."""
    rng = random.SystemRandom()
    cases = []

    for _ in range(6):
        a, b, c, d = [rng.randint(2, 13) for _ in range(4)]
        x = rng.uniform(0.75, 5.25)
        cases.extend([
            (f"{a}+x*{b}-{c}/{d}", x, a + x * b - c / d),
            (f"({a}+x)*({b}-x)+{c}", x, (a + x) * (b - x) + c),
            (f"({a}-x)^2+{b}/(x+{c})", x, (a - x) ** 2 + b / (x + c)),
        ])

    # Explicitly exercise left associativity, nested grouping, every operator,
    # and right-associative exponentiation with values chosen only at test time.
    a, b, c = [rng.randint(3, 11) for _ in range(3)]
    x = rng.uniform(1.0, 4.0)
    cases.extend([
        (f"{a}-x-{b}", x, (a - x) - b),
        (f"{a}/x*{b}", x, (a / x) * b),
        (f"(({a}+x)/({b}+x))^3-{c}*x", x,
         ((a + x) / (b + x)) ** 3 - c * x),
        ("2^3^2+x", x, 2 ** (3 ** 2) + x),
    ])
    rng.shuffle(cases)
    return cases


def test_compiled_source_supports_general_math(compiled_server):
    process, port = compiled_server
    cases = generated_cases()
    check_cases_with_requests(
        f"http://127.0.0.1:{port}/score",
        cases,
        require_protocol_headers=True,
    )
    assert process.poll() is None, "Server did not stay alive after serving requests"


def raw_fragmented_post(port, expr, x_value):
    body = urllib.parse.urlencode({"expr": expr, "x": format(x_value, ".17g")}).encode("ascii")
    request = (
        b"POST /score HTTP/1.1\r\n"
        b"Host: 127.0.0.1\r\n"
        b"Content-Type: application/x-www-form-urlencoded\r\n"
        + f"Content-Length: {len(body)}\r\n".encode("ascii")
        + b"Connection: close\r\n\r\n"
        + body
    )

    # Deliberately split the header terminator, Content-Length line, and body.
    cuts = [5, 19, 43, 71, len(request) - len(body) - 2,
            len(request) - len(body) + 1, len(request) - max(1, len(body) // 2)]
    cuts = sorted({cut for cut in cuts if 0 < cut < len(request)})
    chunks = []
    start = 0
    for cut in cuts + [len(request)]:
        chunks.append(request[start:cut])
        start = cut

    with socket.create_connection(("127.0.0.1", port), timeout=5) as sock:
        sock.settimeout(5)
        for chunk in chunks:
            if chunk:
                sock.sendall(chunk)
                time.sleep(0.02)

        response = b""
        expected_total = None
        while True:
            if expected_total is not None and len(response) >= expected_total:
                break
            part = sock.recv(4096)
            if not part:
                break
            response += part
            marker = response.find(b"\r\n\r\n")
            if marker >= 0 and expected_total is None:
                header_text = response[:marker].decode("iso-8859-1")
                match = re.search(r"(?im)^Content-Length:\s*(\d+)\s*$", header_text)
                assert match, "Response to fragmented request omitted Content-Length"
                expected_total = marker + 4 + int(match.group(1))

    return response


def test_fragmented_http_state_machine_and_protocol(compiled_server):
    process, port = compiled_server
    rng = random.SystemRandom()
    a, b, c = [rng.randint(2, 17) for _ in range(3)]
    x = rng.uniform(0.8, 4.8)
    expr = f"(({a}+x)*({b}-x))/{c}+x^2"
    expected = ((a + x) * (b - x)) / c + x ** 2

    response = raw_fragmented_post(port, expr, x)
    marker = response.find(b"\r\n\r\n")
    assert marker >= 0, "Response is not a valid HTTP response with CRLF header termination"
    header_text = response[:marker].decode("iso-8859-1")
    body = response[marker + 4:]

    assert re.match(r"^HTTP/1\.1 200(?: OK)?\r\n", header_text + "\r\n"), \
        f"Expected HTTP/1.1 200 OK, got {header_text.splitlines()[0] if header_text else response!r}"
    assert re.search(r"(?im)^Content-Type:\s*text/plain(?:\s*;[^\r\n]*)?\s*$", header_text), \
        "Response omitted Content-Type: text/plain"
    length_match = re.search(r"(?im)^Content-Length:\s*(\d+)\s*$", header_text)
    assert length_match and int(length_match.group(1)) == len(body), \
        "Response Content-Length is missing or incorrect"

    text = body.decode("ascii")
    assert re.fullmatch(r"[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?", text), \
        f"Response body was not solely a numerical result: {text!r}"
    assert math.isclose(float(text), expected, rel_tol=1e-5, abs_tol=1e-6)
    assert process.poll() is None, "Server stopped after the fragmented request"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
