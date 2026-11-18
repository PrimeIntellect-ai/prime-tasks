#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import subprocess
import json
import base64
import hmac
import hashlib

ORACLE_PATH = "/tests/jwt_oracle"
AGENT_SCRIPT = "/home/user/verify.sh"
SECRET_KEY = b"b4sh_s3cr3t_99"
RNG = random.SystemRandom()

def b64url_encode(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")

def create_jwt(header: dict, payload: dict, secret: bytes = None, sign: bool = True) -> str:
    header_enc = b64url_encode(json.dumps(header, separators=(",", ":")).encode("utf-8"))
    payload_enc = b64url_encode(json.dumps(payload, separators=(",", ":")).encode("utf-8"))
    msg = f"{header_enc}.{payload_enc}"

    if not sign:
        return f"{msg}."

    if secret is None:
        secret = SECRET_KEY

    sig = hmac.new(secret, msg.encode("utf-8"), hashlib.sha256).digest()
    return f"{msg}.{b64url_encode(sig)}"

def random_payload() -> dict:
    return {
        "user": secrets.token_urlsafe(RNG.randint(1, 30)),
        "role": RNG.choice(["admin", "user", "auditor", "guest"]),
        "nonce": secrets.token_hex(RNG.randint(1, 24)),
        "counter": RNG.randrange(0, 2**40),
        "enabled": RNG.choice([True, False]),
    }

def random_valid_header() -> dict:
    header = {
        "alg": RNG.choice(["HS256", "hs256", "Hs256", "hS256"]),
        "typ": RNG.choice(["JWT", "jwt", "custom"]),
        "kid": secrets.token_urlsafe(RNG.randint(1, 16)),
    }
    items = list(header.items())
    RNG.shuffle(items)
    return dict(items)

def generate_test_cases(n=500):
    cases = []

    while len(cases) < n:
        payload = random_payload()

        # Valid JWT with fresh randomized header, payload, and signature input.
        cases.append(create_jwt(random_valid_header(), payload, secret=SECRET_KEY))

        # Unsupported and alg:none variants.
        bad_alg = RNG.choice(["none", "NONE", "nOnE", "NoNe", "HS512", "RS256", "", " HS256"])
        cases.append(create_jwt({"alg": bad_alg, "typ": "JWT", "x": secrets.token_hex(4)}, payload, sign=False))

        # Correctly formed HS256 token signed with a fresh incorrect key.
        bad_key = secrets.token_bytes(RNG.randint(1, 48))
        if bad_key == SECRET_KEY:
            bad_key += b"x"
        cases.append(create_jwt(random_valid_header(), payload, secret=bad_key))

        # Fresh malformed or corrupted input.
        valid = create_jwt(random_valid_header(), payload)
        malformed = RNG.choice([
            "just.two.parts.wait.four",
            "not.even.base64!",
            "",
            "$(echo bad)",
            "`rm -rf /`",
            valid + secrets.token_urlsafe(RNG.randint(1, 8)),
            valid.rsplit(".", 1)[0] + "." + secrets.token_urlsafe(RNG.randint(1, 24)),
            ".".join([secrets.token_urlsafe(5) for _ in range(RNG.choice([1, 2, 4, 5]))]),
            "...",
        ])
        cases.append(malformed)

    cases = cases[:n]
    RNG.shuffle(cases)
    return cases

def run_cmd(cmd, arg):
    try:
        result = subprocess.run([cmd, arg], capture_output=True, text=True, timeout=2)
        return result.stdout.strip(), result.returncode
    except subprocess.TimeoutExpired:
        return "TIMEOUT", -1
    except Exception as exc:
        return str(exc), -2

def run_argv(cmd, args):
    try:
        result = subprocess.run([cmd] + args, capture_output=True, text=True, timeout=2)
        return result.stdout.strip(), result.returncode
    except subprocess.TimeoutExpired:
        return "TIMEOUT", -1
    except Exception as exc:
        return str(exc), -2

def test_script_exists_and_executable():
    assert os.path.exists(AGENT_SCRIPT), f"Agent script {AGENT_SCRIPT} does not exist."
    assert os.path.isfile(AGENT_SCRIPT), f"Agent script {AGENT_SCRIPT} is not a regular file."
    assert os.access(AGENT_SCRIPT, os.X_OK), f"Agent script {AGENT_SCRIPT} is not executable."
    with open(AGENT_SCRIPT, "rb") as handle:
        first_line = handle.readline().lower()
    assert first_line.startswith(b"#!") and b"bash" in first_line, "Agent implementation must be a Bash script."

def test_not_reference_copy():
    assert os.path.exists(ORACLE_PATH), f"Oracle missing at {ORACLE_PATH}"
    with open(AGENT_SCRIPT, "rb") as agent, open(ORACLE_PATH, "rb") as oracle:
        assert agent.read() != oracle.read(), "Agent script must not be a byte-identical copy of the reference."

def test_argument_count():
    for args in ([], ["a", "b"]):
        oracle_out, oracle_code = run_argv(ORACLE_PATH, args)
        agent_out, agent_code = run_argv(AGENT_SCRIPT, args)
        assert agent_code == oracle_code
        assert agent_out == oracle_out

def test_fuzz_equivalence():
    assert os.path.exists(ORACLE_PATH), f"Oracle missing at {ORACLE_PATH}"

    test_cases = generate_test_cases(500)

    for i, case in enumerate(test_cases):
        oracle_out, oracle_code = run_cmd(ORACLE_PATH, case)
        agent_out, agent_code = run_cmd(AGENT_SCRIPT, case)

        assert agent_code == oracle_code, (
            f"Exit code mismatch on input {i}:\n"
            f"Input: {case}\n"
            f"Oracle code: {oracle_code}\n"
            f"Agent code: {agent_code}\n"
            f"Oracle out: {oracle_out}\n"
            f"Agent out: {agent_out}"
        )

        assert agent_out == oracle_out, (
            f"Stdout mismatch on input {i}:\n"
            f"Input: {case}\n"
            f"Oracle out: {oracle_out}\n"
            f"Agent out: {agent_out}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
