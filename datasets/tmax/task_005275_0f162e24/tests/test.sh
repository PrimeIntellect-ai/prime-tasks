#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import importlib.metadata
import importlib.util
import json
import os
import random
import subprocess
import sys

import pytest

CORE_PATH = "/app/vendor/log_extractor-1.0/log_extractor/core.py"
AGENT_SCRIPT = "/home/user/analyzer.py"
LOG_FILE = "/home/user/pipeline.log"
MARKERS = ["🚨", "CRÍTICO", "严重", "KRITISCH"]


def load_source_core():
    spec = importlib.util.spec_from_file_location("submitted_log_extractor_core", CORE_PATH)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_core_py_fixed():
    assert os.path.isfile(CORE_PATH), f"File {CORE_PATH} is missing."
    with open(CORE_PATH, "r", encoding="utf-8") as f:
        content = f.read()
    assert "utf-8" in content.lower() or "utf8" in content.lower(), "The bug in core.py does not appear to be fixed to decode as utf-8."

    core = load_source_core()
    samples = ["こんにちは", "Café 严重", "مرحبا 🚨", "é"]
    for sample in samples:
        assert core.parse_log(sample.encode("utf-8")) == sample


def test_package_installed_and_working():
    assert importlib.metadata.version("log_extractor") == "1.0"
    code = (
        "import log_extractor; "
        "s='Zażółć gęślą jaźń 世界 🚨'; "
        "assert log_extractor.parse_log(s.encode('utf-8')) == s"
    )
    proc = subprocess.run(
        [sys.executable, "-c", code],
        cwd="/tmp",
        text=True,
        capture_output=True,
        env={k: v for k, v in os.environ.items() if k != "PYTHONPATH"},
    )
    assert proc.returncode == 0, f"Installed log_extractor is unavailable or broken: {proc.stderr}"


def run_agent(uid, text, env=None):
    raw_b64 = base64.b64encode(text.encode("utf-8")).decode("ascii")
    input_data = json.dumps({"uid": uid, "raw_b64": raw_b64})
    proc = subprocess.run(
        [sys.executable, AGENT_SCRIPT],
        input=input_data,
        text=True,
        capture_output=True,
        cwd="/tmp",
        env=env,
    )
    assert proc.returncode == 0, f"Agent script failed on input {input_data}\nStderr: {proc.stderr}"
    try:
        result = json.loads(proc.stdout.strip())
    except json.JSONDecodeError:
        pytest.fail(f"Agent did not output one valid JSON object. Output: {proc.stdout!r}")
    assert isinstance(result, dict)
    assert list(result.keys()) == ["uid", "message_length", "is_anomaly"]
    assert type(result["uid"]) is int
    assert type(result["message_length"]) is int
    assert type(result["is_anomaly"]) is bool
    return result


def test_analyzer_uses_log_extractor(tmp_path):
    assert os.path.isfile(AGENT_SCRIPT), f"Agent script {AGENT_SCRIPT} missing."
    package_dir = tmp_path / "log_extractor"
    package_dir.mkdir()
    (package_dir / "__init__.py").write_text(
        "def parse_log(log_bytes):\n"
        "    assert log_bytes == b'probe-input'\n"
        "    return '🚨PROBED'\n",
        encoding="utf-8",
    )
    env = os.environ.copy()
    env["PYTHONPATH"] = str(tmp_path)
    result = run_agent(731946, "probe-input", env=env)
    assert result == {"uid": 731946, "message_length": 7, "is_anomaly": True}


def random_text(rng):
    units = [
        "a", "Z", " ", "0", "é", "ñ", "ß", "ø", "Ж", "λ", "א", "م",
        "你", "界", "日", "本", "한", "글", "🙂", "🌍", "⚠️", "é",
        "normal", "crítico", "kritisch", "严 重", "\n", "\t",
    ]
    text = "".join(rng.choice(units) for _ in range(rng.randrange(0, 45)))
    mode = rng.randrange(4)
    if mode == 0:
        marker = rng.choice(MARKERS)
        position = rng.randrange(len(text) + 1)
        text = text[:position] + marker + text[position:]
    elif mode == 1:
        text += rng.choice(["🚨", "CRÍTICO", "严重", "KRITISCH"])
    return text


def test_fuzz_equivalence_and_logging():
    assert os.path.isfile(AGENT_SCRIPT), f"Agent script {AGENT_SCRIPT} missing."
    if os.path.exists(LOG_FILE):
        os.remove(LOG_FILE)

    rng = random.SystemRandom()
    texts = [
        "",
        "System normal",
        "こんにちは",
        "CRÍTICO: database failure",
        "Disk space 严重 low",
        "KRITISCH: overload",
        "Warning 🚨",
        "CRITICO and 严 重 are not exact markers",
        "👨‍👩‍👧‍👦 combining é text",
    ]
    while len(texts) < 100:
        texts.append(random_text(rng))

    expected_lines = []
    for text in texts:
        uid = rng.randrange(-10**12, 10**12)
        expected = {
            "uid": uid,
            "message_length": len(text),
            "is_anomaly": any(marker in text for marker in MARKERS),
        }
        assert run_agent(uid, text) == expected
        expected_lines.append(f"[INFO] Processed uid {uid}")

    assert os.path.isfile(LOG_FILE), f"Pipeline log {LOG_FILE} was not created."
    with open(LOG_FILE, "r", encoding="utf-8") as f:
        log_lines = f.read().splitlines()
    assert log_lines == expected_lines
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
