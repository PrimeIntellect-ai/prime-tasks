#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import stat
import secrets
import string
import subprocess

CONFIG = "/app/auth_config.env"
HANDLER = "/app/upload_processor.sh"
UPLOAD_DIR = "/app/safe_uploads"


def read_token():
    with open(CONFIG, "r", encoding="utf-8") as f:
        content = f.read()
    token = None
    for line in content.splitlines():
        if line.startswith("ADMIN_TOKEN="):
            token = line.split("=", 1)[1].strip()
            break
    return token


def snapshot_tree(root):
    result = {}
    for current, dirs, files in os.walk(root, topdown=True, followlinks=False):
        for name in dirs + files:
            path = os.path.join(current, name)
            rel = os.path.relpath(path, root)
            st = os.lstat(path)
            kind = stat.S_IFMT(st.st_mode)
            data = None
            if stat.S_ISREG(st.st_mode):
                with open(path, "rb") as f:
                    data = f.read()
            elif stat.S_ISLNK(st.st_mode):
                data = os.readlink(path)
            result[rel] = (kind, stat.S_IMODE(st.st_mode), data)
    return result


def request(headers, body=b"", ending=b"\r\n"):
    return ending.join(h.encode("utf-8") for h in headers) + ending + ending + body


def run_case(payload, status, exit_code, expected_name=None, expected_body=None,
             forbidden_paths=()):
    expected_path = os.path.join(UPLOAD_DIR, expected_name) if expected_name else None
    if expected_path and os.path.lexists(expected_path):
        if os.path.isdir(expected_path) and not os.path.islink(expected_path):
            raise AssertionError(f"Unexpected pre-existing directory: {expected_path}")
        os.unlink(expected_path)

    for path in forbidden_paths:
        assert not os.path.lexists(path), f"Test sentinel unexpectedly exists: {path}"

    before_uploads = snapshot_tree(UPLOAD_DIR)
    config_before = (open(CONFIG, "rb").read(), stat.S_IMODE(os.stat(CONFIG).st_mode))

    proc = subprocess.run(
        [HANDLER],
        input=payload,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        cwd="/app",
        timeout=10,
    )

    allowed_stdout = {status.encode("ascii"), status.encode("ascii") + b"\n"}
    assert proc.returncode == exit_code, (
        f"For {status}, exit code was {proc.returncode}, expected {exit_code}; "
        f"stdout={proc.stdout!r}, stderr={proc.stderr!r}"
    )
    assert proc.stdout in allowed_stdout, (
        f"Output was not exactly {status!r}: {proc.stdout!r}"
    )
    assert proc.stderr == b"", f"Unexpected stderr: {proc.stderr!r}"

    config_after = (open(CONFIG, "rb").read(), stat.S_IMODE(os.stat(CONFIG).st_mode))
    assert config_after == config_before, "The handler modified auth_config.env"

    for path in forbidden_paths:
        assert not os.path.lexists(path), f"Unauthorized path was written: {path}"

    if expected_name is None:
        assert snapshot_tree(UPLOAD_DIR) == before_uploads, (
            "A rejected request modified /app/safe_uploads"
        )
        return

    assert os.path.lexists(expected_path), f"Expected upload is missing: {expected_path}"
    st = os.lstat(expected_path)
    assert stat.S_ISREG(st.st_mode), f"Upload is not a regular file: {expected_path}"
    assert stat.S_IMODE(st.st_mode) == 0o600, (
        f"Permissions for {expected_path} are {oct(stat.S_IMODE(st.st_mode))}, expected 0o600"
    )
    with open(expected_path, "rb") as f:
        actual_body = f.read()
    assert actual_body == expected_body, (
        f"Body mismatch for {expected_path}: {actual_body!r} != {expected_body!r}"
    )

    os.unlink(expected_path)
    assert snapshot_tree(UPLOAD_DIR) == before_uploads, (
        "A successful request made writes other than its expected upload"
    )


def random_name(suffix=".wav"):
    alphabet = string.ascii_lowercase + string.digits
    return "verify_" + "".join(secrets.choice(alphabet) for _ in range(18)) + suffix


def test_auth_config_rotated_and_secured():
    path = CONFIG
    assert os.path.exists(path), f"File {path} is missing."

    mode = os.stat(path).st_mode
    perms = stat.S_IMODE(mode)
    assert perms == 0o600, f"Permissions for {path} are {oct(perms)}, expected 0o600."

    with open(path, "r", encoding="utf-8") as f:
        content = f.read()

    token = None
    for line in content.splitlines():
        if line.startswith("ADMIN_TOKEN="):
            token = line.split("=", 1)[1].strip()
            break

    assert token is not None, f"ADMIN_TOKEN not found in {path}"
    assert token != "dex972", "ADMIN_TOKEN was not rotated from the leaked value 'dex972'."
    assert len(token) >= 32, f"ADMIN_TOKEN is too short (length {len(token)}), expected at least 32 characters."
    assert re.match(r"^[0-9a-fA-F]+$", token), "ADMIN_TOKEN is not a valid hex string."
    assert len(token) == 32, f"ADMIN_TOKEN must be exactly 32 characters, got {len(token)}."
    assert re.fullmatch(r"[0-9a-fA-F]{32}", token), "ADMIN_TOKEN is not a 32-character hex string."


