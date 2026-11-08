#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import os
import pathlib
import pwd
import subprocess
import tarfile
import uuid

import pytest


def calculate_wer(reference: str, hypothesis: str) -> float:
    ref_words = reference.lower().split()
    hyp_words = hypothesis.lower().split()

    d = [[0] * (len(hyp_words) + 1) for _ in range(len(ref_words) + 1)]
    for i in range(len(ref_words) + 1):
        d[i][0] = i
    for j in range(len(hyp_words) + 1):
        d[0][j] = j

    for i in range(1, len(ref_words) + 1):
        for j in range(1, len(hyp_words) + 1):
            cost = 0 if ref_words[i - 1] == hyp_words[j - 1] else 1
            d[i][j] = min(
                d[i - 1][j] + 1,
                d[i][j - 1] + 1,
                d[i - 1][j - 1] + cost,
            )

    if len(ref_words) == 0:
        return float("inf")
    return d[len(ref_words)][len(hyp_words)] / float(len(ref_words))


def run_as_user(command, **kwargs):
    account = pwd.getpwnam("user")

    def demote():
        os.setgroups([])
        os.setgid(account.pw_gid)
        os.setuid(account.pw_uid)

    env = os.environ.copy()
    env["HOME"] = account.pw_dir
    env["USER"] = account.pw_name
    env["LOGNAME"] = account.pw_name
    kwargs.setdefault("env", env)
    kwargs.setdefault("preexec_fn", demote)
    return subprocess.run(command, **kwargs)


def test_skipped_log_exists_and_contains_malicious_path():
    log_path = "/home/user/skipped.log"
    assert os.path.exists(log_path), f"The log file '{log_path}' does not exist. Did the Rust tool log skipped files?"
    assert os.path.isfile(log_path), f"'{log_path}' is not a file."

    with open(log_path, "r") as f:
        content = f.read()

    assert "../malicious_overwrite.sh" in content, (
        f"The log file '{log_path}' does not contain the expected malicious path '../malicious_overwrite.sh'. "
        "Ensure your tool detects and logs escaping paths."
    )


def test_transcript_wer_metric():
    transcript_path = "/home/user/transcript.txt"
    assert os.path.exists(transcript_path), f"The transcript file '{transcript_path}' does not exist."
    assert os.path.isfile(transcript_path), f"'{transcript_path}' is not a file."

    with open(transcript_path, "r") as f:
        transcript = f.read().strip()

    ground_truth = "Administrator log day forty two. The incremental backup stream has been corrupted by a path traversal payload. Manual extraction is required."
    wer = calculate_wer(ground_truth, transcript)
    threshold = 0.15

    assert wer <= threshold, (
        f"Word Error Rate (WER) is too high. Expected <= {threshold}, got {wer:.4f}. "
        f"Transcript was: '{transcript}'"
    )


def test_original_archive_was_safely_recovered():
    target = pathlib.Path("/home/user/extracted")
    assert target.is_dir(), "The required extraction target does not exist."

    with tarfile.open("/app/backup.tar.gz", "r:gz") as archive:
        for member_name in ("voicemail.wav", "backup_meta.json"):
            expected_file = archive.extractfile(member_name)
            assert expected_file is not None
            expected = expected_file.read()
            recovered = target / member_name
            assert recovered.is_file(), f"Safe archive member {member_name!r} was not extracted."
            assert recovered.read_bytes() == expected, f"Extracted {member_name!r} does not match the archive."

    assert not pathlib.Path("/home/user/malicious_overwrite.sh").exists(), (
        "The traversal payload escaped /home/user/extracted."
    )


