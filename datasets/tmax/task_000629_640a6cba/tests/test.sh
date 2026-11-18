#!/bin/bash
set +e
mkdir -p /logs/verifier
ok=1
workdir=$(mktemp -d)
cp /home/user/config_snapshot.dat "$workdir/original_snapshot.dat" || ok=0

restore_snapshot() {
    if [ -f "$workdir/original_snapshot.dat" ]; then
        cp "$workdir/original_snapshot.dat" /home/user/config_snapshot.dat
    fi
    rm -rf "$workdir"
}
trap restore_snapshot EXIT

if [ ! -f /home/user/parser.c ] || [ ! -s /home/user/parser.c ]; then
    echo "Missing or empty /home/user/parser.c"
    ok=0
fi

if [ "$ok" -eq 1 ]; then
    rm -f /home/user/parser
    gcc /home/user/parser.c -o /home/user/parser -lz -lcrypto
    if [ $? -ne 0 ] || [ ! -x /home/user/parser ]; then
        echo "parser.c did not compile into an executable"
        ok=0
    fi
fi

# Replace the snapshot temporarily with a randomized valid snapshot. This checks
# that the compiled C artifact reads the header, decompresses the payload, and
# derives its output instead of merely writing the known final answer.
if [ "$ok" -eq 1 ]; then
    python3 - "$workdir/expected_dynamic.json" <<'PY'
import gzip
import json
import secrets
import struct
import sys

expected_path = sys.argv[1]
timestamp = secrets.randbelow(1_000_000_000) + 2_000_000_000
network = {
    "IPAddress": "172.31." + str(secrets.randbelow(200) + 1) + "." + str(secrets.randbelow(200) + 1),
    "Port": str(secrets.randbelow(50000) + 10000),
    "Gateway": "gw-" + secrets.token_hex(6),
    "Protocol": "PROTO-" + secrets.token_hex(4),
}
security = {
    "EnableSSL": "flag-" + secrets.token_hex(4),
    "CertPath": "/tmp/cert-" + secrets.token_hex(6) + ".crt",
    "MaxConnections": str(secrets.randbelow(900) + 100),
}
payload = f'''[General]
Decoy={secrets.token_hex(8)}

[Network]
IPAddress={network["IPAddress"]}
Port={network["Port"]}
Gateway={network["Gateway"]}
Protocol={network["Protocol"]}

[Database]
Password={secrets.token_hex(10)}

[Security]
EnableSSL={security["EnableSSL"]}
CertPath={security["CertPath"]}
MaxConnections={security["MaxConnections"]}

[Ignored]
Extra={secrets.token_hex(8)}
'''.encode()
compressed = gzip.compress(payload)
with open('/home/user/config_snapshot.dat', 'wb') as f:
    f.write(struct.pack('<4sIII', b'CFGS', timestamp, len(compressed), len(payload)))
    f.write(compressed)
with open(expected_path, 'w') as f:
    json.dump({"timestamp": timestamp, "data": {"Network": network, "Security": security}}, f)
PY
    if [ $? -ne 0 ]; then
        ok=0
    fi
fi

if [ "$ok" -eq 1 ]; then
    rm -f /home/user/parsed_config.json /home/user/manifest.txt
    (cd /home/user && timeout 20s ./parser)
    if [ $? -ne 0 ]; then
        echo "Compiled parser failed on a valid randomized snapshot"
        ok=0
    fi
fi

if [ "$ok" -eq 1 ]; then
    python3 - "$workdir/expected_dynamic.json" <<'PY'
import hashlib
import json
import os
import sys

with open(sys.argv[1]) as f:
    expected = json.load(f)
json_path = '/home/user/parsed_config.json'
manifest_path = '/home/user/manifest.txt'
assert os.path.isfile(json_path), 'Parser did not create parsed_config.json'
assert os.path.isfile(manifest_path), 'Parser did not create manifest.txt'
with open(json_path, 'rb') as f:
    json_bytes = f.read()
