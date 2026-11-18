#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import shutil
import subprocess
import tempfile


def run_encoder(path, data):
    serialized = str(len(data)).encode("ascii") + b":" + data
    result = subprocess.run(
        [path], input=serialized, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, timeout=10
    )
    assert result.returncode == 0, result.stderr.decode("utf-8", "replace")
    expected = data.hex().encode("ascii")
    assert result.stdout in (expected, expected + b"\n"), (
        f"Incorrect encoding for a {len(data)}-byte dynamically generated payload"
    )


def test_encoder_compiled():
    encoder_path = "/home/user/waf_encoder/encoder"
    assert os.path.isfile(encoder_path), f"Compiled binary not found at {encoder_path}"
    assert os.access(encoder_path, os.X_OK), f"Binary {encoder_path} is not executable"
    with open(encoder_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "encoder is not a compiled ELF binary"


def test_source_and_makefile_build_cleanly():
    source_dir = "/home/user/waf_encoder"
    with tempfile.TemporaryDirectory() as build_dir:
        shutil.copy2(os.path.join(source_dir, "encoder.c"), build_dir)
        shutil.copy2(os.path.join(source_dir, "Makefile"), build_dir)
        result = subprocess.run(
            ["make", "-B", "encoder"], cwd=build_dir,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20
        )
        assert result.returncode == 0, (
            result.stdout.decode("utf-8", "replace") +
            result.stderr.decode("utf-8", "replace")
        )
        rebuilt = os.path.join(build_dir, "encoder")
        assert os.path.isfile(rebuilt) and os.access(rebuilt, os.X_OK)
        with open(rebuilt, "rb") as f:
            assert f.read(4) == b"\x7fELF"
        run_encoder(rebuilt, secrets.token_bytes(73))


def test_encoder_on_dynamic_inputs():
    encoder_path = "/home/user/waf_encoder/encoder"
    for size in (0, 1, 17, 257, 4093):
        run_encoder(encoder_path, secrets.token_bytes(size))


def test_test_harness_exists_and_executable():
    harness_path = "/home/user/test_harness.sh"
    assert os.path.isfile(harness_path), f"Test harness script not found at {harness_path}"
    assert os.access(harness_path, os.X_OK), f"Test harness {harness_path} is not executable"


def test_payload_dat_correct():
    payload_dat_path = "/home/user/payload.dat"
    assert os.path.isfile(payload_dat_path), f"Payload file not found at {payload_dat_path}"

    with open(payload_dat_path, "r") as f:
        content = f.read()

    assert len(content) == 100000, f"payload.dat should be exactly 100,000 bytes, got {len(content)}"
    assert content == "X" * 100000, "payload.dat does not contain exactly 100,000 'X' characters"


def test_payload_ser_correct():
    payload_ser_path = "/home/user/payload.ser"
    assert os.path.isfile(payload_ser_path), f"Serialized payload not found at {payload_ser_path}"

    with open(payload_ser_path, "r") as f:
        content = f.read()

    expected_prefix = "100000:"
    assert content.startswith(expected_prefix), "payload.ser does not start with '100000:'"
    assert content[len(expected_prefix):] == "X" * 100000, "payload.ser data portion is incorrect"


def test_payload_enc_correct():
    payload_enc_path = "/home/user/payload.enc"
    assert os.path.isfile(payload_enc_path), f"Encoded payload not found at {payload_enc_path}"

    with open(payload_enc_path, "r") as f:
        content = f.read().strip()

    assert len(content) == 200000, f"payload.enc should contain 200,000 hex characters, got {len(content)}"
    assert content == "58" * 100000, "payload.enc does not correctly hex-encode the payload"


def test_qa_log_correct():
    qa_log_path = "/home/user/qa_log.txt"
    assert os.path.isfile(qa_log_path), f"QA log file not found at {qa_log_path}"

    with open(qa_log_path, "r") as f:
        content = f.read()

    assert "TEST: WAF_ENCODER" in content, "qa_log.txt missing 'TEST: WAF_ENCODER'"
    assert "STATUS: PASS" in content, "qa_log.txt missing 'STATUS: PASS'"

    time_match = re.search(r"TIME_MS:\s*\d+", content)
    assert time_match is not None, "qa_log.txt missing 'TIME_MS: [Calculated Duration]'"


def clear_harness_outputs():
    for path in ("/home/user/payload.dat", "/home/user/payload.ser",
                 "/home/user/payload.enc", "/home/user/qa_log.txt"):
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass


def run_harness():
    result = subprocess.run(
        ["/home/user/test_harness.sh"], stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, timeout=30
    )
    assert result.returncode == 0, result.stderr.decode("utf-8", "replace")


def assert_harness_state(status):
    with open("/home/user/payload.dat", "rb") as f:
        assert f.read() == b"X" * 100000
    with open("/home/user/payload.ser", "rb") as f:
        assert f.read() == b"100000:" + b"X" * 100000
    with open("/home/user/qa_log.txt", "r") as f:
        log = f.read()
    assert re.fullmatch(
        rf"TEST: WAF_ENCODER\nSTATUS: {status}\nTIME_MS: \d+\n?", log
    ), f"Unexpected qa_log.txt contents: {log!r}"


def compile_probe(destination, capture_path, encoded_pair):
    source = r'''
#include <stdio.h>
int main(void) {
    FILE *capture = fopen("CAPTURE_PATH", "wb");
    unsigned char buf[4096];
    size_t n;
    if (!capture) return 2;
    while ((n = fread(buf, 1, sizeof(buf), stdin)) != 0) {
        if (fwrite(buf, 1, n, capture) != n) return 3;
    }
    if (ferror(stdin) || fclose(capture) != 0) return 4;
    for (int i = 0; i < 100000; ++i) fputs("ENCODED_PAIR", stdout);
    return ferror(stdout) ? 5 : 0;
}
'''.replace("CAPTURE_PATH", capture_path).replace("ENCODED_PAIR", encoded_pair)
    src_path = destination + ".c"
    with open(src_path, "w") as f:
        f.write(source)
    result = subprocess.run(
        ["gcc", "-Wall", "-Werror", "-o", destination, src_path],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20
    )
    os.unlink(src_path)
    assert result.returncode == 0, result.stderr.decode("utf-8", "replace")


def test_harness_executes_encoder_and_checks_its_output():
    encoder = "/home/user/waf_encoder/encoder"
    harness = "/home/user/test_harness.sh"
    token = secrets.token_hex(12)
    backup = f"/home/user/waf_encoder/.encoder.verifier-backup-{token}"
    probe = f"/tmp/encoder-probe-{token}"
    capture = f"/tmp/encoder-input-{token}"

    os.replace(encoder, backup)
    try:
        compile_probe(probe, capture, "58")
        shutil.copy2(probe, encoder)
        os.chmod(encoder, 0o755)
        clear_harness_outputs()
        run_harness()
        with open(capture, "rb") as f:
            assert f.read() == b"100000:" + b"X" * 100000, (
                "Harness did not feed payload.ser to the encoder on standard input"
            )
        assert_harness_state("PASS")
        with open("/home/user/payload.enc", "rb") as f:
            assert f.read().strip() == b"58" * 100000

        compile_probe(probe, capture, "00")
        shutil.copy2(probe, encoder)
        os.chmod(encoder, 0o755)
        clear_harness_outputs()
        run_harness()
        with open(capture, "rb") as f:
            assert f.read() == b"100000:" + b"X" * 100000
        assert_harness_state("FAIL")
    finally:
        try:
            os.unlink(encoder)
        except FileNotFoundError:
            pass
        os.replace(backup, encoder)
        for path in (probe, capture):
            try:
                os.unlink(path)
            except FileNotFoundError:
                pass

    clear_harness_outputs()
    run_harness()
    assert_harness_state("PASS")
    with open("/home/user/payload.enc", "rb") as f:
        assert f.read().strip() == b"58" * 100000
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
