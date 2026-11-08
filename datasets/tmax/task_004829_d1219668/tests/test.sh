#!/bin/bash
set -e
mkdir -p /logs/verifier
echo "0" > /logs/verifier/reward.txt

REAL_DECODER="/app/.sensor_decoder.verifier.$$"
DECODER_LOG="/tmp/sensor_decoder_calls.$$"
mv /app/sensor_decoder "$REAL_DECODER"
touch "$DECODER_LOG"
chmod 666 "$DECODER_LOG"

restore_decoder() {
    rm -f /app/sensor_decoder
    if [ -e "$REAL_DECODER" ]; then
        mv "$REAL_DECODER" /app/sensor_decoder
        chmod +x /app/sensor_decoder
    fi
    rm -f "$DECODER_LOG"
}
trap restore_decoder EXIT

cat > /app/sensor_decoder <<EOF
#!/usr/bin/python3
import hashlib
import json
import subprocess
import sys

path = sys.argv[1] if len(sys.argv) > 1 else ""
try:
    with open(path, "rb") as f:
        digest = hashlib.sha256(f.read()).hexdigest()
except Exception:
    digest = None
with open("$DECODER_LOG", "a", encoding="utf-8") as log:
    log.write(json.dumps({"path": path, "sha256": digest}) + "\\n")
result = subprocess.run(["$REAL_DECODER"] + sys.argv[1:])
sys.exit(result.returncode)
EOF
chmod 755 /app/sensor_decoder

export DECODER_LOG
cat <<'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import io
import json
import os
import random
import secrets
import string
import time
import zipfile

import pytest
import requests

URL = "http://127.0.0.1:9000/upload"
DECODER_LOG = os.environ["DECODER_LOG"]


def wait_for_service():
    for _ in range(40):
        try:
            requests.get("http://127.0.0.1:9000/", timeout=0.5)
            return
        except requests.RequestException:
            time.sleep(0.25)
    pytest.fail("Service did not start on 127.0.0.1:9000")


def token(n=10):
    alphabet = string.ascii_uppercase + string.digits
    return "".join(secrets.choice(alphabet) for _ in range(n))


def wal(sensor_id):
    return b"WALMAGIC" + sensor_id.encode("ascii").ljust(16, b"\0")


def read_calls(offset):
    with open(DECODER_LOG, encoding="utf-8") as f:
        lines = f.readlines()
    return [json.loads(line) for line in lines[offset:]], len(lines)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def test_randomized_uploads_use_decoder_rename_files_and_block_zip_slip():
    wait_for_service()
    log_offset = 0

    # Several independently randomized sequential uploads prevent responses from
    # being keyed to fixed request order, member names, or SensorIDs.
    for round_number in range(3):
        valid = []
        for index in range(random.randint(2, 5)):
            sensor_id = token(random.randint(6, 14))
            basename = f"{token(9)}_{index}.wal"
            member = basename if index % 2 == 0 else f"nested_{token(5)}/deeper/{basename}"
            content = wal(sensor_id)
            valid.append((member, basename, sensor_id, content))

        target1 = f"/tmp/zipslip_{token(14)}.wal"
        target2 = f"/tmp/zipslip_abs_{token(14)}.wal"
        malicious1 = wal(token(12))
        malicious2 = wal(token(12))
        for target in (target1, target2):
            if os.path.lexists(target):
                os.remove(target)

        entries = [(member, content) for member, _, _, content in valid]
        entries += [
            ("../../../../../../../../../../tmp/" + os.path.basename(target1), malicious1),
            (target2, malicious2),
            (f"notes_{token(8)}.txt", secrets.token_bytes(31)),
        ]
        random.SystemRandom().shuffle(entries)

        archive = io.BytesIO()
        with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED) as zf:
            for name, content in entries:
                zf.writestr(name, content)

        response = requests.post(
            URL,
            data=archive.getvalue(),
            headers={"Content-Type": "application/zip"},
            timeout=15,
        )
        assert response.status_code == 200, response.text
        try:
            result = response.json()
        except ValueError:
            pytest.fail(f"Response is not valid JSON: {response.text}")
        assert isinstance(result, list)

        expected_names = [f"{sensor_id}_{basename}" for _, basename, sensor_id, _ in valid]
        assert sorted(result) == sorted(expected_names)
        assert len(result) == len(expected_names)

        calls, log_offset = read_calls(log_offset)
        expected_hashes = {sha(content) for _, _, _, content in valid}
        called_hashes = [call["sha256"] for call in calls]

        # Every safe WAL must actually be passed to /app/sensor_decoder exactly
        # once, while traversal members must never reach the decoder.
        assert len(calls) == len(valid), calls
        assert set(called_hashes) == expected_hashes
        assert len(called_hashes) == len(set(called_hashes))
        assert sha(malicious1) not in called_hashes
        assert sha(malicious2) not in called_hashes

        calls_by_hash = {call["sha256"]: call for call in calls}
        for member, basename, sensor_id, content in valid:
            original_path = calls_by_hash[sha(content)]["path"]
            assert original_path and os.path.isfile(original_path) is False, (
                "The original WAL should have been renamed after decoding"
            )
            renamed_path = os.path.join(os.path.dirname(original_path), f"{sensor_id}_{basename}")
            assert os.path.isfile(renamed_path), f"Missing renamed staging file: {renamed_path}"
            with open(renamed_path, "rb") as f:
                assert f.read() == content

        assert not os.path.lexists(target1), f"Zip slip created {target1}"
        assert not os.path.lexists(target2), f"Zip slip created {target2}"


if __name__ == "__main__":
    raise SystemExit(pytest.main([__file__]))
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
