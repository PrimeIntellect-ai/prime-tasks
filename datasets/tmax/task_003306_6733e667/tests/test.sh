#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess
import tempfile
from pathlib import Path


def parse_records(data):
    records = []
    offset = 0
    while offset < len(data):
        length = data[offset]
        offset += 1
        assert offset + length <= len(data), "Recovered data contains a truncated record"
        records.append(data[offset:offset + length].decode("utf-8", errors="replace"))
        offset += length
    return records


def daemon_open_data():
    candidates = []
    for proc in Path("/proc").iterdir():
        if not proc.name.isdigit():
            continue
        try:
            cmdline = (proc / "cmdline").read_bytes()
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue
        if b"metrics_emitter.py" not in cmdline:
            continue

        fd_dir = proc / "fd"
        try:
            fds = list(fd_dir.iterdir())
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue
        for fd in fds:
            try:
                target = os.readlink(fd)
                if target == "/tmp/metrics.dat (deleted)":
                    candidates.append(fd.read_bytes())
            except (FileNotFoundError, PermissionError, ProcessLookupError, OSError):
                continue

    assert candidates, "Could not find the running metrics_emitter.py daemon's deleted /tmp/metrics.dat descriptor"
    return candidates


def run_parser(input_path):
    result = subprocess.run(
        ["cargo", "run", "--quiet", "--manifest-path", "/home/user/parser/Cargo.toml", "--", str(input_path)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=120,
        check=False,
    )
    assert result.returncode == 0, f"Rust parser failed: {result.stderr.decode(errors='replace')}"
    return result.stdout.decode("utf-8")


def test_recovered_data_file():
    recovered_file = Path("/home/user/recovered.dat")
    assert recovered_file.exists(), "/home/user/recovered.dat does not exist."
    content = recovered_file.read_bytes()
    assert content in daemon_open_data(), "/home/user/recovered.dat does not match the daemon's open deleted file"
    parse_records(content)


def test_final_metrics_output():
    recovered_file = Path("/home/user/recovered.dat")
    final_file = Path("/home/user/final_metrics.txt")
    assert final_file.exists(), "/home/user/final_metrics.txt does not exist."

    expected_content = ",".join(parse_records(recovered_file.read_bytes())) + "\n"
    content = final_file.read_text()
    assert content == expected_content, f"Content of /home/user/final_metrics.txt is incorrect. Expected {expected_content!r}, got {content!r}"

    actual_parser_output = run_parser(recovered_file)
    assert actual_parser_output == expected_content, "The compiled Rust parser does not produce the required output for recovered.dat"


def test_rust_parser_fixed():
    main_rs = Path("/home/user/parser/src/main.rs")
    assert main_rs.exists(), "/home/user/parser/src/main.rs does not exist."
    content = main_rs.read_text()

    # Preserve the original source-level assertion while also exercising the parser.
    assert "len + 1" not in content or "buf.len(), len" not in content or "vec![0u8; len]" in content, "The buffer allocation bug in /home/user/parser/src/main.rs does not appear to be fixed."

    records = [
        secrets.token_bytes(1).hex().encode(),
        secrets.token_bytes(31).hex().encode(),
        (secrets.token_hex(127) + "x").encode(),
    ]
    payload = b"".join(bytes([len(record)]) + record for record in records)
    expected = b",".join(records).decode() + "\n"

    with tempfile.NamedTemporaryFile() as test_input:
        test_input.write(payload)
        test_input.flush()
        assert run_parser(test_input.name) == expected, "The Rust parser fails on independently generated variable-length records"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
