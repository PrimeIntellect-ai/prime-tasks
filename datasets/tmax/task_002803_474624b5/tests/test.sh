#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import string
import subprocess

CONFIG_PATH = "/app/bash-json-reshaper-1.1/config.env"
RESHAPER_PATH = "/app/bash-json-reshaper-1.1/reshape.sh"
AGENT_PATH = "/home/user/run_pipeline.sh"


def run(path, input_data, timeout=20):
    return subprocess.run(
        [path],
        input=input_data.encode("utf-8"),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
    )


def expected_outputs(records):
    flattened = []
    reports = []
    for record in records:
        doc_id = record.get("id", "")
        text = record.get("text", "")
        metrics = record.get("metrics", {})
        for name in sorted(metrics):
            value = metrics[name]
            flattened.append(f"{doc_id}\t{name}\t{value}\t{text}\n")
            reports.append(f"[{doc_id}] Metric {name} has value {value}. Note: {text}\n")
    return "".join(flattened).encode("utf-8"), "".join(reports).encode("utf-8")


def encode_records(records):
    # ensure_ascii=True forces non-ASCII characters to enter the tools as JSON
    # unicode escape sequences, which is the behavior this task must repair.
    return "".join(json.dumps(record, ensure_ascii=True) + "\n" for record in records)


def test_config_env_fixed():
    assert os.path.isfile(CONFIG_PATH), f"Config file {CONFIG_PATH} does not exist."
    with open(CONFIG_PATH, "r") as f:
        content = f.read()
    assert "ENABLE_UNICODE_DECODE=1" in content, (
        f"Config file {CONFIG_PATH} was not fixed. "
        "Expected 'ENABLE_UNICODE_DECODE=1'."
    )

    effective = subprocess.run(
        ["bash", "-c", f'source "{CONFIG_PATH}"; printf "%s" "$ENABLE_UNICODE_DECODE"'],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=5,
    )
    assert effective.returncode == 0, effective.stderr.decode("utf-8", "replace")
    assert effective.stdout == b"1", "ENABLE_UNICODE_DECODE is not effectively set to 1"


def test_agent_script_exists_and_executable():
    assert os.path.isfile(AGENT_PATH), f"Agent script {AGENT_PATH} does not exist."
    assert os.access(AGENT_PATH, os.X_OK), f"Agent script {AGENT_PATH} is not executable."


def test_reshaper_actually_decodes_and_flattens():
    assert os.path.isfile(RESHAPER_PATH), f"Reshaper {RESHAPER_PATH} does not exist."
    assert os.access(RESHAPER_PATH, os.X_OK), f"Reshaper {RESHAPER_PATH} is not executable."

    records = [
        {"id": "doc_1", "metrics": {"beta": 20, "alpha": 10}, "text": "Data point\u2022"},
        {"id": "snow", "metrics": {"cold": 3}, "text": "Snowman \u2603 and NBSP\u00a0done"},
    ]
    input_data = encode_records(records)
    expected_flat, _ = expected_outputs(records)
    proc = run(RESHAPER_PATH, input_data)
    assert proc.returncode == 0, proc.stderr.decode("utf-8", "replace")
    assert proc.stdout == expected_flat, (
        f"Reshaper output mismatch. Expected {expected_flat!r}, got {proc.stdout!r}"
    )


def test_pipeline_invokes_vendored_reshaper():
    package_dir = os.path.dirname(RESHAPER_PATH)
    backup_path = os.path.join(package_dir, ".reshape.verifier-real.sh")
    marker_path = "/tmp/reshape_was_invoked"
    if os.path.exists(marker_path):
        os.unlink(marker_path)
    if os.path.exists(backup_path):
        os.unlink(backup_path)

    os.replace(RESHAPER_PATH, backup_path)
    try:
        with open(RESHAPER_PATH, "w") as wrapper:
            wrapper.write(
                "#!/bin/bash\n"
                f"printf 'invoked\\n' >> {marker_path}\n"
                f'exec "{backup_path}" "$@"\n'
            )
        os.chmod(RESHAPER_PATH, 0o755)

        records = [{"id": "probe", "metrics": {"zeta": 9, "alpha": 2}, "text": "Probe \u2713"}]
        input_data = encode_records(records)
        _, expected_report = expected_outputs(records)
        proc = run(AGENT_PATH, input_data)
        assert proc.returncode == 0, proc.stderr.decode("utf-8", "replace")
        assert os.path.isfile(marker_path), "run_pipeline.sh did not invoke the vendored reshape.sh"
        assert proc.stdout == expected_report
    finally:
        if os.path.exists(RESHAPER_PATH):
            os.unlink(RESHAPER_PATH)
        os.replace(backup_path, RESHAPER_PATH)
        if os.path.exists(marker_path):
            os.unlink(marker_path)


def generate_random_case(num_lines):
    unicode_chars = ["\u00a0", "\u2713", "\u2022", "\u2603", "\u2728"]
    records = []
    for _ in range(num_lines):
        id_val = "".join(random.choices(string.ascii_letters + string.digits, k=8))
        metrics = {}
        for _ in range(random.randint(1, 5)):
            name = "".join(random.choices(string.ascii_lowercase, k=5))
            metrics[name] = random.randint(0, 1000)

        parts = []
        for _ in range(random.randint(1, 5)):
            parts.append("".join(random.choices(string.ascii_letters, k=5)))
            if random.random() < 0.7:
                parts.append(random.choice(unicode_chars))

        records.append({"id": id_val, "metrics": metrics, "text": " ".join(parts)})

    return records, encode_records(records)


def test_fuzz_equivalence():
    random.seed(42)
    for iteration in range(100):
        records, input_data = generate_random_case(random.randint(10, 100))
        _, expected_report = expected_outputs(records)
        agent_proc = run(AGENT_PATH, input_data)
        assert agent_proc.returncode == 0, (
            f"Nonzero return code on iteration {iteration}: {agent_proc.returncode}\n"
            f"stderr: {agent_proc.stderr.decode('utf-8', 'replace')[:500]}"
        )
        assert agent_proc.stdout == expected_report, (
            f"Output mismatch on iteration {iteration}.\n"
            f"Input:\n{input_data[:500]}...\n\n"
            f"Expected:\n{expected_report.decode('utf-8')[:500]}...\n\n"
            f"Got:\n{agent_proc.stdout.decode('utf-8', 'replace')[:500]}..."
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
