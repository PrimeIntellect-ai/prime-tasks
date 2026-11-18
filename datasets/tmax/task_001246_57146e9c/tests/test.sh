#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import string
import subprocess
import pytest

CPP_SOURCE = "/home/user/url_sanitizer.cpp"
COMPILED_BINARY = "/home/user/sanitizer"
CLEAN_CORPUS = "/app/clean_urls.txt"
EVIL_CORPUS = "/app/evil_urls.txt"


def run_binary(url=None):
    command = [COMPILED_BINARY]
    if url is not None:
        command.append(url)
    env = os.environ.copy()
    env["ASAN_OPTIONS"] = "detect_leaks=1:halt_on_error=1"
    try:
        return subprocess.run(
            command, capture_output=True, text=True, timeout=5, env=env
        )
    except subprocess.TimeoutExpired:
        pytest.fail(f"Sanitizer timed out for input: {url!r}")


def assert_no_sanitizer_error(result, url):
    diagnostics = result.stderr
    assert "AddressSanitizer" not in diagnostics, \
        f"AddressSanitizer error for {url!r}:\n{diagnostics}"
    assert "LeakSanitizer" not in diagnostics, \
        f"LeakSanitizer error for {url!r}:\n{diagnostics}"


def whiteboard_allows(url):
    if url.startswith("ws://"):
        remainder = url[5:]
    elif url.startswith("wss://"):
        remainder = url[6:]
    else:
        return False

    # A URL with no authority, whitespace, or control characters is malformed.
    authority_end = len(remainder)
    for separator in "/?#":
        position = remainder.find(separator)
        if position != -1:
            authority_end = min(authority_end, position)
    authority = remainder[:authority_end]
    if not authority or any(ch.isspace() or ord(ch) < 32 for ch in url):
        return False

    route = remainder[authority_end:]
    route_before_fragment = route.split("#", 1)[0]
    if "?" not in route_before_fragment:
        return False
    path, query = route_before_fragment.split("?", 1)

    if "/admin/" in path:
        return False

    token_values = []
    for parameter in query.split("&"):
        if "=" in parameter:
            key, value = parameter.split("=", 1)
            if key == "token":
                token_values.append(value)

    return bool(token_values) and all(
        re.fullmatch(r"[A-Za-z0-9]{16}", value) is not None
        for value in token_values
    )


def test_source_file_exists():
    assert os.path.isfile(CPP_SOURCE), f"The C++ source file {CPP_SOURCE} does not exist."


def test_compilation():
    compile_cmd = [
        "g++", "-std=c++17", "-O2", "-fsanitize=address", "-Wall",
        CPP_SOURCE, "-o", COMPILED_BINARY
    ]
    result = subprocess.run(compile_cmd, capture_output=True, text=True)
    assert result.returncode == 0, f"Compilation failed:\n{result.stderr}"
    assert os.path.isfile(COMPILED_BINARY), \
        f"Compiled binary {COMPILED_BINARY} was not created."


def test_adversarial_corpus():
    if not os.path.isfile(COMPILED_BINARY):
        pytest.fail("Compiled binary missing, cannot run corpus tests.")

    with open(CLEAN_CORPUS, "r") as f:
        clean_urls = [line.strip() for line in f if line.strip()]
    with open(EVIL_CORPUS, "r") as f:
        evil_urls = [line.strip() for line in f if line.strip()]

    clean_failures = []
    evil_failures = []
    asan_errors = []

    for url in clean_urls:
        result = run_binary(url)
        if "AddressSanitizer" in result.stderr or "LeakSanitizer" in result.stderr:
            asan_errors.append(url)
        elif result.returncode != 0:
            clean_failures.append(url)

    for url in evil_urls:
        result = run_binary(url)
        if "AddressSanitizer" in result.stderr or "LeakSanitizer" in result.stderr:
            asan_errors.append(url)
        elif result.returncode == 0:
            evil_failures.append(url)

    error_msg = []
    if asan_errors:
        error_msg.append(f"{len(asan_errors)} URLs triggered sanitizer errors.")
    if clean_failures:
        error_msg.append(
            f"{len(clean_failures)} of {len(clean_urls)} clean URLs modified/rejected: {clean_failures}"
        )
    if evil_failures:
        error_msg.append(
            f"{len(evil_failures)} of {len(evil_urls)} evil URLs bypassed/accepted: {evil_failures}"
        )
    if error_msg:
        pytest.fail(" | ".join(error_msg))


def random_text(length):
    alphabet = string.ascii_letters + string.digits
    return "".join(secrets.choice(alphabet) for _ in range(length))


def test_generated_whiteboard_cases():
    if not os.path.isfile(COMPILED_BINARY):
        pytest.fail("Compiled binary missing, cannot run generated tests.")

    cases = []
    for index in range(12):
        token = random_text(16)
        host = random_text(10).lower() + ".example"
        scheme = secrets.choice(["ws://", "wss://"])
        path = "/route/" + random_text(8)
        valid = f"{scheme}{host}{path}?room={index}&token={token}&region=us"

        cases.extend([
            valid,
            f"{scheme}{host}/administrator/view?token={token}",
            f"{scheme}admin.{host}{path}?note=/admin/&token={token}",
            "http://" + valid.split("://", 1)[1],
            valid.replace(scheme, scheme.upper(), 1),
            f"{scheme}{host}/safe/admin/panel?token={token}",
            f"{scheme}{host}{path}?token={token[:-1]}",
            f"{scheme}{host}{path}?token={token}Z",
            f"{scheme}{host}{path}?token={token[:-1]}!",
            f"{scheme}{host}{path}?room={index}",
            f"{scheme}{host}{path}?tok={token}",
            f"{scheme}{host}{path}#ignored?token={token}",
            f"{scheme}?token={token}",
            f"{scheme}{host}{path}",
        ])

    for url in cases:
        expected = 0 if whiteboard_allows(url) else 1
        result = run_binary(url)
        assert_no_sanitizer_error(result, url)
        assert result.returncode == expected, (
            f"Incorrect classification for generated URL {url!r}: "
            f"expected exit {expected}, got {result.returncode}. "
            f"stdout={result.stdout!r}, stderr={result.stderr!r}"
        )


def test_missing_argument_is_denied():
    result = run_binary()
    assert_no_sanitizer_error(result, "<missing argv[1]>")
    assert result.returncode == 1, \
        f"Missing URL argument must exit 1, got {result.returncode}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
