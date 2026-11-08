#!/bin/bash
set +e
mkdir -p /logs/verifier

WORK=$(mktemp -d)
cp /home/user/certs/root.crt "$WORK/original-root.crt"
cp /home/user/certs/sub.crt "$WORK/original-sub.crt"
cp /home/user/certs/leaf.crt "$WORK/original-leaf.crt"

cleanup() {
    cp "$WORK/original-root.crt" /home/user/certs/root.crt 2>/dev/null || true
    cp "$WORK/original-sub.crt" /home/user/certs/sub.crt 2>/dev/null || true
    cp "$WORK/original-leaf.crt" /home/user/certs/leaf.crt 2>/dev/null || true
    if [ -f "$WORK/dynamic_filename" ]; then
        rm -f "/home/user/payloads/input/$(cat "$WORK/dynamic_filename")"
    fi
    rm -rf "$WORK"
}
trap cleanup EXIT

cat << 'TEST_EOF' > "$WORK/test_final_state.py"
import os
import json
import base64
import hmac
import hashlib
import pytest

def b64url_decode(s):
    s += '=' * (-len(s) % 4)
    return base64.urlsafe_b64decode(s.replace('-', '+').replace('_', '/'))

def verify_jwt(token, expected_user):
    parts = token.split('.')
    assert len(parts) == 3, f"JWT must have 3 parts, got {len(parts)}"
    header_b64, payload_b64, sig_b64 = parts

    try:
        header = json.loads(b64url_decode(header_b64))
    except Exception as e:
        pytest.fail(f"Failed to decode JWT header: {e}")

    assert header.get("alg") == "HS256", f"Expected alg HS256, got {header.get('alg')}"
    assert header.get("typ") == "JWT", f"Expected typ JWT, got {header.get('typ')}"

    try:
        payload = json.loads(b64url_decode(payload_b64))
    except Exception as e:
        pytest.fail(f"Failed to decode JWT payload: {e}")

    assert payload.get("user") == expected_user, f"Expected user {expected_user}, got {payload.get('user')}"
    assert payload.get("role") == "admin", f"Expected role admin, got {payload.get('role')}"
    assert payload.get("exp") == 1893456000, f"Expected exp 1893456000, got {payload.get('exp')}"

    msg = f"{header_b64}.{payload_b64}".encode('ascii')
    secret = b"SuperSecretRotationKey2024!"
    expected_sig = hmac.new(secret, msg, hashlib.sha256).digest()
    expected_sig_b64 = base64.urlsafe_b64encode(expected_sig).decode('ascii').rstrip('=')

    assert sig_b64 == expected_sig_b64, "JWT signature is invalid or does not match the expected secret"

def test_summary_log():
    summary_path = "/home/user/rotation_summary.txt"
    assert os.path.isfile(summary_path), f"Summary log {summary_path} does not exist."

    with open(summary_path, 'r') as f:
        content = f.read().strip()

    expected_content = "Successfully processed: 2 payloads"
    assert content == expected_content, f"Summary log content mismatch. Expected '{expected_content}', got '{content}'"

def test_output_payload_001():
    payload_path = "/home/user/payloads/output/payload_001.json"
    assert os.path.isfile(payload_path), f"Output payload {payload_path} does not exist."

    with open(payload_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"Output file {payload_path} is not valid JSON.")

    assert "id" in data, f"Output {payload_path} missing 'id' key."
    assert "data_b64" in data, f"Output {payload_path} missing 'data_b64' key."
    assert data["id"] == "payload_001", "ID mismatch in payload_001.json"

    try:
        inner_json_str = base64.b64decode(data["data_b64"]).decode('utf-8')
        inner_data = json.loads(inner_json_str)
    except Exception as e:
        pytest.fail(f"Failed to decode and parse inner JSON from data_b64: {e}")

    assert inner_data.get("ssn") == "XXX-XX-XXXX", f"SSN not properly redacted. Got: {inner_data.get('ssn')}"
    assert "old_token" in inner_data, "Missing 'old_token' in inner JSON"

    verify_jwt(inner_data["old_token"], "Alice")

