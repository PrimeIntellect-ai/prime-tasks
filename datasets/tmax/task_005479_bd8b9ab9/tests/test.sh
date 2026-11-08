#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess
import tempfile

SCRIPT_PATH = "/home/user/recover_tx.py"


def run_extractor(dump_path, tx_id):
    result = subprocess.run(
        ["python3", SCRIPT_PATH, dump_path, tx_id],
        capture_output=True,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, (
        f"recover_tx.py failed with exit code {result.returncode}: {result.stderr}"
    )
    return result.stdout.strip()


def test_recovered_payload():
    payload_path = "/home/user/recovered_payload.txt"

    assert os.path.exists(payload_path), f"Output file not found: {payload_path}"

    with open(payload_path, "r") as f:
        content = f.read().strip()

    expected_payload = "PAYMENT_DATA_REQ_77491_SUCCESS"
    assert content == expected_payload, f"Incorrect payload recovered. Expected '{expected_payload}', but got '{content}'"


def test_recover_tx_script_fixed():
    assert os.path.isfile(SCRIPT_PATH), f"Extractor script not found: {SCRIPT_PATH}"
    assert not os.path.islink(SCRIPT_PATH), "recover_tx.py must be a regular script, not a symlink"

    with open(SCRIPT_PATH, "r") as f:
        content = f.read()

    # Preserve the original check for the known buggy expression.
    assert "data[payload_start : end_idx - 1]" not in content, "The off-by-one error in recover_tx.py was not fixed."

    expected_payload = "PAYMENT_DATA_REQ_77491_SUCCESS"
    output = run_extractor("/home/user/mem.dmp", "f8a92b1c")
    assert output == f"Recovered Payload: {expected_payload}", (
        f"recover_tx.py did not recover the full payload: {output!r}"
    )


def test_recover_tx_script_on_generated_dumps():
    for final_byte in ("Z", "7"):
        tx_id = secrets.token_hex(4)
        distractor_id = secrets.token_hex(4)
        while distractor_id == tx_id:
            distractor_id = secrets.token_hex(4)

        payload = f"DYNAMIC_PAYLOAD_{secrets.token_hex(16)}_{final_byte}"
        dump_data = (
            os.urandom(71)
            + f"TX_START|{distractor_id}|DISTRACTOR_DATA|TX_END".encode()
            + os.urandom(53)
            + f"TX_START|{tx_id}|{payload}|TX_END".encode()
            + os.urandom(67)
        )

        with tempfile.NamedTemporaryFile() as dump_file:
            dump_file.write(dump_data)
            dump_file.flush()
            output = run_extractor(dump_file.name, tx_id)

        assert output == f"Recovered Payload: {payload}", (
            "recover_tx.py failed to extract a complete dynamically generated payload; "
            f"expected {payload!r}, got {output!r}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
