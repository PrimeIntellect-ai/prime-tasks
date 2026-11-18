#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import importlib.util
import inspect
import json
import math
import os
import secrets
import shutil
import sqlite3
import subprocess
import tempfile

ANALYZE = "/home/user/analyze.py"
FLAG = "/home/user/flag.txt"
EXPECTED_ORIGINAL = "FLAG{fL0at1ng_p0int_f0r3ns1cs_M4st3r}"


def load_analyze():
    spec = importlib.util.spec_from_file_location("submitted_analyze", ANALYZE)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def unpadded_payload(obj):
    # Ensure the generated encoding genuinely requires restored padding.
    while True:
        raw = json.dumps(obj, separators=(",", ":")).encode()
        encoded = base64.b64encode(raw).decode()
        if encoded.endswith("="):
            return encoded.rstrip("=")
        obj["nonce"] = obj.get("nonce", "") + "x"


def test_analyze_is_executed_and_extracts_original_flag():
    assert os.path.isfile(ANALYZE), f"Expected {ANALYZE} to be a regular file."
    assert not os.path.islink(ANALYZE), f"Expected {ANALYZE} itself to be repaired, not replaced by a symlink."

    if os.path.lexists(FLAG):
        os.remove(FLAG)

    result = subprocess.run(
        ["python3", ANALYZE],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=15,
    )
    assert result.returncode == 0, f"analyze.py failed:\n{result.stdout}\n{result.stderr}"
    assert os.path.exists(FLAG), f"Expected {FLAG} to exist. The script did not run successfully or did not write the output."
    assert os.path.isfile(FLAG), f"Expected {FLAG} to be a file."
    with open(FLAG, "r") as f:
        flag_content = f.read().strip()
    assert flag_content == EXPECTED_ORIGINAL, f"Expected the flag to be '{EXPECTED_ORIGINAL}', but got '{flag_content}'. Ensure the script correctly extracts the flag from the database."


def test_payload_decoding_stable_math_and_approximate_float_lookup():
    module = load_analyze()

    payload_obj = {"id": secrets.randbelow(800000) + 100000, "x": 1e-12}
    encoded = unpadded_payload(payload_obj.copy())
    assert len(encoded) % 4 != 0
    assert module.decode_payload(encoded)["id"] == payload_obj["id"]

    expected_key = math.expm1(payload_obj["x"]) / payload_obj["x"]
    actual_key = module.compute_key(payload_obj["x"])
    assert math.isclose(actual_key, expected_key, rel_tol=1e-15, abs_tol=2e-15), (
        f"compute_key is numerically unstable: expected {expected_key!r}, got {actual_key!r}"
    )

    with tempfile.TemporaryDirectory() as td:
        db_path = os.path.join(td, "lookup.db")
        wanted = "FLAG{" + secrets.token_hex(18) + "}"
        conn = sqlite3.connect(db_path)
        conn.execute("CREATE TABLE beacons (id INTEGER, timestamp INTEGER, key REAL, flag TEXT)")
        conn.execute("INSERT INTO beacons VALUES (?, ?, ?, ?)", (payload_obj["id"], 7, expected_key + 1e-3, "distractor"))
        conn.execute("INSERT INTO beacons VALUES (?, ?, ?, ?)", (payload_obj["id"], 7, expected_key + 2e-10, wanted))
        conn.commit()
        conn.close()

        params = inspect.signature(module.find_flag).parameters
        if len(params) >= 4:
            found = module.find_flag(db_path, payload_obj["id"], expected_key, 7)
        else:
            found = module.find_flag(db_path, payload_obj["id"], expected_key)
        assert found == wanted, "find_flag did not perform a tolerant floating-point key lookup."


def test_dynamic_end_to_end_timestamp_correlation():
    with tempfile.TemporaryDirectory() as td:
        shutil.copy2(ANALYZE, os.path.join(td, "analyze.py"))
        payload_id = secrets.randbelow(800000) + 100000
        timestamp = 1800000000 + secrets.randbelow(1000000)
        x = 2e-8
        computed_key = math.expm1(x) / x
        expected_flag = "FLAG{" + secrets.token_hex(20) + "}"
        wrong_flag = "FLAG{" + secrets.token_hex(20) + "}"

        encoded = unpadded_payload({"id": payload_id, "x": x})
        with open(os.path.join(td, "syslog.log"), "w") as f:
            f.write(f"{timestamp} INFO Payload: {encoded}\n")

        conn = sqlite3.connect(os.path.join(td, "beacon.db"))
        conn.execute("CREATE TABLE beacons (id INTEGER, timestamp INTEGER, key REAL, flag TEXT)")
        # The wrong timestamp is deliberately inserted first and has the same
        # approximate key, so ID/key-only queries return the wrong record.
        conn.execute("INSERT INTO beacons VALUES (?, ?, ?, ?)", (payload_id, timestamp - 3600, computed_key + 3e-10, wrong_flag))
        conn.execute("INSERT INTO beacons VALUES (?, ?, ?, ?)", (payload_id, timestamp, computed_key + 3e-10, expected_flag))
        conn.execute("INSERT INTO beacons VALUES (?, ?, ?, ?)", (payload_id + 1, timestamp, computed_key, "unrelated"))
        conn.commit()
        conn.close()

        result = subprocess.run(
            ["python3", os.path.join(td, "analyze.py")],
            cwd=td,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=15,
        )
        assert result.returncode == 0, f"Dynamic execution failed:\n{result.stdout}\n{result.stderr}"
        output_path = os.path.join(td, "flag.txt")
        assert os.path.isfile(output_path), "Dynamic execution did not create flag.txt."
        with open(output_path, "r") as f:
            actual = f.read().strip()
        assert actual == expected_flag, "analyze.py did not correlate the payload timestamp with the correct database record."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