def test_rust_project_builds_and_extractor_handles_fresh_archive():
    project = pathlib.Path("/home/user/extractor")
    manifest = project / "Cargo.toml"
    assert project.is_dir(), "The Rust project directory /home/user/extractor is missing."
    assert manifest.is_file(), "The Rust project has no Cargo.toml."
    assert any(p.is_file() for p in (project / "src").glob("**/*.rs")), "The project has no Rust source files."

    metadata_result = run_as_user(
        ["cargo", "metadata", "--format-version", "1", "--no-deps", "--manifest-path", str(manifest)],
        cwd=str(project), text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=120,
    )
    assert metadata_result.returncode == 0, f"Cargo metadata failed:\n{metadata_result.stderr}"
    metadata = json.loads(metadata_result.stdout)
    root_id = metadata.get("resolve", {}).get("root")
    package = next((p for p in metadata["packages"] if p["id"] == root_id), None)
    if package is None:
        manifest_real = manifest.resolve()
        package = next(
            (p for p in metadata["packages"] if pathlib.Path(p["manifest_path"]).resolve() == manifest_real),
            None,
        )
    assert package is not None, "Could not identify the extractor Cargo package."

    bin_targets = [t["name"] for t in package["targets"] if "bin" in t.get("kind", [])]
    assert bin_targets, "The Cargo package does not define an executable binary."
    default_bin = package.get("default_run")
    if default_bin:
        assert default_bin in bin_targets, "Cargo default-run does not name a binary target."
        bin_name = default_bin
    else:
        assert len(bin_targets) == 1, "Multiple binaries are present but no default-run extractor is specified."
        bin_name = bin_targets[0]

    build = run_as_user(
        ["cargo", "build", "--manifest-path", str(manifest), "--bin", bin_name, "--message-format=json"],
        cwd=str(project), text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=240,
    )
    assert build.returncode == 0, f"The Rust extractor does not compile:\n{build.stderr}"

    executable = None
    for line in build.stdout.splitlines():
        try:
            message = json.loads(line)
        except json.JSONDecodeError:
            continue
        if message.get("reason") == "compiler-artifact" and message.get("target", {}).get("name") == bin_name:
            candidate = message.get("executable")
            if candidate:
                executable = candidate
    assert executable and os.path.isfile(executable), "Cargo did not produce the extractor executable."
    assert os.access(executable, os.X_OK), "The compiled extractor is not executable."

    token = uuid.uuid4().hex
    work = pathlib.Path("/home/user") / (".verifier_extract_" + token)
    target = work / "target"
    archive_path = work / "challenge.tar.gz"
    work.mkdir(mode=0o777)
    target.mkdir(mode=0o777)

    safe_top = f"safe_{token}.txt"
    safe_nested = f"nested_{token}/payload.bin"
    safe_top_data = ("top-" + token).encode()
    safe_nested_data = hashlib.sha256(token.encode()).digest()
    traversal_name = f"../escape_{token}.txt"
    absolute_path = pathlib.Path("/home/user") / (".absolute_escape_" + token)
    absolute_name = str(absolute_path)
    traversal_path = work / f"escape_{token}.txt"
    canary = ("unchanged-" + token).encode()
    traversal_path.write_bytes(canary)
    absolute_path.write_bytes(canary)
    os.chmod(traversal_path, 0o666)
    os.chmod(absolute_path, 0o666)

    import io
    with tarfile.open(archive_path, "w:gz") as archive:
        for name, data in (
            (safe_top, safe_top_data),
            (safe_nested, safe_nested_data),
            (traversal_name, b"TRAVERSAL-WROTE"),
            (absolute_name, b"ABSOLUTE-WROTE"),
        ):
            info = tarfile.TarInfo(name)
            info.size = len(data)
            info.mode = 0o644
            archive.addfile(info, io.BytesIO(data))
    os.chmod(archive_path, 0o644)

    result = run_as_user(
        [executable, str(archive_path), str(target)],
        cwd=str(project), text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=120,
    )
    assert result.returncode == 0, (
        f"The compiled extractor failed on a valid tar.gz archive.\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )

    assert (target / safe_top).is_file()
    assert (target / safe_top).read_bytes() == safe_top_data
    assert (target / safe_nested).is_file()
    assert (target / safe_nested).read_bytes() == safe_nested_data
    assert safe_top in result.stdout, "The extractor did not print a safely extracted filename."
    assert safe_nested in result.stdout, "The extractor did not print a safely extracted nested filename."

    assert traversal_path.read_bytes() == canary, "A '..' archive path overwrote a file outside the target."
    assert absolute_path.read_bytes() == canary, "An absolute archive path overwrote a file outside the target."

    log_lines = pathlib.Path("/home/user/skipped.log").read_text().splitlines()
    assert traversal_name in log_lines, "The fresh traversal path was not logged exactly."
    assert absolute_name in log_lines, "The fresh absolute path was not logged exactly."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
