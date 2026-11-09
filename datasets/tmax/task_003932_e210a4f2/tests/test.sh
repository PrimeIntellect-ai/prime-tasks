#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import string
import subprocess

FILTER_BIN = "/home/user/filter"
FILTER_SRC = "/home/user/filter.c"
EXPECTED_OLD = "hunter two rotation"
HEX = string.hexdigits[:16]


def token(n=12):
    alphabet = string.ascii_letters + string.digits + "_-"
    return "".join(secrets.choice(alphabet) for _ in range(n))


def digest(mixed=False):
    value = secrets.token_hex(32)
    if mixed:
        value = "".join(c.upper() if c.isalpha() and secrets.randbelow(2) else c for c in value)
    return value


def request(path, old=EXPECTED_OLD, new=None, sha=None):
    if new is None:
        new = token(18)
    if sha is None:
        sha = digest()
    return (
        f"file_path: {path}\n"
        f"old_passphrase: {old}\n"
        f"new_passphrase: {new}\n"
        f"file_sha256: {sha}\n"
    ).encode()


def run_filter(body):
    return subprocess.run(
        [FILTER_BIN], input=body, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, timeout=2
    ).returncode


def assert_rejected(body, label):
    code = run_filter(body)
    assert code == 1, f"Rejected case {label!r} returned {code}, expected 1"


def test_filter_artifacts_exist_and_are_correct_kind():
    assert os.path.isfile(FILTER_SRC), f"C source not found at {FILTER_SRC}"
    assert os.path.isfile(FILTER_BIN), f"Filter binary not found at {FILTER_BIN}. Did you compile your code?"
    assert os.access(FILTER_BIN, os.X_OK), f"Filter binary at {FILTER_BIN} is not executable."
    with open(FILTER_BIN, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Compiled filter is not an ELF executable"


def test_generated_clean_requests_accepted():
    for i in range(24):
        directory = token(8)
        filename = token(10)
        # A single dot within a component is safe; only '..' is traversal.
        if i % 3 == 0:
            filename += ".v2"
        path = f"/srv/{directory}/{filename}.wav"
        code = run_filter(request(path, sha=digest(mixed=True)))
        assert code == 0, f"Generated clean request {i} returned {code}, expected 0"


def test_generated_unsafe_paths_rejected():
    nonce = token(10)
    unsafe_paths = {
        "semicolon": f"/srv/{nonce}.wav;id",
        "pipe": f"/srv/{nonce}.wav|id",
        "ampersand": f"/srv/{nonce}.wav&id",
        "dollar": f"/srv/${{PATH}}/{nonce}.wav",
        "parent traversal": f"/srv/{nonce}/../../etc/secret.wav",
        "embedded double dot": f"/srv/{nonce}..backup.wav",
        "wrong extension": f"/srv/{nonce}.mp3",
        "suffix after wav": f"/srv/{nonce}.wav.tmp",
    }
    for label, path in unsafe_paths.items():
        assert_rejected(request(path), label)


def test_generated_incorrect_old_passphrases_rejected():
    path = f"/var/lib/{token()}.wav"
    wrong_values = [
        EXPECTED_OLD + token(3),
        token(3) + EXPECTED_OLD,
        EXPECTED_OLD.upper(),
        "hunter  two rotation",
        token(20),
        "",
    ]
    for i, old in enumerate(wrong_values):
        assert_rejected(request(path, old=old), f"wrong old passphrase {i}")


def test_generated_invalid_hashes_rejected():
    path = f"/opt/audio/{token()}.wav"
    good = digest()
    bad_hashes = [
        good[:-1],
        good + secrets.choice(HEX),
        good[:secrets.randbelow(64)] + "g" + good[secrets.randbelow(64) + 1:],
        "",
        token(64),
    ]
    # Construct an unambiguously 64-character non-hex mutation as well.
    pos = secrets.randbelow(64)
    bad_hashes.append(good[:pos] + "Z" + good[pos + 1:])
    for i, sha in enumerate(bad_hashes):
        assert_rejected(request(path, sha=sha), f"invalid hash {i}")


def test_incomplete_or_malformed_requests_rejected():
    values = [
        f"file_path: /data/{token()}.wav",
        f"old_passphrase: {EXPECTED_OLD}",
        f"new_passphrase: {token()}",
        f"file_sha256: {digest()}",
    ]
    for missing in range(4):
        body = ("\n".join(v for i, v in enumerate(values) if i != missing) + "\n").encode()
        assert_rejected(body, f"missing field {missing}")

    malformed = values.copy()
    malformed[0] = f"path: /data/{token()}.wav"
    assert_rejected(("\n".join(malformed) + "\n").encode(), "wrong field name")
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
