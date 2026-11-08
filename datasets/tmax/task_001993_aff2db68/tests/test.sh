#!/bin/bash
set +e
mkdir -p /logs/verifier
echo "0" > /logs/verifier/reward.txt

ORACLE_PATH="/app/token_oracle"
HIDDEN_ORACLE="/root/.token_oracle.verifier-hidden.$$"
WORKDIR="$(mktemp -d /tmp/policy-verifier.XXXXXX)"
ORACLE_MOVED=0

cleanup() {
    if [ "$ORACLE_MOVED" -eq 1 ] && [ -f "$HIDDEN_ORACLE" ]; then
        mv "$HIDDEN_ORACLE" "$ORACLE_PATH"
        chmod +x "$ORACLE_PATH"
    fi
    rm -rf "$WORKDIR"
}
trap cleanup EXIT

if [ ! -f "$ORACLE_PATH" ] || [ ! -f /home/user/policy_enforcer.py ]; then
    exit 0
fi

# Preserve the original seeded 1000-case oracle-equivalence assertion by
# recording the oracle's answers before making the oracle unavailable.
WORKDIR="$WORKDIR" ORACLE_PATH="$ORACLE_PATH" python3 - <<'PY'
import binascii
import itertools
import json
import os
import random
import string
import subprocess
import sys

ORACLE_PATH = os.environ["ORACLE_PATH"]
OUT_PATH = os.path.join(os.environ["WORKDIR"], "original_cases.json")
KEY = b"839201"

def encrypt_url(url):
    raw = url.encode("ascii")
    encrypted = bytes(b ^ k for b, k in zip(raw, itertools.cycle(KEY)))
    return binascii.hexlify(encrypted).decode("ascii")

def generate_random_cookie_padding():
    pad = ""
    for _ in range(random.randint(0, 3)):
        k = "".join(random.choices(string.ascii_lowercase, k=random.randint(3, 8)))
        v = "".join(random.choices(string.ascii_letters + string.digits,
                                   k=random.randint(5, 15)))
        pad += f"{k}={v}; "
    return pad

def generate_inputs(n=1000):
    random.seed(42)
    inputs = []
    for i in range(n):
        category = i % 10
        prefix = generate_random_cookie_padding()
        suffix = generate_random_cookie_padding()
        if category < 2:
            cookie = prefix + suffix
        elif category < 4:
            invalid_hex = "".join(random.choices("ghijklmnopqrstuvwxyz", k=10))
            cookie = f"{prefix}redirect_token={invalid_hex}; {suffix}"
        elif category < 7:
            path = "".join(random.choices(string.ascii_letters + string.digits + "/",
                                          k=random.randint(0, 20)))
            url = f"https://trusted.corp.local/{path}"
            cookie = f"{prefix}redirect_token={encrypt_url(url)}; {suffix}"
        else:
            domain = random.choice([
                "http://evil.com/",
                "https://trusted.corp.local.evil.com/",
                "https://other.local/",
                "http://trusted.corp.local/",
            ])
            path = "".join(random.choices(string.ascii_letters + string.digits + "/",
                                          k=random.randint(0, 20)))
            url = domain + path
            cookie = f"{prefix}redirect_token={encrypt_url(url)}; {suffix}"
        inputs.append(cookie)
    return inputs

cases = []
try:
    for index, cookie in enumerate(generate_inputs()):
        proc = subprocess.run([ORACLE_PATH, cookie], capture_output=True, text=True,
                              timeout=2)
        cases.append([cookie, proc.stdout.strip()])
except Exception as exc:
    print(f"Failed to record original oracle case {index}: {exc}", file=sys.stderr)
    sys.exit(1)

with open(OUT_PATH, "w", encoding="utf-8") as fh:
    json.dump(cases, fh)
PY
if [ $? -ne 0 ]; then
    exit 0
fi

# Every submitted program is run only after the supplied executable has been
# moved into a root-only location. A wrapper around /app/token_oracle therefore
# cannot satisfy either the retained corpus or the independently derived cases.
mv "$ORACLE_PATH" "$HIDDEN_ORACLE" || exit 0
chmod 700 "$HIDDEN_ORACLE"
ORACLE_MOVED=1

cp /home/user/policy_enforcer.py "$WORKDIR/policy_enforcer.py" || exit 0
chmod 0444 "$WORKDIR/policy_enforcer.py"
chown -R root:root "$WORKDIR"
chmod 0755 "$WORKDIR"

cat > "$WORKDIR/test_final_state.py" <<'PY'
import ast
import binascii
import itertools
import json
import os
import re
import secrets
import string
import subprocess

import pytest

AGENT_PATH = os.path.join(os.environ["WORKDIR"], "policy_enforcer.py")
CASES_PATH = os.path.join(os.environ["WORKDIR"], "original_cases.json")
KEY = b"839201"
TRUSTED = b"https://trusted.corp.local/"


def expected_output(cookie):
    match = re.search(r"redirect_token=([a-fA-F0-9]+)", cookie)
    if not match:
        return b"ERROR: Missing token\n"

    token = match.group(1)
    if len(token) % 2:
        return b"ERROR: Invalid hex\n"

    try:
        encrypted = binascii.unhexlify(token)
    except binascii.Error:
        return b"ERROR: Invalid hex\n"

    decrypted = bytes(b ^ k for b, k in zip(encrypted, itertools.cycle(KEY)))
    try:
        decrypted.decode("ascii")
    except UnicodeDecodeError:
        return b"DENY: Open Redirect\n"

    if decrypted.startswith(TRUSTED):
        return b"ALLOW: " + decrypted + b"\n"
    return b"DENY: Open Redirect\n"


