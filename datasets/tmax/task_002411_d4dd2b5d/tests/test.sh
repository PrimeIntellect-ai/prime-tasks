#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "yaml:pyyaml"; do
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
import json
import os
import re
import secrets
import shlex
import shutil
import subprocess
import tempfile

import pytest
import yaml

WAV_PATH = "/app/recording.wav"
OPUS_PATH = "/home/user/recording.opus"
SCRIPT_PATH = "/home/user/setup_node.sh"
GROUND_TRUTH = "Please configure the new transcription nodes with exactly 512 megabytes of RAM and a 5 gigabyte disk. Also, ensure that the SSH daemon is configured to disable public key authentication so it silently rejects key-based login, relying entirely on secure passwords."


def normalized_words(text):
    return re.findall(r"[a-z0-9]+", text.lower())


def word_error_rate(reference, hypothesis):
    ref = normalized_words(reference)
    hyp = normalized_words(hypothesis)
    assert ref, "Ground-truth transcript is empty."
    previous = list(range(len(hyp) + 1))
    for i, ref_word in enumerate(ref, 1):
        current = [i]
        for j, hyp_word in enumerate(hyp, 1):
            current.append(min(
                current[-1] + 1,
                previous[j] + 1,
                previous[j - 1] + (ref_word != hyp_word),
            ))
        previous = current
    return previous[-1] / len(ref)


def test_audio_compression():
    assert os.path.exists(WAV_PATH), f"Original audio file {WAV_PATH} is missing."
    assert os.path.exists(OPUS_PATH), f"Compressed audio file {OPUS_PATH} is missing."

    wav_size = os.path.getsize(WAV_PATH)
    opus_size = os.path.getsize(OPUS_PATH)
    size_ratio = opus_size / wav_size
    assert size_ratio <= 0.10, f"Size ratio {size_ratio:.3f} exceeds threshold 0.10."

    result = subprocess.run(
        ["ffprobe", "-v", "error", "-show_entries", "format=format_name",
         "-of", "default=noprint_wrappers=1:nokey=1", OPUS_PATH],
        capture_output=True, text=True, check=True,
    )
    format_name = result.stdout.strip()
    assert "ogg" in format_name.lower(), f"File is not in Ogg format, detected format: {format_name}"

    stream = subprocess.run(
        ["ffprobe", "-v", "error", "-select_streams", "a:0",
         "-show_entries", "stream=codec_name", "-of",
         "default=noprint_wrappers=1:nokey=1", OPUS_PATH],
        capture_output=True, text=True, check=True,
    )
    assert stream.stdout.strip().lower() == "opus", "The Ogg file does not contain an Opus audio stream."


def assert_active_pubkey_rule(user_data_path):
    with open(user_data_path, "r", encoding="utf-8") as handle:
        content = handle.read()

    # Preserve the original assertion.
    assert re.search(r"PubkeyAuthentication\s+no", content, re.IGNORECASE), \
        "Cloud-init user-data does not contain 'PubkeyAuthentication no'."

    try:
        document = yaml.safe_load(content)
    except yaml.YAMLError as exc:
        pytest.fail(f"Cloud-init user-data is not valid YAML: {exc}")
    assert isinstance(document, dict), "Cloud-init user-data is not a cloud-config mapping."

    configured = False
    write_files = document.get("write_files", [])
    if isinstance(write_files, list):
        for entry in write_files:
            if not isinstance(entry, dict):
                continue
            path = str(entry.get("path", ""))
            body = str(entry.get("content", ""))
            active_lines = [line for line in body.splitlines() if not line.lstrip().startswith("#")]
            if path.startswith("/etc/ssh/") and any(
                re.fullmatch(r"\s*PubkeyAuthentication\s+no\s*", line, re.IGNORECASE)
                for line in active_lines
            ):
                configured = True

    # Also accept a cloud-init command that explicitly writes the rule into sshd configuration.
    for section in ("bootcmd", "runcmd"):
        commands = document.get(section, [])
        if not isinstance(commands, list):
            continue
        for command in commands:
            if isinstance(command, list):
                command = " ".join(str(part) for part in command)
            else:
                command = str(command)
            if (re.search(r"PubkeyAuthentication\s+no", command, re.IGNORECASE)
                    and re.search(r"/etc/ssh/(?:sshd_config|sshd_config\.d/)", command)
                    and re.search(r"\b(?:sed|printf|echo|tee|install)\b", command)):
                configured = True

    assert configured, (
        "The user-data mentions the SSH rule but does not configure it through an SSH "
        "configuration file or a cloud-init command."
    )


