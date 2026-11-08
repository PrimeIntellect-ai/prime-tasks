#!/bin/bash
set -e
mkdir -p /logs/verifier

STANDALONE_PATH="/home/user/prepare_data.rs"
CARGO_PATH="/home/user/data_prep/src/main.rs"
RUNNER="/tmp/run_prepare_data.sh"
BINARY="/tmp/prepare_data_verifier_bin"
rm -f "$RUNNER" "$BINARY"

# Compile the submitted Rust artifact. Preserve support for either form accepted
# by the original verifier, falling back to the Cargo project if necessary.
if [ -f "$STANDALONE_PATH" ] && rustc "$STANDALONE_PATH" -o "$BINARY"; then
    cat > "$RUNNER" <<'RUN_EOF'
#!/bin/bash
exec /tmp/prepare_data_verifier_bin
RUN_EOF
elif [ -f "$CARGO_PATH" ] && [ -f /home/user/data_prep/Cargo.toml ] && \
     cargo build --quiet --manifest-path /home/user/data_prep/Cargo.toml; then
    cat > "$RUNNER" <<'RUN_EOF'
#!/bin/bash
exec cargo run --quiet --manifest-path /home/user/data_prep/Cargo.toml
RUN_EOF
else
    echo "0" > /logs/verifier/reward.txt
    exit 0
fi
chmod +x "$RUNNER"

# Require the compiled program itself to generate the initial output.
rm -f /home/user/tracking.json
if ! timeout 30 "$RUNNER"; then
    echo "0" > /logs/verifier/reward.txt
    exit 0
fi

cat <<'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import random
import re
import secrets
import string
import subprocess

DATASET = "/home/user/dataset.txt"
JSON_PATH = "/home/user/tracking.json"
RUNNER = "/tmp/run_prepare_data.sh"


def expected_for(text):
    normalized = re.sub(r"[^a-z0-9]", " ", text.lower())
    tokens = normalized.split()
    total = len(tokens)
    count = sum(token == "anomaly" for token in tokens)
    return total, count, (2.0 + count) / (4.0 + total)


def load_tracking():
    assert os.path.isfile(JSON_PATH), f"The output file {JSON_PATH} does not exist."
    with open(JSON_PATH, "r") as f:
        return json.load(f)


def run_program(text):
    with open(DATASET, "w") as f:
        f.write(text)
    if os.path.exists(JSON_PATH):
        os.unlink(JSON_PATH)
    subprocess.run([RUNNER], check=True, timeout=30)
    return load_tracking()


def assert_result(data, expected):
    total, count, posterior = expected
    assert "total_tokens" in data, "Missing 'total_tokens' in JSON output."
    assert "anomaly_count" in data, "Missing 'anomaly_count' in JSON output."
    assert "posterior_expected_value" in data, "Missing 'posterior_expected_value' in JSON output."
    assert data["total_tokens"] == total
    assert data["anomaly_count"] == count
    assert math.isclose(data["posterior_expected_value"], posterior, rel_tol=1e-7, abs_tol=1e-9)


def test_rust_program_exists():
    standalone_path = "/home/user/prepare_data.rs"
    cargo_path = "/home/user/data_prep/src/main.rs"
    assert os.path.isfile(standalone_path) or os.path.isfile(cargo_path), \
        "The Rust program was not found at /home/user/prepare_data.rs or /home/user/data_prep/src/main.rs"


def test_tracking_json_exists():
    assert os.path.isfile(JSON_PATH), f"The output file {JSON_PATH} does not exist."


def test_tracking_json_content():
    with open(JSON_PATH, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            raise AssertionError(f"The file {JSON_PATH} does not contain valid JSON.")

    assert "total_tokens" in data, "Missing 'total_tokens' in JSON output."
    assert "anomaly_count" in data, "Missing 'anomaly_count' in JSON output."
    assert "posterior_expected_value" in data, "Missing 'posterior_expected_value' in JSON output."
    assert data["total_tokens"] == 16, f"Expected total_tokens to be 16, got {data['total_tokens']}"
    assert data["anomaly_count"] == 3, f"Expected anomaly_count to be 3, got {data['anomaly_count']}"
    expected_posterior = 0.25
    assert math.isclose(data["posterior_expected_value"], expected_posterior, rel_tol=1e-4), \
        f"Expected posterior_expected_value to be ~{expected_posterior}, got {data['posterior_expected_value']}"


def test_program_processes_runtime_datasets():
    with open(DATASET, "r") as f:
        original = f.read()

    nonce = secrets.token_hex(8)
    rng = random.SystemRandom()
    words = [
        "item" + nonce,
        "ANOMALY",
        "pre-anomaly-post",
        "safe" + str(rng.randrange(1000, 9999)),
        "AnOmAlY",
        "node_" + nonce,
    ]
    rng.shuffle(words)
    case_one = ("!@#" + ",.;".join(words) + "\n") * rng.randrange(1, 4)
    case_two = " ".join("clean" + nonce + str(i) for i in range(rng.randrange(5, 12)))
    count = rng.randrange(2, 7)
    case_three = " / ".join(["anomaly"] * count + ["notanomaly", nonce, "42x"])

    try:
        for text in (case_one, case_two, case_three):
            data = run_program(text)
            assert_result(data, expected_for(text))
    finally:
        # Leave the required output corresponding to the original dataset.
        data = run_program(original)
        assert_result(data, expected_for(original))
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
