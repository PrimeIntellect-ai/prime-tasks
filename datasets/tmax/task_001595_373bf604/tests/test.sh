#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import secrets
import subprocess
import tempfile

SCRIPTS = [
    "/home/user/tokenize.sh",
    "/home/user/bootstrap.sh",
    "/home/user/inference.sh",
    "/home/user/run_experiment.sh",
]
WEIGHTS = {
    "critical": -10,
    "error": -6,
    "warning": -2,
    "info": 1,
    "success": 4,
    "resolved": 6,
}

def reference_tokenize(text):
    output = []
    for line in text.splitlines():
        line = line.lower()
        line = re.sub(r"[^a-z0-9 ]", "", line)
        line = re.sub(r" +", " ", line).strip(" ")
        output.append(line)
    return "".join(line + "\n" for line in output)

def line_score_units(line):
    return sum(WEIGHTS.get(word, 0) for word in line.split())

def expected_mean(lines):
    units = sum(line_score_units(line) for line in lines)
    return f"{units / (2.0 * len(lines)):.4f}"

def possible_bootstrap_means(lines):
    n = len(lines)
    choices = set(line_score_units(line) for line in lines)
    sums = {0}
    for _ in range(n):
        sums = {a + b for a in sums for b in choices}
    return {f"{total / (2.0 * n):.4f}" for total in sums}

def run_script(path, input_text=None, args=()):
    result = subprocess.run(
        [path, *args], input=input_text, text=True, capture_output=True,
        timeout=15
    )
    assert result.returncode == 0, (
        f"{path} exited with {result.returncode}: {result.stderr}"
    )
    return result.stdout

def test_scripts_exist_and_executable():
    for script in SCRIPTS:
        assert os.path.isfile(script), f"Script {script} does not exist."
        assert os.access(script, os.X_OK), f"Script {script} is not executable."

def test_raw_data_exists_and_valid():
    raw_data_path = "/home/user/raw_data.txt"
    assert os.path.isfile(raw_data_path), f"{raw_data_path} does not exist."
    with open(raw_data_path, "r") as f:
        lines = f.readlines()
    assert len(lines) >= 10, f"{raw_data_path} must contain at least 10 lines."

def test_artifacts_exist():
    artifacts_dir = "/home/user/artifacts"
    assert os.path.isdir(artifacts_dir), f"Artifacts directory {artifacts_dir} does not exist."
    for name in ["tokenized.txt", "baseline_score.txt", "bootstrap_scores.txt"]:
        assert os.path.isfile(os.path.join(artifacts_dir, name)), f"Artifact {name} is missing."

def test_tokenized_format():
    with open("/home/user/artifacts/tokenized.txt") as f:
        content = f.read()
    assert not re.search(r"[A-Z]", content), "tokenized.txt contains uppercase letters."
    assert not re.search(r"[^a-z0-9 \n]", content), "tokenized.txt contains punctuation or invalid characters."
    for line in content.split("\n"):
        if line:
            assert not line.startswith(" "), "tokenized.txt contains leading spaces."
            assert not line.endswith(" "), "tokenized.txt contains trailing spaces."
            assert "  " not in line, "tokenized.txt contains consecutive spaces."

def test_baseline_score_format():
    with open("/home/user/artifacts/baseline_score.txt") as f:
        content = f.read().strip()
    assert re.match(r"^-?[0-9]+\.[0-9]{4}$", content), (
        f"baseline_score.txt does not contain a valid 4-decimal number: {content}"
    )

def test_bootstrap_scores_format():
    with open("/home/user/artifacts/bootstrap_scores.txt") as f:
        lines = f.read().strip().split("\n")
    assert len(lines) == 5, f"bootstrap_scores.txt must contain exactly 5 lines, found {len(lines)}."
    for line in lines:
        assert re.match(r"^-?[0-9]+\.[0-9]{4}$", line), f"Invalid score format in bootstrap_scores.txt: {line}"

def test_existing_artifacts_are_derived_from_raw_data():
    with open("/home/user/raw_data.txt") as f:
        raw = f.read()
    expected_tokenized = reference_tokenize(raw)
    with open("/home/user/artifacts/tokenized.txt") as f:
        actual_tokenized = f.read()
    assert actual_tokenized == expected_tokenized, "tokenized.txt was not derived from raw_data.txt."
    lines = expected_tokenized.splitlines()
    assert lines, "The tokenized dataset must not be empty."
    with open("/home/user/artifacts/baseline_score.txt") as f:
        baseline = f.read().strip()
    assert baseline == expected_mean(lines), "baseline_score.txt is not the mean score of tokenized.txt."

