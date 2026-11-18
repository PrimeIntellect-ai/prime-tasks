#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import string
import subprocess
import urllib.error
import urllib.request

import pytest

AGENT_PATH = "/home/user/normalizer"
N_ITERATIONS = 100


def run_normalizer(payload):
    return subprocess.run(
        [AGENT_PATH], input=payload, capture_output=True, timeout=5
    )


def assert_output_lines(proc, expected_lines):
    assert proc.returncode == 0, (
        f"Expected exit code 0, got {proc.returncode}; "
        f"stdout={proc.stdout!r}, stderr={proc.stderr!r}"
    )
    try:
        actual = proc.stdout.decode("utf-8")
    except UnicodeDecodeError as exc:
        pytest.fail(f"Normalizer emitted invalid UTF-8: {exc}; output={proc.stdout!r}")
    assert actual.splitlines() == expected_lines, (
        f"Unexpected normalized output. Expected lines {expected_lines!r}, "
        f"got {actual.splitlines()!r}; raw output={proc.stdout!r}"
    )


def assert_error(payload, message):
    proc = run_normalizer(payload)
    assert proc.returncode == 1, (
        f"Expected exit code 1, got {proc.returncode}; "
        f"stdout={proc.stdout!r}, stderr={proc.stderr!r}"
    )
    encoded = message.encode("utf-8")
    assert proc.stdout in (encoded, encoded + b"\n"), (
        f"Expected {message!r} on stdout, got {proc.stdout!r}"
    )


def ascii_lower(value):
    return "".join(chr(ord(c) + 32) if "A" <= c <= "Z" else c for c in value)


def test_normalizer_exists_and_is_compiled_executable():
    assert os.path.isfile(AGENT_PATH), f"Agent normalizer not found at {AGENT_PATH}"
    assert os.access(AGENT_PATH, os.X_OK), f"Agent normalizer at {AGENT_PATH} is not executable"
    with open(AGENT_PATH, "rb") as artifact:
        assert artifact.read(4) == b"\x7fELF", "Normalizer must be a compiled executable"


def test_normalizer_core_rules():
    payload = (
        b"ignored line\n"
        b"+ DB_HOST=  localhost \t\r\n"
        b"- OLD_PORT\n"
        b"+ Greeting=\tHello \xf0\x9f\x8c\x8d  \n"
        b"+ DUP=first\n"
        b"- dup\n"
        b"+ DuP= final value \n"
        b"+bad=no-prefix-space\n"
        b"-bad\n"
        b"+ missing-equals\n"
    )
    assert_output_lines(
        run_normalizer(payload),
        [
            "+ db_host=localhost",
            "+ dup=final value",
            "+ greeting=Hello 🌍",
            "- old_port",
        ],
    )


def test_ascii_only_key_lowercasing_and_sorting():
    payload = "+ ÄA=value\n+ z_KEY=two\n+ A-key=one\n".encode("utf-8")
    assert_output_lines(
        run_normalizer(payload),
        ["+ a-key=one", "+ z_key=two", "+ Äa=value"],
    )


def test_empty_input_and_ignored_lines():
    assert_output_lines(run_normalizer(b""), [])
    assert_output_lines(
        run_normalizer(b"\ncomment\n + KEY=value\n+NOPE=value\n-NOPE\n"), []
    )


def test_utf8_validation_covers_entire_input():
    assert_error(b"+ GOOD=value\nignored \xff bytes\n", "ERROR: INVALID_UTF8")
    assert_error(b"+ KEY=bad\xc3\x28\n", "ERROR: INVALID_UTF8")


def test_value_length_is_measured_after_trimming_in_bytes():
    assert_output_lines(
        run_normalizer(b"+ KEY= \t" + b"a" * 50 + b"\r \n"),
        ["+ key=" + "a" * 50],
    )
    assert_error(b"+ KEY=" + b"a" * 51 + b"\n", "ERROR: LENGTH_EXCEEDED")

    fifty_utf8_bytes = ("é" * 25).encode("utf-8")
    assert_output_lines(
        run_normalizer(b"+ UTF8= " + fifty_utf8_bytes + b" \n"),
        ["+ utf8=" + "é" * 25],
    )
    assert_error(
        b"+ UTF8=" + ("é" * 26).encode("utf-8") + b"\n",
        "ERROR: LENGTH_EXCEEDED",
    )


