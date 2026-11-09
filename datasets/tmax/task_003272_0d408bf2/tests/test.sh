#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import secrets
import subprocess
import pytest

FILTER_SCRIPT = "/home/user/filter.sh"
EVIL_CORPUS = "/app/corpora/evil"
CLEAN_CORPUS = "/app/corpora/clean"
PROCESSOR = "/app/process_single.sh"


def processor_semantics(payload):
    # process_single.sh reads one line and embeds ID and VALUE in C. The supplied
    # corpora and generated behavioral tests use decimal integer values.
    line = payload.split("\n", 1)[0]
    match = re.fullmatch(r"TELEMETRY_(.*)_(.*)", line)
    if not match:
        return 1

    ident, value_text = match.groups()
    if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", ident):
        return 1
    if not re.fullmatch(r"[0-9]+", value_text):
        return 1

    value = int(value_text)
    seen = set()
    while value != 1:
        if value % 100 == 0:
            return 1
        if value in seen:
            return 1
        seen.add(value)
        if value % 2 == 0:
            value //= 2
        else:
            value = 3 * value + 1
        assert value < 2**31, "Generated test exceeded the processor's int range"
    return 0


def run_filter(payload):
    try:
        result = subprocess.run(
            [FILTER_SCRIPT],
            input=payload.encode("utf-8"),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=1.0,
        )
    except subprocess.TimeoutExpired:
        pytest.fail(f"Filter exceeded one second for payload {payload!r}")

    assert result.stdout == b"", f"Filter wrote to stdout for {payload!r}"
    assert result.stderr == b"", f"Filter wrote to stderr for {payload!r}"
    return result.returncode


def assert_matches_processor(payload):
    expected = processor_semantics(payload)
    actual = run_filter(payload)
    assert actual == expected, (
        f"Wrong classification for {payload!r}: expected exit {expected}, got {actual}"
    )


def test_filter_script_exists_and_executable():
    assert os.path.isfile(FILTER_SCRIPT), f"Filter script {FILTER_SCRIPT} is missing."
    assert os.access(FILTER_SCRIPT, os.X_OK), f"Filter script {FILTER_SCRIPT} is not executable."
    with open(FILTER_SCRIPT, "rb") as fp:
        assert fp.readline().rstrip(b"\r\n") == b"#!/bin/bash", "Filter must start with #!/bin/bash"


def test_semantic_oracle_agrees_with_real_processor_on_regressions():
    probes = [
        "TELEMETRY_a001_3\n",       # Valid C identifier and converges.
        "TELEMETRY_A016_33\n",      # Reaches 100 and hangs.
        "TELEMETRY_bad-id_7\n",     # Generated C does not compile.
    ]
    for payload in probes:
        result = subprocess.run(
            [PROCESSOR], input=payload.encode("utf-8"),
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=4.0
        )
        expected = processor_semantics(payload)
        assert (0 if result.returncode == 0 else 1) == expected


def test_filter_matches_processor_on_provided_corpora():
    files = []
    for corpus in (EVIL_CORPUS, CLEAN_CORPUS):
        corpus_files = [
            os.path.join(corpus, name) for name in os.listdir(corpus)
            if os.path.isfile(os.path.join(corpus, name))
        ]
        assert corpus_files, f"Corpus {corpus} is empty."
        files.extend(corpus_files)

    failures = []
    for filepath in files:
        with open(filepath, "r") as fp:
            payload = fp.read()
        expected = processor_semantics(payload)
        actual = run_filter(payload)
        if actual != expected:
            failures.append((filepath, expected, actual))

    if failures:
        pytest.fail(f"Corpus classifications disagree with processor behavior: {failures[:5]}")


def test_filter_on_generated_behavioral_inputs():
    rng = random.Random(int.from_bytes(os.urandom(16), "big"))
    token = secrets.token_hex(5)

    safe_values = [n for n in range(1, 100) if processor_semantics(f"TELEMETRY_x_{n}") == 0]
    hanging_values = [n for n in range(1, 100) if processor_semantics(f"TELEMETRY_x_{n}") == 1]
    assert safe_values and hanging_values

    payloads = []
    for i in range(12):
        ident = f"lower_{token}_{i}"
        payloads.append(f"TELEMETRY_{ident}_{rng.choice(safe_values)}\n")
    for i in range(12):
        ident = f"Mixed_{token}_{i}"
        payloads.append(f"TELEMETRY_{ident}_{rng.choice(hanging_values)}\n")
    for i in range(8):
        ident = f"B_{token}_{i}"
        payloads.append(f"TELEMETRY_{ident}_{100 * rng.randint(1, 9)}\n")
    for i in range(8):
        payloads.append(f"TELEMETRY_bad-{token}-{i}_{rng.randint(1, 99)}\n")
    payloads.extend(["not_telemetry\n", "TELEMETRY_missingvalue_\n"])

    rng.shuffle(payloads)
    for payload in payloads:
        assert_matches_processor(payload)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
