#!/bin/bash
set -e
mkdir -p /logs/verifier

ORIGINAL_SIGNER="$(mktemp /tmp/metadata_signer.original.XXXXXX)"
WRAPPER_TMP="$(mktemp /tmp/metadata_signer.wrapper.XXXXXX)"
SIGNER_CALLS="$(mktemp /tmp/metadata_signer.calls.XXXXXX)"
SIGNER_CHALLENGE="$(mktemp /tmp/metadata_signer.challenge.XXXXXX)"

cp /app/metadata_signer "$ORIGINAL_SIGNER"
chmod 666 "$SIGNER_CALLS"
chmod 644 "$SIGNER_CHALLENGE"

cat > "$WRAPPER_TMP" <<EOF
#!/usr/bin/python3
import base64
import sys

data = sys.stdin.buffer.read()
with open("$SIGNER_CALLS", "ab") as f:
    f.write(base64.b64encode(data) + b"\\n")
with open("$SIGNER_CHALLENGE", "r", encoding="ascii") as f:
    challenge = f.read().strip()
sys.stdout.write(challenge + "\\n")
EOF
chmod 755 "$WRAPPER_TMP"
cp "$WRAPPER_TMP" /app/metadata_signer
chmod 755 /app/metadata_signer

restore_signer() {
    cp "$ORIGINAL_SIGNER" /app/metadata_signer
    chmod 755 /app/metadata_signer
    rm -f "$ORIGINAL_SIGNER" "$WRAPPER_TMP" "$SIGNER_CALLS" "$SIGNER_CHALLENGE"
}
trap restore_signer EXIT

export SIGNER_CALLS SIGNER_CHALLENGE

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import io
import json
import os
import secrets
import uuid
import zipfile

import pytest
import requests

SERVICE_URL = "http://127.0.0.1:8080/upload_project"
CALLS_FILE = os.environ["SIGNER_CALLS"]
CHALLENGE_FILE = os.environ["SIGNER_CHALLENGE"]


def signer_calls():
    with open(CALLS_FILE, "rb") as f:
        return [base64.b64decode(line) for line in f.read().splitlines() if line]


def set_challenge():
    challenge = secrets.token_hex(32) + "-signed"
    with open(CHALLENGE_FILE, "w", encoding="ascii") as f:
        f.write(challenge)
    return challenge


def make_zip(entries):
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", compression=zipfile.ZIP_DEFLATED) as zf:
        for name, content in entries:
            zf.writestr(name, content)
    return buf.getvalue()


def post_archive(data):
    try:
        return requests.post(
            SERVICE_URL,
            data=data,
            headers={"Content-Type": "application/zip"},
            timeout=5,
        )
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect to service at {SERVICE_URL}: {exc}")


@pytest.mark.parametrize("index", range(3))
def test_randomized_valid_archives_are_decoded_and_signed(index):
    token = uuid.uuid4().hex
    names = ["café", "naïve", "édition"]
    manifest = {
        "project_name": f"{names[index]}_{token}",
        "id": secrets.randbelow(2_000_000_000) + 1,
        "description": f"Legacy £ data — {token}",
        "settings": {"revision": index, "enabled": bool(index % 2)},
    }
    legacy_json = json.dumps(manifest, ensure_ascii=False, indent=index + 1)
    archive = make_zip([
        ("manifest.json", legacy_json.encode("windows-1252")),
        (f"assets/{token}.bin", secrets.token_bytes(31 + index)),
    ])

    challenge = set_challenge()
    before = signer_calls()
    response = post_archive(archive)
    after = signer_calls()

    assert response.status_code == 200, response.text
    try:
        body = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON: {response.text}")

    assert set(body) == {"manifest", "signature"}
    assert body["manifest"] == manifest
    assert body["signature"] == challenge

    new_calls = after[len(before):]
    assert new_calls, "The service did not invoke /app/metadata_signer"
    for raw_input in new_calls:
        try:
            decoded = raw_input.decode("utf-8")
        except UnicodeDecodeError as exc:
            pytest.fail(f"Signer input was not UTF-8: {exc}")
        try:
            signed_manifest = json.loads(decoded)
        except ValueError as exc:
            pytest.fail(f"Signer input was not a JSON string: {exc}")
        assert signed_manifest == manifest, "Signer received the wrong manifest"


@pytest.mark.parametrize("member_name", [
    "../../../../tmp/{name}",
    "/tmp/{name}",
])
def test_randomized_zip_slip_is_rejected_without_extraction(member_name):
    probe_name = f"zip_slip_{uuid.uuid4().hex}.txt"
    target = f"/tmp/{probe_name}"
    path = member_name.format(name=probe_name)
    archive = make_zip([
        ("manifest.json", b'{"project_name":"must_not_process","id":1}'),
        ("ordinary.txt", b"must not be extracted"),
        (path, b"pwned"),
    ])
    if os.path.exists(target):
        os.remove(target)

    before = signer_calls()
    response = post_archive(archive)
    after = signer_calls()

    assert response.status_code == 400, response.text
    try:
        body = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON: {response.text}")
    assert body == {"error": "Invalid archive"}
    assert not os.path.exists(target), f"Zip Slip wrote {target}"
    assert after == before, "The signer was invoked for an unsafe archive"


def test_randomized_invalid_zip_is_rejected():
    invalid_data = b"not-a-zip-" + secrets.token_bytes(97)
    before = signer_calls()
    response = post_archive(invalid_data)
    after = signer_calls()

    assert response.status_code == 400, response.text
    assert after == before, "The signer was invoked for an invalid ZIP"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
