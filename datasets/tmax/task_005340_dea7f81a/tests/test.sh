#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import shlex
import subprocess
import pytest

BINARY = "/app/ws-route-parser/target/release/ws-route-parser"
SCRIPT = "/home/user/ws_filter.sh"
PROJECT = "/app/ws-route-parser"


def test_rust_binary_compiled_and_works():
    assert os.path.isfile(BINARY), f"Compiled Rust binary not found at {BINARY}"
    assert os.access(BINARY, os.X_OK), f"Rust binary at {BINARY} is not executable"

    result = subprocess.run(
        [BINARY, "/api/test?room=50"],
        capture_output=True,
        text=True
    )
    assert result.returncode == 0, "Rust binary failed to execute"
    output = result.stdout.strip()
    assert "PATH=/api/test" in output, f"Unexpected PATH output from binary: {output}"
    assert "ROOM=50" in output, f"Unexpected ROOM output from binary: {output}"


def test_rust_project_rebuilds_and_parser_handles_unseen_inputs():
    source = os.path.join(PROJECT, "src/main.rs")
    manifest = os.path.join(PROJECT, "Cargo.toml")
    assert os.path.isfile(source), f"Rust source not found at {source}"
    assert os.path.isfile(manifest), f"Cargo manifest not found at {manifest}"

    clean = subprocess.run(["cargo", "clean"], cwd=PROJECT, capture_output=True, text=True)
    assert clean.returncode == 0, f"cargo clean failed: {clean.stderr}"
    build = subprocess.run(
        ["cargo", "build", "--release"], cwd=PROJECT, capture_output=True, text=True
    )
    assert build.returncode == 0, f"cargo build --release failed: {build.stderr}"
    assert os.path.isfile(BINARY) and os.access(BINARY, os.X_OK)
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Release artifact is not a native executable"

    nonce = secrets.token_hex(12)
    samples = [
        (f"/api/{nonce}?room=317&user={nonce}", f"PATH=/api/{nonce} ROOM=317 USER={nonce}"),
        (f"/ws/{nonce}%20channel?token={nonce}&id=9381", f"PATH=/ws/{nonce} channel TOKEN={nonce} ID=9381"),
        (f"/api/{nonce}/item?id={secrets.randbelow(900000) + 100000}", None),
    ]
    for url, expected in samples:
        result = subprocess.run([BINARY, url], capture_output=True, text=True)
        assert result.returncode == 0, f"Parser failed for unseen input {url!r}"
        if expected is None:
            value = url.split("?", 1)[1].split("=", 1)[1]
            expected = f"PATH=/api/{nonce}/item ID={value}"
        assert result.stdout.strip() == expected, (
            f"Incorrect parser output for {url!r}: {result.stdout!r}"
        )


def test_bash_script_exists_and_executable():
    assert os.path.isfile(SCRIPT), f"Bash script not found at {SCRIPT}"
    assert os.access(SCRIPT, os.X_OK), f"Bash script at {SCRIPT} is not executable"


def test_clean_corpus():
    clean_dir = "/app/corpus/clean"
    assert os.path.isdir(clean_dir), f"Clean corpus directory not found at {clean_dir}"

    clean_files = [f for f in os.listdir(clean_dir) if os.path.isfile(os.path.join(clean_dir, f))]
    assert len(clean_files) > 0, "No files found in clean corpus"

    failed_files = []
    for filename in clean_files:
        filepath = os.path.join(clean_dir, filename)
        with open(filepath, "r") as f:
            url = f.read().strip()

        result = subprocess.run([SCRIPT, url], capture_output=True, text=True)
        if result.returncode != 0 or "ALLOW" not in result.stdout:
            failed_files.append(filename)

    if failed_files:
        pytest.fail(f"{len(failed_files)} of {len(clean_files)} clean modified/rejected: {', '.join(failed_files)}")


def test_evil_corpus():
    evil_dir = "/app/corpus/evil"
    assert os.path.isdir(evil_dir), f"Evil corpus directory not found at {evil_dir}"

    evil_files = [f for f in os.listdir(evil_dir) if os.path.isfile(os.path.join(evil_dir, f))]
    assert len(evil_files) > 0, "No files found in evil corpus"

    failed_files = []
    for filename in evil_files:
        filepath = os.path.join(evil_dir, filename)
        with open(filepath, "r") as f:
            url = f.read().strip()

        result = subprocess.run([SCRIPT, url], capture_output=True, text=True)
        if result.returncode == 0 or "DENY" not in result.stdout:
            failed_files.append(filename)

    if failed_files:
        pytest.fail(f"{len(failed_files)} of {len(evil_files)} evil bypassed: {', '.join(failed_files)}")


def test_filter_on_unseen_inputs_and_uses_parser():
    nonce = secrets.token_hex(10)
    valid_token = secrets.token_hex(32).upper()
    invalid_hex_token = "g" + secrets.token_hex(31) + "0"
    good_room = secrets.randbelow(998) + 2
    high_room = secrets.randbelow(9000) + 1001

    cases = [
        (f"/api/{nonce}?room={good_room}&user={nonce}", True),
        (f"/ws/{nonce}/chat", True),
        (f"/api/admin/{nonce}?token={valid_token}", True),
        (f"/ws/admin-{nonce}?token={valid_token}&room=1000", True),
        (f"/api/{nonce}?room=1", True),
        (f"/api/{nonce}?room=1000", True),
        (f"/api/{nonce}?token=short", True),
        (f"/other/{nonce}?room={good_room}", False),
        (f"/api/{nonce}?room=0", False),
        (f"/ws/{nonce}?room={high_room}", False),
        (f"/api/admin/{nonce}", False),
        (f"/api/admin/{nonce}?token={secrets.token_hex(12)}", False),
        (f"/api/admin/{nonce}?token={invalid_hex_token}", False),
        (f"/api/{nonce}/../private", False),
        (f"/ws/../{nonce}", False),
    ]

    real_binary = os.path.join(PROJECT, "target/release", f".ws-route-parser.real-{nonce}")
    log_path = f"/tmp/ws-parser-calls-{nonce}.log"
    os.replace(BINARY, real_binary)
    wrapper = (
        "#!/bin/bash\n"
        f"printf '%s\\t%s\\n' \"$#\" \"${{1-}}\" >> {shlex.quote(log_path)}\n"
        f"exec {shlex.quote(real_binary)} \"$@\"\n"
    )
    with open(BINARY, "w") as f:
        f.write(wrapper)
    os.chmod(BINARY, 0o755)

    try:
        for url, should_allow in cases:
            result = subprocess.run([SCRIPT, url], capture_output=True, text=True)
            if should_allow:
                assert result.returncode == 0 and "ALLOW" in result.stdout, (
                    f"Valid unseen URL rejected: {url!r}; stdout={result.stdout!r}, stderr={result.stderr!r}"
                )
            else:
                assert result.returncode == 1 and "DENY" in result.stdout, (
                    f"Invalid unseen URL accepted: {url!r}; stdout={result.stdout!r}, stderr={result.stderr!r}"
                )

        assert os.path.isfile(log_path), "Filter never invoked the required Rust parser"
        with open(log_path, "r") as f:
            calls = set(line.rstrip("\n") for line in f)
        for url, _ in cases:
            assert f"1\t{url}" in calls, f"Filter did not pass URL {url!r} to the Rust parser"
    finally:
        if os.path.lexists(BINARY):
            os.unlink(BINARY)
        if os.path.exists(real_binary):
            os.replace(real_binary, BINARY)
        if os.path.exists(log_path):
            os.unlink(log_path)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