def test_output_payload_002():
    payload_path = "/home/user/payloads/output/payload_002.json"
    assert os.path.isfile(payload_path), f"Output payload {payload_path} does not exist."

    with open(payload_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"Output file {payload_path} is not valid JSON.")

    assert "id" in data, f"Output {payload_path} missing 'id' key."
    assert "data_b64" in data, f"Output {payload_path} missing 'data_b64' key."
    assert data["id"] == "payload_002", "ID mismatch in payload_002.json"

    try:
        inner_json_str = base64.b64decode(data["data_b64"]).decode('utf-8')
        inner_data = json.loads(inner_json_str)
    except Exception as e:
        pytest.fail(f"Failed to decode and parse inner JSON from data_b64: {e}")

    assert inner_data.get("ssn") == "XXX-XX-XXXX", f"SSN not properly redacted. Got: {inner_data.get('ssn')}"
    assert "old_token" in inner_data, "Missing 'old_token' in inner JSON"

    verify_jwt(inner_data["old_token"], "Bob")
TEST_EOF

cat << 'DYNAMIC_EOF' > "$WORK/check_dynamic.py"
import base64
import hashlib
import hmac
import json
import os
import sys

metadata_path, output_dir, summary_path = sys.argv[1:]
with open(metadata_path, "r", encoding="utf-8") as f:
    expected = json.load(f)

expected_names = {"payload_001.json", "payload_002.json", expected["filename"]}
actual_names = {name for name in os.listdir(output_dir) if name.endswith(".json")}
assert actual_names == expected_names, (actual_names, expected_names)

with open(summary_path, "r", encoding="utf-8") as f:
    assert f.read().strip() == "Successfully processed: 3 payloads"

path = os.path.join(output_dir, expected["filename"])
with open(path, "r", encoding="utf-8") as f:
    outer = json.load(f)
assert outer.get("id") == expected["id"]
assert "data_b64" in outer
inner = json.loads(base64.b64decode(outer["data_b64"], validate=True).decode("utf-8"))
assert inner.get("user") == expected["user"]
assert inner.get("ssn") == expected["redacted_ssn"]
assert "old_token" in inner

parts = inner["old_token"].split(".")
assert len(parts) == 3

def decode_url(part):
    return base64.urlsafe_b64decode(part + "=" * (-len(part) % 4))

header = json.loads(decode_url(parts[0]))
payload = json.loads(decode_url(parts[1]))
assert header.get("alg") == "HS256"
assert header.get("typ") == "JWT"
assert payload.get("user") == expected["user"]
assert payload.get("role") == "admin"
assert payload.get("exp") == 1893456000
message = (parts[0] + "." + parts[1]).encode("ascii")
signature = hmac.new(b"SuperSecretRotationKey2024!", message, hashlib.sha256).digest()
assert hmac.compare_digest(decode_url(parts[2]), signature)
DYNAMIC_EOF

