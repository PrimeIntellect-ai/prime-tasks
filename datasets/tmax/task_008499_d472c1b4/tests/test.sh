#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import secrets
import shlex
import subprocess
from pathlib import Path

SCRIPT = Path("/home/user/run_pipeline.sh")
RUST_DIR = Path("/home/user/rust_analyzer")
JSON_PATH = Path("/home/user/test_payload.json")
PROTO_PATH = Path("/home/user/config.proto")
BIN_PATH = Path("/home/user/payload.bin")
LOG_PATH = Path("/home/user/test_result.log")


def encode_with_protoc(json_bytes):
    result = subprocess.run(
        [
            "/usr/bin/protoc",
            "-I/home/user",
            "--encode=mobile.config.AppConfig",
            str(PROTO_PATH),
        ],
        input=json_bytes,
        capture_output=True,
    )
    assert result.returncode == 0, result.stderr.decode(errors="replace")
    return result.stdout


def expected_analyzer_output(data):
    assert data
    return f"First byte: {data[0]}\nTotal length: {len(data)}\n"


def traced_commands(stderr):
    commands = []
    for line in stderr.splitlines():
        if not re.match(r"^\++ ", line):
            continue
        text = re.sub(r"^\++ ", "", line)
        try:
            commands.append(shlex.split(text))
        except ValueError:
            pass
    return commands


def test_run_pipeline_exists_and_executable():
    assert SCRIPT.exists(), f"{SCRIPT} does not exist."
    assert os.access(SCRIPT, os.X_OK), f"{SCRIPT} is not executable."


def test_rust_compiles_and_has_required_behavior(tmp_path):
    assert RUST_DIR.exists(), f"{RUST_DIR} does not exist."
    result = subprocess.run(
        ["cargo", "check"], cwd=RUST_DIR, capture_output=True, text=True
    )
    assert result.returncode == 0, (
        "Rust project failed to compile. Cargo check output:\n" + result.stderr
    )

    # Exercise the submitted analyzer on answers not known while the image was built.
    for index, length in enumerate((7, 31)):
        data = bytes([17 + index * 91]) + secrets.token_bytes(length - 1)
        sample = tmp_path / f"sample-{index}.bin"
        sample.write_bytes(data)
        run = subprocess.run(
            ["cargo", "run", "--quiet", "--", str(sample)],
            cwd=RUST_DIR,
            capture_output=True,
            text=True,
            timeout=120,
        )
        assert run.returncode == 0, run.stderr
        assert run.stdout == expected_analyzer_output(data), (
            f"Analyzer output was incorrect for a {length}-byte input:\n{run.stdout}"
        )


def test_pipeline_is_executed_and_uses_required_tools():
    original_json = JSON_PATH.read_bytes()
    original_encoded = encode_with_protoc(original_json)

    random_payload = {
        "device_id": "device_" + secrets.token_hex(9),
        "config_version": secrets.randbelow(100000) + 100,
        "enable_beta_features": bool(secrets.randbits(1)),
    }
    random_json = (json.dumps(random_payload) + "\n").encode()
    expected_random = encode_with_protoc(random_json)

    try:
        JSON_PATH.write_bytes(random_json)
        BIN_PATH.unlink(missing_ok=True)
        LOG_PATH.unlink(missing_ok=True)

        run = subprocess.run(
            ["/bin/bash", "-x", str(SCRIPT)],
            cwd="/home/user",
            capture_output=True,
            text=True,
            timeout=180,
        )
        assert run.returncode == 0, (
            f"run_pipeline.sh exited with {run.returncode}.\n"
            f"stdout:\n{run.stdout}\nstderr:\n{run.stderr}"
        )

        commands = traced_commands(run.stderr)
        protoc_commands = [
            cmd for cmd in commands
            if cmd and os.path.basename(cmd[0]) == "protoc"
        ]
        assert protoc_commands, "run_pipeline.sh did not invoke protoc."
        assert any(
            "--encode=mobile.config.AppConfig" in cmd
            or any(
                cmd[i] == "--encode" and i + 1 < len(cmd)
                and cmd[i + 1] == "mobile.config.AppConfig"
                for i in range(len(cmd))
            )
            for cmd in protoc_commands
        ), "protoc was not invoked with message type mobile.config.AppConfig."
        assert any(
            any(os.path.basename(arg) == "config.proto" for arg in cmd)
            for cmd in protoc_commands
        ), "protoc was not invoked with config.proto."

        cargo_commands = [
            cmd for cmd in commands
            if cmd and os.path.basename(cmd[0]) == "cargo" and "run" in cmd[1:]
        ]
        assert cargo_commands, "run_pipeline.sh did not invoke cargo run."
        assert "/home/user/rust_analyzer" in run.stderr, (
            "cargo run was not associated with /home/user/rust_analyzer."
        )
        assert any(
            "--" in cmd and cmd[cmd.index("--") + 1:] == [str(BIN_PATH)]
            for cmd in cargo_commands
        ), (
            "cargo run must pass /home/user/payload.bin as the first and only "
            "analyzer argument."
        )

        assert BIN_PATH.exists(), "payload.bin was not generated by the pipeline."
        assert BIN_PATH.read_bytes() == expected_random, (
            "payload.bin is not protoc's encoding of the current test_payload.json."
        )
        assert LOG_PATH.exists(), "test_result.log was not generated by the pipeline."
        assert LOG_PATH.read_text() == expected_analyzer_output(expected_random), (
            "test_result.log does not contain the analyzer's output for payload.bin."
        )
    finally:
        # Restore the supplied fixture and execute the artifact directly so the final
        # files are generated from the payload named in the instruction.
        JSON_PATH.write_bytes(original_json)
        final = subprocess.run(
            [str(SCRIPT)],
            cwd="/home/user",
            capture_output=True,
            text=True,
            timeout=180,
        )
        assert final.returncode == 0, (
            f"Final run_pipeline.sh execution failed:\n{final.stderr}"
        )

    assert BIN_PATH.exists(), f"{BIN_PATH} does not exist. Did protoc run successfully?"
    assert BIN_PATH.read_bytes() == original_encoded, (
        "The final payload.bin is not protoc's encoding of test_payload.json."
    )
    assert LOG_PATH.exists(), (
        f"{LOG_PATH} does not exist. Did the script redirect output properly?"
    )
    content = LOG_PATH.read_text()
    expected_log = expected_analyzer_output(original_encoded)
    assert content == expected_log, f"Unexpected contents in {LOG_PATH}:\n{content}"
    assert f"First byte: {original_encoded[0]}" in content
    assert f"Total length: {len(original_encoded)}" in content
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
