#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import stat
import subprocess
import tarfile
import uuid

import pytest


def test_archive_tool_fixed():
    script_path = "/app/bash-archive-tool-1.0.0/archive.sh"
    assert os.path.isfile(script_path), f"Script {script_path} is missing."

    st = os.stat(script_path)
    assert bool(st.st_mode & (stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)), f"Script {script_path} is not executable."

    output_archive = "/tmp/test_archive.tar.gz"
    input_dir = "/app/corpus/clean/"

    if os.path.exists(output_archive):
        os.remove(output_archive)

    result = subprocess.run([script_path, output_archive, input_dir], capture_output=True, text=True)
    assert result.returncode == 0, f"Archive script failed with return code {result.returncode}.\nStderr: {result.stderr}"
    assert os.path.isfile(output_archive), f"Archive script did not create the output archive at {output_archive}."

    try:
        with tarfile.open(output_archive, "r:gz") as tar:
            members = tar.getnames()
            assert len(members) > 0, "Archive is empty."
    except tarfile.ReadError:
        pytest.fail(f"Archive {output_archive} is not a valid gzip-compressed tar archive.")


def test_archive_contains_requested_dynamic_directory(tmp_path):
    script_path = "/app/bash-archive-tool-1.0.0/archive.sh"
    source_name = "source-" + uuid.uuid4().hex
    source = tmp_path / source_name
    (source / "nested").mkdir(parents=True)
    (source / "empty").mkdir()

    expected_files = {
        f"{source_name}/alpha-{uuid.uuid4().hex}.log": secrets.token_bytes(257),
        f"{source_name}/nested/beta-{uuid.uuid4().hex}.log": secrets.token_bytes(1025),
        f"{source_name}/nested/empty-{uuid.uuid4().hex}.log": b"",
    }
    for archive_name, content in expected_files.items():
        relative = archive_name.split("/", 1)[1]
        path = source / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(content)

    output_archive = tmp_path / ("result-" + uuid.uuid4().hex + ".tar.gz")
    result = subprocess.run(
        [script_path, str(output_archive), source_name],
        cwd=tmp_path,
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, f"Archive script failed with return code {result.returncode}.\nStderr: {result.stderr}"
    assert output_archive.is_file(), "Archive script did not create the requested output archive."

    try:
        with tarfile.open(output_archive, "r:gz") as tar:
            members = tar.getmembers()
            normalized = {m.name.removeprefix("./"): m for m in members}
            archived_files = {}
            for name, member in normalized.items():
                assert not name.startswith("/"), "Archive unexpectedly contains an absolute path."
                assert ".." not in name.split("/"), "Archive unexpectedly contains a parent traversal path."
                if member.isfile():
                    stream = tar.extractfile(member)
                    assert stream is not None
                    archived_files[name] = stream.read()

            assert archived_files == expected_files, (
                "Archive does not contain exactly the files and contents from the requested input directory."
            )
            directory_names = {name.rstrip("/") for name, member in normalized.items() if member.isdir()}
            assert source_name in directory_names
            assert f"{source_name}/nested" in directory_names
            assert f"{source_name}/empty" in directory_names
    except tarfile.ReadError:
        pytest.fail(f"Archive {output_archive} is not a valid gzip-compressed tar archive.")


def test_classifier_adversarial_corpus():
    classifier_path = "/home/user/classifier.sh"
    assert os.path.isfile(classifier_path), f"Classifier script missing at {classifier_path}"

    st = os.stat(classifier_path)
    assert bool(st.st_mode & (stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)), f"Classifier {classifier_path} is not executable."

    evil_dir = "/app/corpus/evil/"
    clean_dir = "/app/corpus/clean/"

    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if os.path.isfile(os.path.join(evil_dir, f))]
    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if os.path.isfile(os.path.join(clean_dir, f))]

    bypassed_evil = []
    modified_clean = []

    for f in evil_files:
        result = subprocess.run([classifier_path, f], capture_output=True, text=True)
        out = result.stdout.strip()
        if result.returncode != 1 or out != "EVIL":
            bypassed_evil.append(os.path.basename(f))

    for f in clean_files:
        result = subprocess.run([classifier_path, f], capture_output=True, text=True)
        out = result.stdout.strip()
        if result.returncode != 0 or out != "CLEAN":
            modified_clean.append(os.path.basename(f))

    errors = []
    if bypassed_evil:
        errors.append(f"{len(bypassed_evil)} of {len(evil_files)} evil bypassed: {', '.join(bypassed_evil)}")
    if modified_clean:
        errors.append(f"{len(modified_clean)} of {len(clean_files)} clean modified (rejected): {', '.join(modified_clean)}")

    if errors:
        pytest.fail(" | ".join(errors))


def test_classifier_dynamic_content(tmp_path):
    classifier_path = "/home/user/classifier.sh"

    def random_card():
        return "-".join("".join(secrets.choice("0123456789") for _ in range(4)) for _ in range(4))

    cases = [
        (b"ordinary application message\n", 0, "CLEAN"),
        (b"prefix [MALICIOUS_INJECTION] suffix\n", 1, "EVIL"),
        (("purchase=" + random_card() + " completed\n").encode(), 1, "EVIL"),
        (("first line\n" + "x" * 131072 + "\nlate card " + random_card()).encode(), 1, "EVIL"),
        (("x" * 131072 + "\n[MALICIOUS_INJECTION]").encode(), 1, "EVIL"),
        (b"near misses: 1234-5678-9012-345 and 1234 5678 9012 3456\n", 0, "CLEAN"),
        (b"near misses: [MALICIOUS-INJECTION] and [MALICIOUS_INJECTION\n", 0, "CLEAN"),
        (b"digits without required separators: 1234567890123456\n", 0, "CLEAN"),
        (("several lines\ncard-like " + random_card()[:-1] + "X\nall safe").encode(), 0, "CLEAN"),
    ]
    secrets.SystemRandom().shuffle(cases)

    failures = []
    for content, expected_status, expected_output in cases:
        path = tmp_path / ("log-" + uuid.uuid4().hex + ".data")
        path.write_bytes(content)
        result = subprocess.run([classifier_path, str(path)], capture_output=True, text=True)
        if result.returncode != expected_status or result.stdout.strip() != expected_output:
            failures.append(
                f"{path.name}: expected ({expected_status}, {expected_output!r}), "
                f"got ({result.returncode}, {result.stdout.strip()!r})"
            )

    assert not failures, "Dynamic classifier failures: " + " | ".join(failures)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
