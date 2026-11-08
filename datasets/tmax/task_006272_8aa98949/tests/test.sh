#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import subprocess
import tempfile
import pytest

def test_audit_report_exists_and_format():
    report_path = "/home/user/audit_report.bin"
    assert os.path.exists(report_path), f"Audit report not found at {report_path}"
    assert os.path.isfile(report_path), f"{report_path} is not a file"

    # The expected plaintext is "PIN: 1234, Redirect: next_url, SUID: backup_tool"
    expected_plaintext = b"PIN: 1234, Redirect: next_url, SUID: backup_tool"

    # AES-GCM with a 16-byte tag will result in ciphertext of same length as plaintext + 16 bytes
    expected_length = len(expected_plaintext) + 16

    with open(report_path, "rb") as f:
        actual_content = f.read()

    assert len(actual_content) == expected_length, (
        f"Expected audit report to be {expected_length} bytes, "
        f"but got {len(actual_content)} bytes. Check your plaintext and encryption method."
    )

    # To verify the exact ciphertext without third-party Python libraries,
    # we can compile a minimal Rust program using the same dependencies 
    # available in the student's environment to compute the expected ciphertext.

    rust_code = """
    use aes_gcm::{
        aead::{Aead, KeyInit},
        Aes128Gcm, Nonce, Key
    };
    use std::io::Write;

    fn main() {
        let key = Key::<Aes128Gcm>::from_slice(b"secret_key_16_by");
        let nonce = Nonce::from_slice(b"unique_nonce");
        let cipher = Aes128Gcm::new(&key);

        let plaintext = b"PIN: 1234, Redirect: next_url, SUID: backup_tool";
        let ciphertext = cipher.encrypt(nonce, plaintext.as_ref()).expect("encryption failure!");

        std::io::stdout().write_all(&ciphertext).unwrap();
    }
    """

    with tempfile.TemporaryDirectory() as tmpdir:
        # Create a temporary Cargo project to build the verifier
        subprocess.run(["cargo", "new", "verifier"], cwd=tmpdir, capture_output=True, check=True)

        cargo_toml_path = os.path.join(tmpdir, "verifier", "Cargo.toml")
        with open(cargo_toml_path, "a") as f:
            f.write('aes-gcm = "0.10.3"\n')

        main_rs_path = os.path.join(tmpdir, "verifier", "src", "main.rs")
        with open(main_rs_path, "w") as f:
            f.write(rust_code)

        # Build and run the verifier
        run_res = subprocess.run(
            ["cargo", "run", "--quiet"],
            cwd=os.path.join(tmpdir, "verifier"),
            capture_output=True,
            check=True
        )

        expected_ciphertext = run_res.stdout

    assert actual_content == expected_ciphertext, (
        "The ciphertext in the audit report does not match the expected value. "
        "Ensure the plaintext is exactly formatted as requested and the correct key/nonce were used."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