def encrypt(raw):
    return bytes(b ^ k for b, k in zip(raw, itertools.cycle(KEY))).hex()


def run_agent(cookie=None):
    command = [
        "runuser", "-u", "user", "--", "env", "-i",
        "HOME=/tmp", "PATH=/usr/bin:/bin", "PYTHONDONTWRITEBYTECODE=1",
        "python3", AGENT_PATH,
    ]
    if cookie is not None:
        command.append(cookie)
    return subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                          timeout=3, cwd=os.environ["WORKDIR"])


def test_submission_is_a_standalone_python_program():
    assert os.path.isfile(AGENT_PATH)
    assert not os.path.islink(AGENT_PATH)
    assert os.path.getsize(AGENT_PATH) <= 262144, "Python submission is unexpectedly large"

    source = open(AGENT_PATH, "r", encoding="utf-8").read()
    tree = ast.parse(source, filename=AGENT_PATH)
    lowered = source.lower()
    assert "token_oracle" not in lowered
    assert "/app/" not in lowered

    forbidden_imports = {"subprocess", "ctypes", "pexpect"}
    forbidden_calls = {"system", "popen", "spawnl", "spawnle", "spawnlp",
                       "spawnlpe", "spawnv", "spawnve", "spawnvp", "spawnvpe",
                       "execl", "execle", "execlp", "execlpe", "execv",
                       "execve", "execvp", "execvpe"}
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            assert all(alias.name.split(".")[0] not in forbidden_imports
                       for alias in node.names)
        elif isinstance(node, ast.ImportFrom):
            assert (node.module or "").split(".")[0] not in forbidden_imports
        elif isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute):
            assert node.func.attr not in forbidden_calls


def test_original_seeded_fuzz_equivalence():
    with open(CASES_PATH, encoding="utf-8") as fh:
        cases = json.load(fh)
    assert len(cases) == 1000
    for index, (cookie, oracle_output) in enumerate(cases):
        proc = run_agent(cookie)
        assert proc.stdout.decode("utf-8").strip() == oracle_output, (
            f"Mismatch on original input {index}: {cookie!r}; "
            f"expected {oracle_output!r}, got {proc.stdout!r}"
        )


def test_no_argument_behavior():
    proc = run_agent()
    assert proc.stdout == b""


def test_independently_derived_edge_cases():
    trusted = TRUSTED
    edge_cases = [
        "",
        "Cookie: session=123;",
        "redirect_token=",
        "redirect_token=g1",
        "redirect_token=0",
        "redirect_token=abc",
        "redirect_token=00zzyy",
        "xredirect_token=00",
        "redirect_token=gg; redirect_token=00",
        "redirect_token=abcg; redirect_token=00",
        "redirect_token=" + encrypt(trusted),
        "Cookie: redirect_token=" + encrypt(trusted + b"path"),
        "redirect_token=" + encrypt(b"https://trusted.corp.local.evil/x"),
        "redirect_token=" + encrypt(b"https://trusted.corp.local"),
        "redirect_token=" + encrypt(b"http://trusted.corp.local/x"),
        "redirect_token=" + encrypt(bytes([0xff, 0x80, 0x00])),
        "redirect_token=" + encrypt(trusted + b"line\nnext"),
        "redirect_token=0; redirect_token=" + encrypt(trusted + b"later"),
        "Redirect_Token=" + encrypt(trusted),
        "prefix=\u2603; redirect_token=" + encrypt(trusted + b"unicode-cookie"),
    ]
    for cookie in edge_cases:
        proc = run_agent(cookie)
        assert proc.stdout == expected_output(cookie), (
            f"Edge-case mismatch for {cookie!r}: expected "
            f"{expected_output(cookie)!r}, got {proc.stdout!r}; stderr={proc.stderr!r}"
        )


def test_unseeded_independently_derived_cases():
    alphabet = string.ascii_letters + string.digits + "/._-"
    for index in range(500):
        category = index % 5
        prefix = secrets.token_hex(secrets.randbelow(12))
        suffix = secrets.token_hex(secrets.randbelow(12))

        if category == 0:
            cookie = f"a={prefix}; no_redirect={suffix}"
        elif category == 1:
            raw = secrets.token_bytes(1 + secrets.randbelow(96))
            cookie = f"p={prefix}; redirect_token={raw.hex()}; q={suffix}"
        elif category == 2:
            odd = secrets.token_hex(1 + secrets.randbelow(40)) + secrets.choice("0123456789abcdef")
            cookie = f"redirect_token={odd}; tail={suffix}"
        else:
            path = "".join(secrets.choice(alphabet) for _ in range(secrets.randbelow(80)))
            if category == 3:
                raw = TRUSTED + path.encode("ascii")
            else:
                base = secrets.choice([
                    b"http://evil.example/",
                    b"https://trusted.corp.local.evil/",
                    b"HTTPS://trusted.corp.local/",
                    b"https://other.local/",
                ])
                raw = base + path.encode("ascii")
            cookie = f"p={prefix}; redirect_token={encrypt(raw)}; q={suffix}"

        proc = run_agent(cookie)
        wanted = expected_output(cookie)
        assert proc.stdout == wanted, (
            f"Random mismatch for case {index}, cookie={cookie!r}: "
            f"expected {wanted!r}, got {proc.stdout!r}; stderr={proc.stderr!r}"
        )
PY

WORKDIR="$WORKDIR" python3 -m pytest "$WORKDIR/test_final_state.py" -x --tb=short 2>&1
if [ $? -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
fi

exit 0