try:
    actual = json.loads(json_bytes)
except Exception as e:
    raise AssertionError(f'Randomized output is not valid JSON: {e}')
assert actual == expected['data'], f'Parser did not derive randomized snapshot content: {actual}'
expected_manifest = (
    f"TIMESTAMP={expected['timestamp']}\n"
    f"SHA256={hashlib.sha256(json_bytes).hexdigest()}\n"
).encode()
with open(manifest_path, 'rb') as f:
    manifest_bytes = f.read()
assert manifest_bytes == expected_manifest, (
    f'Manifest must have exactly two lines and a final newline; got {manifest_bytes!r}'
)
PY
    if [ $? -ne 0 ]; then
        ok=0
    fi
fi

# Restore the supplied snapshot and execute the same compiled program to produce
# the required final artifacts before applying all original assertions.
cp "$workdir/original_snapshot.dat" /home/user/config_snapshot.dat
if [ $? -ne 0 ]; then
    ok=0
fi

if [ "$ok" -eq 1 ]; then
    rm -f /home/user/parsed_config.json /home/user/manifest.txt
    (cd /home/user && timeout 20s ./parser)
    if [ $? -ne 0 ]; then
        echo "Compiled parser failed on the supplied snapshot"
        ok=0
    fi
fi

cat <<'TEST_EOF' > "$workdir/test_final_state.py"
import os
import json
import hashlib

def test_parsed_config_json():
    json_path = "/home/user/parsed_config.json"
    assert os.path.isfile(json_path), f"File {json_path} does not exist."

    with open(json_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError as e:
            assert False, f"File {json_path} is not valid JSON: {e}"

    expected_data = {
        "Network": {
            "IPAddress": "10.0.5.55",
            "Port": "9090",
            "Gateway": "10.0.5.1",
            "Protocol": "TCP"
        },
        "Security": {
            "EnableSSL": "true",
            "CertPath": "/etc/ssl/certs/legacy.crt",
            "MaxConnections": "50"
        }
    }

    assert data == expected_data, f"JSON content in {json_path} does not match expected output. Got: {data}"

def test_manifest_txt():
    json_path = "/home/user/parsed_config.json"
    manifest_path = "/home/user/manifest.txt"

    assert os.path.isfile(manifest_path), f"File {manifest_path} does not exist."
    assert os.path.isfile(json_path), f"File {json_path} missing, cannot verify manifest."

    with open(json_path, "rb") as f:
        json_bytes = f.read()
    expected_sha256 = hashlib.sha256(json_bytes).hexdigest()

    with open(manifest_path, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(lines) == 2, f"Manifest should contain exactly 2 lines (TIMESTAMP and SHA256), found {len(lines)}."

    timestamp_line = lines[0]
    sha256_line = lines[1]

    assert timestamp_line.startswith("TIMESTAMP="), "First line of manifest must start with 'TIMESTAMP='."
    assert sha256_line.startswith("SHA256="), "Second line of manifest must start with 'SHA256='."

    timestamp_val = timestamp_line.split("=", 1)[1]
    sha256_val = sha256_line.split("=", 1)[1]

    assert timestamp_val == "1715000000", f"Expected TIMESTAMP=1715000000, got {timestamp_val}"
    assert sha256_val == expected_sha256, f"Expected SHA256={expected_sha256}, got {sha256_val}"

    expected_manifest = f"TIMESTAMP=1715000000\nSHA256={expected_sha256}\n".encode()
    with open(manifest_path, "rb") as f:
        manifest_bytes = f.read()
    assert manifest_bytes == expected_manifest, "Manifest must match the required format exactly, including its final newline."
TEST_EOF

if [ "$ok" -eq 1 ]; then
    python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider "$workdir/test_final_state.py" -x --tb=short 2>&1
    if [ $? -ne 0 ]; then
        ok=0
    fi
fi

if [ "$ok" -eq 1 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