def assert_qemu_output(stdout, instance_name):
    # Preserve the original stdout assertions.
    assert "qemu-system-x86_64" in stdout, "stdout missing 'qemu-system-x86_64'"
    assert "-m 512" in stdout or "-m 512M" in stdout, \
        "stdout missing RAM specification (-m 512 or -m 512M)"
    assert "-nographic" in stdout, "stdout missing '-nographic'"
    assert f"{instance_name}.qcow2" in stdout, \
        f"stdout missing disk image '{instance_name}.qcow2'"

    command_line = next(
        (line.strip() for line in stdout.splitlines() if "qemu-system-x86_64" in line), None
    )
    assert command_line, "No QEMU command line was printed."
    try:
        tokens = shlex.split(command_line)
    except ValueError as exc:
        pytest.fail(f"Printed QEMU command is not valid shell syntax: {exc}")
    assert os.path.basename(tokens[0]) == "qemu-system-x86_64", \
        "Printed line does not invoke qemu-system-x86_64."
    assert "-nographic" in tokens, "Printed QEMU command is not headless."
    assert any(f"{instance_name}.qcow2" in token for token in tokens), \
        "Printed QEMU command does not use the generated disk image."


def run_and_validate(instance_name, cwd, env=None):
    result = subprocess.run(
        [SCRIPT_PATH, instance_name], capture_output=True, text=True,
        cwd=cwd, env=env, timeout=60,
    )
    assert result.returncode == 0, \
        f"Script exited with non-zero code {result.returncode}. stderr: {result.stderr}"

    qcow2_path = os.path.join(cwd, f"{instance_name}.qcow2")
    user_data_path = os.path.join(cwd, f"{instance_name}_user-data")
    assert os.path.exists(qcow2_path), f"Disk image {instance_name}.qcow2 was not created."
    assert os.path.exists(user_data_path), f"Cloud-init file {instance_name}_user-data was not created."

    info_result = subprocess.run(
        ["qemu-img", "info", "--output=json", qcow2_path],
        capture_output=True, text=True, check=True,
    )
    info = json.loads(info_result.stdout)
    virtual_size = info.get("virtual-size", 0)
    assert virtual_size == 5368709120, \
        f"Virtual size of {instance_name}.qcow2 is {virtual_size}, expected 5368709120 (5G)."

    assert_active_pubkey_rule(user_data_path)
    assert_qemu_output(result.stdout, instance_name)


def test_setup_node_script():
    assert os.path.exists(SCRIPT_PATH), f"Script {SCRIPT_PATH} is missing."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable."

    # Preserve the original fixed-name execution and assertions.
    fixed_name = "node-01"
    for suffix in (".qcow2", "_user-data"):
        path = os.path.join("/home/user", fixed_name + suffix)
        if os.path.exists(path):
            os.remove(path)
    run_and_validate(fixed_name, "/home/user")

    # Exercise argument handling with an unpredictable name and observe the exported
    # variable in qemu-img, a child process of the submitted script.
    dynamic_name = "verify-" + secrets.token_hex(6)
    real_qemu_img = shutil.which("qemu-img")
    assert real_qemu_img, "qemu-img is unavailable."
    with tempfile.TemporaryDirectory() as workdir, tempfile.TemporaryDirectory() as bindir:
        env_log = os.path.join(workdir, "observed_vm_name")
        wrapper = os.path.join(bindir, "qemu-img")
        with open(wrapper, "w", encoding="utf-8") as handle:
            handle.write(
                "#!/bin/sh\n"
                f"printf '%s' \"$QEMU_VM_NAME\" > {shlex.quote(env_log)}\n"
                f"exec {shlex.quote(real_qemu_img)} \"$@\"\n"
            )
        os.chmod(wrapper, 0o755)
        env = os.environ.copy()
        env["PATH"] = bindir + os.pathsep + env.get("PATH", "")
        run_and_validate(dynamic_name, workdir, env)
        assert os.path.exists(env_log), "The script did not invoke qemu-img to create the disk."
        with open(env_log, "r", encoding="utf-8") as handle:
            observed_name = handle.read()
        assert observed_name == dynamic_name, \
            f"QEMU_VM_NAME was {observed_name!r}, expected {dynamic_name!r}."


def test_whisper_wer():
    assert os.path.exists(OPUS_PATH), f"Compressed audio file {OPUS_PATH} is missing."
    from faster_whisper import WhisperModel

    model = WhisperModel(
        "tiny.en", device="cpu", compute_type="int8",
        download_root="/opt/whisper-models", local_files_only=True,
    )
    segments, _ = model.transcribe(
        OPUS_PATH, language="en", beam_size=5, vad_filter=False,
        condition_on_previous_text=False,
    )
    transcript = " ".join(segment.text.strip() for segment in segments).strip()
    assert transcript, "Whisper produced an empty transcript."
    wer = word_error_rate(GROUND_TRUTH, transcript)
    assert wer <= 0.15, f"Whisper WER {wer:.3f} exceeds threshold 0.15. Transcript: {transcript!r}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