def test_generated_normalization_cases():
    rng = random.SystemRandom()
    canonical_keys = ["alpha", "beta_2", "gamma-x", "port9", "zeta"]
    value_chars = list("abcXYZ019 _-=") + ["é", "界", "🌍"]

    for iteration in range(N_ITERATIONS):
        state = {}
        input_lines = ["", "ignored", "+invalid=x", " - also_ignored"]

        for _ in range(rng.randint(8, 25)):
            canonical = rng.choice(canonical_keys)
            presented_key = "".join(
                c.upper() if c.isalpha() and rng.choice((True, False)) else c
                for c in canonical
            )

            if rng.choice((True, False)):
                value = "".join(rng.choice(value_chars) for _ in range(rng.randint(1, 12)))
                left = rng.choice(["", " ", "\t", " \t"])
                right = rng.choice(["", " ", "\t", "\r", "\t "])
                input_lines.append(f"+ {presented_key}={left}{value}{right}")
                state[ascii_lower(presented_key)] = ("+", value)
            else:
                input_lines.append(f"- {presented_key}")
                state[ascii_lower(presented_key)] = ("-", None)

        payload = ("\n".join(input_lines) + "\n").encode("utf-8")
        expected = []
        for key in sorted(state):
            op, value = state[key]
            expected.append(f"+ {key}={value}" if op == "+" else f"- {key}")

        proc = run_normalizer(payload)
        try:
            assert_output_lines(proc, expected)
        except AssertionError as exc:
            raise AssertionError(
                f"Generated case {iteration} failed for input {payload!r}: {exc}"
            ) from exc


def test_redis_running_and_configured():
    try:
        import redis
        r = redis.Redis(host="127.0.0.1", port=6379, db=0)
        r.ping()
        info = r.info("memory")
        assert info.get("maxmemory") == 10485760, (
            f"Redis maxmemory is not 10mb. Found: {info.get('maxmemory')}"
        )
    except ImportError:
        res = subprocess.run(["redis-cli", "ping"], capture_output=True, text=True)
        assert "PONG" in res.stdout, "Redis is not running on port 6379"
        res_conf = subprocess.run(
            ["redis-cli", "CONFIG", "GET", "maxmemory"], capture_output=True, text=True
        )
        assert "10485760" in res_conf.stdout, (
            f"Redis maxmemory is not 10mb. Found: {res_conf.stdout}"
        )


def post_patch(payload):
    req = urllib.request.Request(
        "http://127.0.0.1:8080/patch", data=payload, method="POST"
    )
    try:
        with urllib.request.urlopen(req, timeout=5) as response:
            assert response.status == 200, f"Expected HTTP 200, got {response.status}"
    except urllib.error.URLError as exc:
        pytest.fail(f"Failed to connect to Nginx on port 8080: {exc}")


def test_end_to_end_flow():
    import redis

    r = redis.Redis(host="127.0.0.1", port=6379, db=0, decode_responses=True)
    r.delete("configs")

    fixed_payload = b"+ KEY=val\n- OLD\n+ Greeting=Hello \xf0\x9f\x8c\x8d"
    post_patch(fixed_payload)

    nonce = "".join(random.SystemRandom().choice(string.ascii_lowercase) for _ in range(16))
    dynamic_payload = (
        f"+ Z_{nonce}=  first  \n"
        f"- TEMP_{nonce}\n"
        f"+ z_{nonce}=second\n"
        f"+ A_{nonce}= value-{nonce} \n"
    ).encode("utf-8")
    post_patch(dynamic_payload)

    stored = r.lrange("configs", 0, -1)
    assert len(stored) == 2, f"Expected exactly two stored patches, found {stored!r}"
    assert stored[0].splitlines() == [
        "+ greeting=Hello 🌍",
        "+ key=val",
        "- old",
    ], f"Fixed patch was not normalized correctly in Redis: {stored[0]!r}"
    assert stored[1].splitlines() == [
        f"+ a_{nonce}=value-{nonce}",
        f"- temp_{nonce}",
        f"+ z_{nonce}=second",
    ], f"Dynamic patch was not normalized correctly in Redis: {stored[1]!r}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