def test_upload_processor_metric():
    assert os.path.exists(HANDLER), f"File {HANDLER} is missing"
    st = os.lstat(HANDLER)
    assert stat.S_ISREG(st.st_mode), f"{HANDLER} must be a regular file"
    assert os.access(HANDLER, os.X_OK), f"{HANDLER} is not executable"
    with open(HANDLER, "rb") as f:
        first_line = f.readline(256).decode("utf-8", "replace")
    assert first_line.startswith("#!") and "bash" in first_line, (
        "upload_processor.sh must be a Bash script"
    )

    token = read_token()
    assert token is not None

    # Valid uploads with both supported line endings, varied header order,
    # unpredictable names, nested paths, spaces, and nontrivial bodies.
    valid_cases = []
    for i in range(12):
        name = random_name()
        body_alphabet = string.ascii_letters + string.digits + " !@#$%^&*()[]{};:\\r\\n"
        body = "".join(secrets.choice(body_alphabet) for _ in range(80 + i)).encode("utf-8")
        if i == 0:
            body = b"BODY"
        elif i == 1:
            body = b""
        elif i == 2:
            body = b"first line\r\n\r\nAuthorization: Bearer fake\nlast line\n"

        supplied = name
        if i % 4 == 1:
            supplied = "incoming/subdir/" + name
        elif i % 4 == 2:
            supplied = "../../../tmp/" + name
        elif i % 4 == 3:
            supplied = "/var/tmp//nested/../" + name

        headers = [f"Authorization: Bearer {token}", f"X-Upload-Filename: {supplied}"]
        if i % 3 == 0:
            headers = ["X-Ignored: arbitrary", headers[1], headers[0]]
        ending = b"\n" if i % 2 else b"\r\n"
        forbidden = []
        if supplied.startswith("../../../tmp/"):
            forbidden.append(os.path.join("/tmp", name))
        valid_cases.append((request(headers, body, ending), name, body, forbidden))

    # Literal filenames that commonly expose unsafe splitting or expansion.
    special_names = [
        random_name().replace("verify_", "clip name_", 1),
        "semi;" + random_name(),
        "..\\..\\" + random_name(),
        "%2e%2e%2f" + random_name(),
        ".wav",
    ]
    for name in special_names:
        body = ("special-body-" + secrets.token_hex(12)).encode("ascii")
        valid_cases.append((
            request([f"X-Upload-Filename: {name}", f"Authorization: Bearer {token}"], body),
            name,
            body,
            [],
        ))

    for payload, name, body, forbidden in valid_cases:
        run_case(payload, "HTTP/1.1 200 OK", 0, name, body, forbidden)

    # Authentication must be exact and must be checked before filename handling.
    auth_failures = [
        [],
        ["Authorization: Bearer BADTOKEN"],
        [f"Authorization: Bearer {token}extra"],
        [f"Authorization: Bearer prefix{token}"],
        [f"Authorization: Basic {token}"],
        [f"Authorization: bearer {token}"],
        ["Authorization: Bearer"],
        ["Authorization:"],
    ]
    for auth_headers in auth_failures:
        name = random_name()
        headers = auth_headers + [f"X-Upload-Filename: {name}"]
        run_case(request(headers, b"must-not-be-written"),
                 "HTTP/1.1 401 Unauthorized", 1)

    # Invalid authentication must not permit traversal outside the upload area.
    outside_name = random_name()
    outside_path = os.path.join("/tmp", outside_name)
    run_case(
        request([
            "Authorization: Bearer invalid",
            f"X-Upload-Filename: ../../../tmp/{outside_name}",
        ], b"unauthorized"),
        "HTTP/1.1 401 Unauthorized",
        1,
        forbidden_paths=[outside_path],
    )

    # Empty or missing filenames are bad requests and create no files.
    run_case(request([f"Authorization: Bearer {token}"], b"body"),
             "HTTP/1.1 400 Bad Request", 1)
    run_case(request([f"Authorization: Bearer {token}", "X-Upload-Filename:"], b"body"),
             "HTTP/1.1 400 Bad Request", 1)
    run_case(request([f"Authorization: Bearer {token}", "X-Upload-Filename: "], b"body", b"\n"),
             "HTTP/1.1 400 Bad Request", 1)

    # The whitelist is a strict, case-sensitive .wav suffix check.
    bad_suffixes = [".txt", ".WAV", ".wave", ".wav.txt", ".wav/extra", "wav", ".mp3"]
    for suffix in bad_suffixes:
        name = random_name("") + suffix
        run_case(
            request([f"Authorization: Bearer {token}", f"X-Upload-Filename: {name}"], b"reject"),
            "HTTP/1.1 403 Forbidden",
            1,
        )

    # Additional randomized accepted and rejected requests prevent fixed-fixture handlers.
    for _ in range(15):
        name = random_name()
        body = secrets.token_bytes(96).replace(b"\x00", b"X")
        run_case(
            request([f"Authorization: Bearer {token}", f"X-Upload-Filename: a/b/c/{name}"], body,
                    secrets.choice([b"\n", b"\r\n"])),
            "HTTP/1.1 200 OK", 0, name, body,
        )

        rejected = random_name(secrets.choice([".ogg", ".WAV", ".wav.bak", ".txt"]))
        run_case(
            request([f"Authorization: Bearer {token}", f"X-Upload-Filename: {rejected}"], b"nope"),
            "HTTP/1.1 403 Forbidden", 1,
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