run_tests() {
    if [ ! -f /home/user/rotator/main.go ]; then
        echo "Missing /home/user/rotator/main.go"
        return 1
    fi

    (cd /home/user/rotator && go build -o "$WORK/rotator_submission" .) || return 1
    [ -x "$WORK/rotator_submission" ] || return 1

    rm -f /home/user/payloads/output/* /home/user/rotation_summary.txt
    (cd /home/user/rotator && "$WORK/rotator_submission") || return 1
    python3 -m pytest "$WORK/test_final_state.py" -x --tb=short || return 1

    python3 - "$WORK/dynamic.json" "$WORK/dynamic_filename" << 'PY_EOF' || return 1
import base64
import json
import secrets
import sys

metadata_path, filename_path = sys.argv[1:]
tag = secrets.token_hex(12)
filename = "challenge_" + tag + ".json"
metadata = {
    "filename": filename,
    "id": "id_" + tag,
    "user": "User_" + tag,
    "redacted_ssn": "XXX-XX-XXXX",
}
inner = {
    "user": metadata["user"],
    "ssn": "314-15-9265",
    "old_token": "untrusted." + tag + ".token",
}
outer = {
    "id": metadata["id"],
    "data_b64": base64.b64encode(json.dumps(inner, separators=(",", ":")).encode()).decode(),
}
with open("/home/user/payloads/input/" + filename, "w", encoding="utf-8") as f:
    json.dump(outer, f, separators=(",", ":"))
with open(metadata_path, "w", encoding="utf-8") as f:
    json.dump(metadata, f)
with open(filename_path, "w", encoding="utf-8") as f:
    f.write(filename)
PY_EOF

    rm -f /home/user/payloads/output/* /home/user/rotation_summary.txt
    (cd /home/user/rotator && "$WORK/rotator_submission") || return 1
    python3 "$WORK/check_dynamic.py" "$WORK/dynamic.json" /home/user/payloads/output /home/user/rotation_summary.txt || return 1

    mkdir -p "$WORK/newcerts"
    openssl req -x509 -newkey rsa:2048 -nodes -days 2 \
        -keyout "$WORK/newcerts/root.key" -out "$WORK/newcerts/root.crt" \
        -subj "/C=US/O=Verifier/CN=DynamicRoot" \
        -addext "basicConstraints=critical,CA:TRUE" \
        -addext "keyUsage=critical,keyCertSign,cRLSign" >/dev/null 2>&1 || return 1
    openssl req -newkey rsa:2048 -nodes \
        -keyout "$WORK/newcerts/sub.key" -out "$WORK/newcerts/sub.csr" \
        -subj "/C=US/O=Verifier/CN=DynamicSub" >/dev/null 2>&1 || return 1
    cat > "$WORK/newcerts/sub.ext" << 'EOF'
basicConstraints=critical,CA:TRUE
keyUsage=critical,keyCertSign,cRLSign
subjectKeyIdentifier=hash
authorityKeyIdentifier=keyid,issuer
EOF
    openssl x509 -req -in "$WORK/newcerts/sub.csr" \
        -CA "$WORK/newcerts/root.crt" -CAkey "$WORK/newcerts/root.key" -CAcreateserial \
        -out "$WORK/newcerts/sub.crt" -days 2 -extfile "$WORK/newcerts/sub.ext" >/dev/null 2>&1 || return 1
    openssl req -newkey rsa:2048 -nodes \
        -keyout "$WORK/newcerts/leaf.key" -out "$WORK/newcerts/leaf.csr" \
        -subj "/C=US/O=Verifier/CN=DynamicLeaf" >/dev/null 2>&1 || return 1
    cat > "$WORK/newcerts/leaf.ext" << 'EOF'
basicConstraints=critical,CA:FALSE
keyUsage=critical,digitalSignature,keyEncipherment
subjectKeyIdentifier=hash
authorityKeyIdentifier=keyid,issuer
EOF
    openssl x509 -req -in "$WORK/newcerts/leaf.csr" \
        -CA "$WORK/newcerts/sub.crt" -CAkey "$WORK/newcerts/sub.key" -CAcreateserial \
        -out "$WORK/newcerts/leaf.crt" -days 2 -extfile "$WORK/newcerts/leaf.ext" >/dev/null 2>&1 || return 1

    cp "$WORK/newcerts/root.crt" /home/user/certs/root.crt || return 1
    cp "$WORK/newcerts/sub.crt" /home/user/certs/sub.crt || return 1
    cp "$WORK/newcerts/leaf.crt" /home/user/certs/leaf.crt || return 1

    rm -f /home/user/payloads/output/* /home/user/rotation_summary.txt
    (cd /home/user/rotator && "$WORK/rotator_submission") || return 1
    python3 "$WORK/check_dynamic.py" "$WORK/dynamic.json" /home/user/payloads/output /home/user/rotation_summary.txt || return 1

    openssl req -x509 -newkey rsa:2048 -nodes -days 2 \
        -keyout "$WORK/newcerts/rogue.key" -out "$WORK/newcerts/rogue.crt" \
        -subj "/C=US/O=Verifier/CN=RogueRoot" \
        -addext "basicConstraints=critical,CA:TRUE" \
        -addext "keyUsage=critical,keyCertSign,cRLSign" >/dev/null 2>&1 || return 1
    openssl x509 -req -in "$WORK/newcerts/leaf.csr" \
        -CA "$WORK/newcerts/rogue.crt" -CAkey "$WORK/newcerts/rogue.key" -CAcreateserial \
        -out "$WORK/newcerts/bad-leaf.crt" -days 2 -extfile "$WORK/newcerts/leaf.ext" >/dev/null 2>&1 || return 1
    cp "$WORK/newcerts/bad-leaf.crt" /home/user/certs/leaf.crt || return 1

    invalid_output=$(cd /home/user/rotator && "$WORK/rotator_submission" 2>&1)
    invalid_status=$?
    if [ "$invalid_status" -eq 0 ]; then
        echo "Program accepted an invalid certificate chain"
        return 1
    fi
    if [ -z "$invalid_output" ]; then
        echo "Program did not print an error for an invalid certificate chain"
        return 1
    fi

    return 0
}

if run_tests; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