def test_tokenize_script_logic():
    input_text = "  Hello, World! This is a TEST...  \n  Another line!!!  \n"
    expected_output = "hello world this is a test\nanother line\n"
    assert run_script("/home/user/tokenize.sh", input_text) == expected_output

    nonce = secrets.token_hex(8)
    cases = [
        f"  CRITICAL!!!   Success?? {nonce}  ",
        "Error---warning   INFO; resolved.",
        "A1_b2@C3      mixed CASE and 9876",
        "punctuation: []{}()<> /\\ | += * & ^ % $ # @ !",
        "tabs\tAre\tRemoved and spaces     collapse",
    ]
    random.SystemRandom().shuffle(cases)
    dynamic_input = "\n".join(cases) + "\n"
    assert run_script("/home/user/tokenize.sh", dynamic_input) == reference_tokenize(dynamic_input)

def test_inference_script_logic():
    input_text1 = "critical error warning info success resolved unknown\n"
    assert run_script("/home/user/inference.sh", input_text1).strip() == "-3.5000"

    input_text2 = "critical error\nsuccess resolved\n"
    assert run_script("/home/user/inference.sh", input_text2).strip() == "-1.5000"

    rng = random.SystemRandom()
    vocabulary = list(WEIGHTS) + [secrets.token_hex(5), secrets.token_hex(6), "neutral"]
    lines = []
    for _ in range(13):
        lines.append(" ".join(rng.choice(vocabulary) for _ in range(rng.randint(1, 12))))
    dynamic_input = "\n".join(lines) + "\n"
    actual = run_script("/home/user/inference.sh", dynamic_input).strip()
    assert re.fullmatch(r"-?[0-9]+\.[0-9]{4}", actual), "Inference output is not formatted to four decimals."
    assert actual == expected_mean(lines), f"Incorrect dynamic inference result: {actual}"

def test_bootstrap_script_logic():
    with tempfile.NamedTemporaryFile(mode="w", delete=False) as tmp:
        for i in range(10):
            tmp.write(f"line {i}\n")
        tmp_path = tmp.name
    try:
        output_lines = run_script("/home/user/bootstrap.sh", args=(tmp_path,)).strip().split("\n")
        assert len(output_lines) == 10, "bootstrap.sh did not return the same number of lines as input."
        for line in output_lines:
            assert line.startswith("line "), "bootstrap.sh output contains invalid data."
    finally:
        os.remove(tmp_path)

    nonce = secrets.token_hex(10)
    source = [f"{nonce}-{i}-{secrets.token_hex(4)}" for i in range(17)]
    with tempfile.NamedTemporaryFile(mode="w", delete=False) as tmp:
        tmp.write("\n".join(source) + "\n")
        tmp_path = tmp.name
    try:
        observed = []
        for _ in range(6):
            lines = run_script("/home/user/bootstrap.sh", args=(tmp_path,)).splitlines()
            assert len(lines) == len(source), "Bootstrap output line count differs from its input."
            assert all(line in source for line in lines), "Bootstrap invented a line not present in its input."
            observed.append(tuple(lines))
        assert len(set(observed)) > 1, "Repeated bootstrap calls always returned the same sample."
    finally:
        os.remove(tmp_path)

def test_z_master_script_rebuilds_complete_pipeline_artifacts():
    nonce = secrets.token_hex(8)
    rows = [
        f"  CRITICAL!! error {nonce}  ",
        f"Warning... info {nonce} success",
        f"resolved RESOLVED; neutral{nonce}",
        f"error error error ({nonce})",
        f"SUCCESS + info + unknown{nonce}",
        f"critical warning resolved {nonce}",
        f"INFO info info info {nonce}",
        f"nothing weighted here 123 {nonce}",
        f"success resolved error {nonce}",
        f"warning warning warning {nonce}",
        f"critical success success {nonce}",
        f"resolved info error {nonce}",
        f"mixed: CRITICAL, resolved! success? {nonce}",
    ]
    random.SystemRandom().shuffle(rows)
    raw = "\n".join(rows) + "\n"
    with open("/home/user/raw_data.txt", "w") as f:
        f.write(raw)

    result = subprocess.run(
        ["/home/user/run_experiment.sh"], text=True, capture_output=True, timeout=30
    )
    assert result.returncode == 0, f"run_experiment.sh failed: {result.stderr}"

    expected_tokenized = reference_tokenize(raw)
    with open("/home/user/artifacts/tokenized.txt") as f:
        actual_tokenized = f.read()
    assert actual_tokenized == expected_tokenized, "Master script did not tokenize raw_data.txt correctly."

    lines = expected_tokenized.splitlines()
    with open("/home/user/artifacts/baseline_score.txt") as f:
        baseline = f.read().strip()
    assert baseline == expected_mean(lines), "Master script produced an incorrect baseline score."

    with open("/home/user/artifacts/bootstrap_scores.txt") as f:
        scores = f.read().strip().splitlines()
    assert len(scores) == 5, "Master script must replace bootstrap_scores.txt with exactly five scores."
    possible = possible_bootstrap_means(lines)
    for score in scores:
        assert re.fullmatch(r"-?[0-9]+\.[0-9]{4}", score), f"Malformed bootstrap score: {score}"
        assert score in possible, f"Bootstrap score {score} cannot come from sampling tokenized.txt with replacement."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
