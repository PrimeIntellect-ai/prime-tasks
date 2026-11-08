#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "requests:requests"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import math
import os
import py_compile
import stat
from pathlib import Path

import pytest
import requests

API_URL = "http://127.0.0.1:8555/api/dataset/sample_features"
SECRET_TOKEN = "Bearer ds-research-secret"
PIPELINE = Path("/home/user/pipeline.py")
AUDIO = "/app/audio/sample.wav"


def listener_pids(port):
    inodes = set()
    wanted = f"{port:04X}"
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) > 9 and fields[1].rsplit(":", 1)[-1].upper() == wanted and fields[3] == "0A":
                inodes.add(fields[9])

    result = set()
    for proc_dir in glob.glob("/proc/[0-9]*"):
        fd_dir = os.path.join(proc_dir, "fd")
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    result.add(int(os.path.basename(proc_dir)))
                    break
        except OSError:
            continue
    return result


def test_pipeline_artifact_is_running():
    assert PIPELINE.exists(), "/home/user/pipeline.py is missing"
    assert not PIPELINE.is_symlink(), "/home/user/pipeline.py must be a regular source file"
    assert stat.S_ISREG(PIPELINE.stat().st_mode), "/home/user/pipeline.py must be a regular file"
    assert PIPELINE.stat().st_size > 0, "/home/user/pipeline.py is empty"
    py_compile.compile(str(PIPELINE), doraise=True)

    pids = listener_pids(8555)
    assert pids, "No process is listening on TCP port 8555"
    associated = False
    for pid in pids:
        try:
            cmdline = Path(f"/proc/{pid}/cmdline").read_bytes().replace(b"\0", b" ").decode(errors="replace")
            cwd = os.readlink(f"/proc/{pid}/cwd")
        except OSError:
            continue
        if str(PIPELINE) in cmdline or ("pipeline" in cmdline and cwd == "/home/user"):
            associated = True
            break
    assert associated, "The service listening on port 8555 is not running /home/user/pipeline.py"


def test_api_unauthorized_missing_header():
    try:
        response = requests.get(API_URL, timeout=5)
    except requests.exceptions.ConnectionError:
        pytest.fail("Failed to connect to the API. Is the server running on 127.0.0.1:8555?")
    assert response.status_code in (401, 403), f"Expected 401 or 403 for missing auth, got {response.status_code}"


def test_api_unauthorized_wrong_header():
    headers = {"Authorization": "Bearer wrong-secret"}
    try:
        response = requests.get(API_URL, headers=headers, timeout=5)
    except requests.exceptions.ConnectionError:
        pytest.fail("Failed to connect to the API. Is the server running on 127.0.0.1:8555?")
    assert response.status_code in (401, 403), f"Expected 401 or 403 for wrong auth, got {response.status_code}"


def find_cached_model():
    candidates = []
    roots = [
        "/root/.cache/huggingface/hub",
        "/home/user/.cache/huggingface/hub",
        "/cache/huggingface/hub",
    ]
    for env_name in ("HF_HUB_CACHE", "HUGGINGFACE_HUB_CACHE"):
        if os.environ.get(env_name):
            roots.append(os.environ[env_name])
    if os.environ.get("HF_HOME"):
        roots.append(os.path.join(os.environ["HF_HOME"], "hub"))
    if os.environ.get("TRANSFORMERS_CACHE"):
        roots.append(os.environ["TRANSFORMERS_CACHE"])

    for root in roots:
        candidates.extend(glob.glob(os.path.join(root, "models--openai--whisper-tiny", "snapshots", "*")))
    complete = [p for p in candidates if os.path.isfile(os.path.join(p, "config.json"))]
    return max(complete, key=os.path.getmtime) if complete else "openai/whisper-tiny"


def test_api_authorized_response_structure_and_values():
    headers = {"Authorization": SECRET_TOKEN}
    try:
        response = requests.get(API_URL, headers=headers, timeout=15)
    except requests.exceptions.ConnectionError:
        pytest.fail("Failed to connect to the API. Is the server running on 127.0.0.1:8555?")

    assert response.status_code == 200, f"Expected 200 OK, got {response.status_code}. Response: {response.text}"
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON: {response.text}")

    assert "audio_stats" in data, "Missing 'audio_stats' in response"
    assert "transcription" in data, "Missing 'transcription' in response"
    assert "tokens" in data, "Missing 'tokens' in response"
    assert set(data) == {"audio_stats", "transcription", "tokens"}, "Response contains unexpected top-level keys"

    audio_stats = data["audio_stats"]
    assert isinstance(audio_stats, dict), "'audio_stats' must be a dictionary"
    assert "mean" in audio_stats, "Missing 'mean' in audio_stats"
    assert "variance" in audio_stats, "Missing 'variance' in audio_stats"
    assert "rms_mean" in audio_stats, "Missing 'rms_mean' in audio_stats"
    assert set(audio_stats) == {"mean", "variance", "rms_mean"}, "audio_stats contains unexpected keys"
    assert isinstance(audio_stats["mean"], (int, float)), "'mean' must be a number"
    assert isinstance(audio_stats["variance"], (int, float)), "'variance' must be a number"
    assert isinstance(audio_stats["rms_mean"], (int, float)), "'rms_mean' must be a number"

    assert isinstance(data["transcription"], str), "'transcription' must be a string"
    assert len(data["transcription"]) > 0, "'transcription' should not be empty"
    assert isinstance(data["tokens"], list), "'tokens' must be a list"
    assert len(data["tokens"]) > 0, "'tokens' list should not be empty"
    assert all(isinstance(t, int) for t in data["tokens"]), "All items in 'tokens' must be integers"

    import librosa
    import numpy as np
    import torch
    from transformers import WhisperForConditionalGeneration, WhisperProcessor

    native_audio, native_sr = librosa.load(AUDIO, sr=None, mono=True)
    assert native_sr > 0 and native_audio.ndim == 1
    expected_stats = {
        "mean": float(np.mean(native_audio)),
        "variance": float(np.var(native_audio)),
        "rms_mean": float(np.mean(librosa.feature.rms(y=native_audio))),
    }
    for name, expected in expected_stats.items():
        actual = float(audio_stats[name])
        assert math.isfinite(actual), f"audio_stats.{name} must be finite"
        assert np.isclose(actual, expected, rtol=2e-5, atol=1e-8), (
            f"Incorrect {name}: expected {expected}, got {actual}"
        )

    model_source = find_cached_model()
    processor = WhisperProcessor.from_pretrained(model_source)
    model = WhisperForConditionalGeneration.from_pretrained(model_source)
    model.eval()
    whisper_audio, _ = librosa.load(AUDIO, sr=16000, mono=True)
    inputs = processor(whisper_audio, sampling_rate=16000, return_tensors="pt")
    with torch.no_grad():
        generated = model.generate(inputs.input_features)
    expected_tokens = generated[0].tolist()
    expected_transcription = processor.batch_decode(generated, skip_special_tokens=True)[0]

    assert data["tokens"] == expected_tokens, f"Token IDs do not match Whisper output: expected {expected_tokens}, got {data['tokens']}"
    assert data["transcription"] == expected_transcription, (
        f"Transcription does not match decoded Whisper output: expected {expected_transcription!r}, got {data['transcription']!r}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
