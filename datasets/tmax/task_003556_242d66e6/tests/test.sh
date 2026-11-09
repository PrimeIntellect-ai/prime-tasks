#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import difflib
import hashlib
import json
import os
import re
import secrets
import shutil
import stat
import subprocess
import sys
import tempfile
from pathlib import Path

import pytest

REPO = Path("/home/user/iot_ingest.git")
SCRIPT = Path("/home/user/process_audio.py")
LOG = Path("/home/user/ingest.log")
AUDIO = Path("/app/device_audio.wav")


def run(cmd, **kwargs):
    return subprocess.run(cmd, text=True, capture_output=True, check=True, **kwargs)


def sha256(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def test_ingest_log_metric():
    """Retain the original transcript similarity assertion."""
    assert LOG.exists(), f"Expected log file {LOG} does not exist. Did the git hook run successfully?"

    content = LOG.read_text().strip()
    match = re.search(r"Transcript:\s*(.*)", content)
    assert match is not None, "Could not find 'Transcript: <text>' in ingest.log. Ensure the git hook writes strictly in the requested format."

    actual = match.group(1).lower().strip()
    actual_clean = re.sub(r"[^a-z0-9\s]", "", actual)
    expected_clean = re.sub(r"[^a-z0-9\s]", "", "the temperature sensor on unit four is malfunctioning")
    score = difflib.SequenceMatcher(None, expected_clean, actual_clean).ratio()
    assert score >= 0.80, f"Transcript similarity score {score:.3f} is below the 0.80 threshold. Actual transcript extracted: '{actual}'"


def test_owner_extracted_correctly():
    """Retain the original owner assertion."""
    if not LOG.exists():
        pytest.fail(f"Expected log file {LOG} does not exist.")
    content = LOG.read_text().strip()
    assert "Owner: edge_device_alpha" in content, "The correct owner 'edge_device_alpha' was not found in ingest.log. Ensure the git hook extracts it properly."


def test_bare_repo_exists():
    """Retain the original bare-repository assertions and validate it with Git."""
    assert REPO.is_dir(), f"Bare repository directory {REPO} does not exist."
    config = REPO / "config"
    assert config.exists(), "Repository does not appear to be initialized."
    config_content = config.read_text()
    assert "bare = true" in config_content.lower(), f"Repository at {REPO} is not configured as a bare repository."

    result = run(["git", "-c", "safe.directory=*", "--git-dir", str(REPO), "rev-parse", "--is-bare-repository"])
    assert result.stdout.strip() == "true"


def test_python_script_exists():
    """Retain the original script-existence assertion."""
    assert SCRIPT.is_file(), f"Python script {SCRIPT} does not exist."


def test_requested_initial_clone_commit_and_push_exist():
    clone = Path("/home/user/test_clone")
    assert (clone / ".git").is_dir(), "The required /home/user/test_clone Git clone is missing."
    assert (clone / "audio.wav").is_file()
    assert sha256(clone / "audio.wav") == sha256(AUDIO)
    assert (clone / "metadata.txt").read_text() == (
        "device_id: 104\n"
        "owner: edge_device_alpha\n"
        "priority: high\n"
    )

    tracked = set(run(["git", "-c", "safe.directory=*", "-C", str(clone), "ls-files"]).stdout.splitlines())
    assert {"audio.wav", "metadata.txt"}.issubset(tracked), "The audio and metadata were not committed."
    origin = run(["git", "-c", "safe.directory=*", "-C", str(clone), "remote", "get-url", "origin"]).stdout.strip()
    assert Path(origin).resolve() == REPO.resolve(), "test_clone does not use the required bare repository as origin."
    clone_master = run(["git", "-c", "safe.directory=*", "-C", str(clone), "rev-parse", "master"]).stdout.strip()
    bare_master = run(["git", "-c", "safe.directory=*", "--git-dir", str(REPO), "rev-parse", "refs/heads/master"]).stdout.strip()
    assert clone_master == bare_master, "The required master commit was not pushed to the bare repository."


def test_process_audio_uses_whisper_tiny_and_prints_transcription_only(tmp_path):
    """Execute the submitted script against a randomized fake Whisper API."""
    token = "recognized_" + secrets.token_hex(12)
    calls = tmp_path / "whisper_calls.jsonl"
    fake_module = tmp_path / "whisper.py"
    fake_module.write_text(
        "import json, os\n"
        "def _record(value):\n"
        "    with open(os.environ['WHISPER_CALLS'], 'a') as f:\n"
        "        f.write(json.dumps(value) + '\\n')\n"
        "class Model:\n"
        "    def transcribe(self, path, *args, **kwargs):\n"
        "        _record({'event':'transcribe','path':path,'args':args,'kwargs':kwargs})\n"
        "        return {'text': os.environ['WHISPER_TOKEN']}\n"
        "def load_model(name, *args, **kwargs):\n"
        "    _record({'event':'load_model','name':name,'args':args,'kwargs':kwargs})\n"
        "    return Model()\n"
    )
    test_audio = tmp_path / ("input_" + secrets.token_hex(8) + ".wav")
    shutil.copy2(AUDIO, test_audio)

    env = os.environ.copy()
    env["PYTHONPATH"] = str(tmp_path)
    env["WHISPER_CALLS"] = str(calls)
    env["WHISPER_TOKEN"] = token
    proc = subprocess.run(
        [sys.executable, "-c", "import runpy; runpy.run_path('/home/user/process_audio.py', run_name='__main__')", str(test_audio)],
        cwd=tmp_path,
        env=env,
        text=True,
        capture_output=True,
        timeout=60,
    )
    assert proc.returncode == 0, f"process_audio.py failed: {proc.stderr}"
    assert proc.stdout == token + "\n", "process_audio.py must print only the recognized text to stdout."

    events = [json.loads(line) for line in calls.read_text().splitlines()]
    loads = [event for event in events if event.get("event") == "load_model"]
    transcribes = [event for event in events if event.get("event") == "transcribe"]
    assert len(loads) == 1 and loads[0]["name"] == "tiny", "The script must load Whisper's tiny model."
    assert len(transcribes) == 1, "The script must transcribe the WAV argument exactly once."
    assert Path(transcribes[0]["path"]).resolve() == test_audio.resolve(), "The command-line WAV path was not passed to Whisper."


def test_post_receive_hook_executes_pipeline_on_new_push(tmp_path):
    hook = REPO / "hooks" / "post-receive"
    assert hook.is_file(), "The post-receive hook is missing."
    assert os.access(hook, os.X_OK), "The post-receive hook is not executable."

    owner = "device_" + secrets.token_hex(10)
    transcript = "hook_transcript_" + secrets.token_hex(10)
    marker = tmp_path / "process_invocations.jsonl"
    original_script = SCRIPT.read_bytes()
    original_mode = stat.S_IMODE(SCRIPT.stat().st_mode)
    before_lines = LOG.read_text().splitlines()

    wrapper = f'''#!/usr/bin/env python3
import hashlib
import json
import sys
p = sys.argv[1]
with open({str(marker)!r}, "a") as f:
    f.write(json.dumps({{"path": p, "sha256": hashlib.sha256(open(p, "rb").read()).hexdigest()}}) + "\\n")
print({transcript!r})
'''

    try:
        SCRIPT.write_text(wrapper)
        SCRIPT.chmod(0o755)

        clone = tmp_path / "dynamic_clone"
        run(["git", "-c", "safe.directory=*", "clone", str(REPO), str(clone)])
        shutil.copy2(AUDIO, clone / "audio.wav")
        metadata = f"device_id: {secrets.randbelow(900000) + 100000}\nowner: {owner}\npriority: high\n"
        (clone / "metadata.txt").write_text(metadata)
        run(["git", "-C", str(clone), "config", "user.email", "verifier@example.invalid"])
        run(["git", "-C", str(clone), "config", "user.name", "Pipeline Verifier"])
        run(["git", "-C", str(clone), "add", "audio.wav", "metadata.txt"])
        run(["git", "-C", str(clone), "commit", "-m", "dynamic verifier push"])
        run(["git", "-c", "safe.directory=*", "-C", str(clone), "push", "origin", "HEAD:master"])

        pushed = run(["git", "-C", str(clone), "rev-parse", "HEAD"]).stdout.strip()
        received = run(["git", "-c", "safe.directory=*", "--git-dir", str(REPO), "rev-parse", "refs/heads/master"]).stdout.strip()
        assert pushed == received

        latest = Path("/home/user/latest_push")
        assert (latest / "metadata.txt").read_text() == metadata, "The newly pushed tree was not extracted to latest_push."
        assert sha256(latest / "audio.wav") == sha256(AUDIO), "latest_push/audio.wav is not the pushed audio."

        invocations = [json.loads(line) for line in marker.read_text().splitlines()]
        assert len(invocations) == 1, "The hook must invoke /home/user/process_audio.py once for this push."
        assert Path(invocations[0]["path"]).resolve() == (latest / "audio.wav").resolve()
        assert invocations[0]["sha256"] == sha256(AUDIO)

        after_lines = LOG.read_text().splitlines()
        assert len(after_lines) == len(before_lines) + 1, "The hook must append exactly one log line per push."
        assert after_lines[-1] == f"Owner: {owner} | Transcript: {transcript}", "The appended line has the wrong owner, transcript, or format."
    finally:
        SCRIPT.write_bytes(original_script)
        SCRIPT.chmod(original_mode)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
