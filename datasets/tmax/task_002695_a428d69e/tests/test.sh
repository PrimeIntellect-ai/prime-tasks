#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess
import tarfile
import tempfile
import uuid
import pytest

CLEAN_DIR = "/app/corpus/clean/"
EVIL_DIR = "/app/corpus/evil/"

# Snapshot the shipped corpus before any submitted program is executed.
INITIAL_CLEAN = {
    name: open(os.path.join(CLEAN_DIR, name), "rb").read()
    for name in os.listdir(CLEAN_DIR)
    if name.endswith(".conf")
}


def run_archiver(binary, directory):
    return subprocess.run(
        [binary, directory], capture_output=True, text=True, timeout=20
    )


def test_archiver_binary_exists():
    assert os.path.isfile("/home/user/archiver"), "The Go binary /home/user/archiver does not exist."
    assert os.access("/home/user/archiver", os.X_OK), "The Go binary /home/user/archiver is not executable."


def test_go_source_builds_and_handles_generated_cases():
    source = "/home/user/archiver.go"
    assert os.path.isfile(source), "The Go source /home/user/archiver.go does not exist."

    with tempfile.TemporaryDirectory() as td:
        rebuilt = os.path.join(td, "archiver-from-source")
        build = subprocess.run(
            ["go", "build", "-o", rebuilt, source],
            capture_output=True, text=True, timeout=60
        )
        assert build.returncode == 0, f"archiver.go did not compile:\n{build.stdout}\n{build.stderr}"
        assert os.path.isfile(rebuilt) and os.access(rebuilt, os.X_OK)

        corpus = os.path.join(td, "generated-corpus")
        os.mkdir(corpus)
        token = uuid.uuid4().hex

        accepted = {
            f"node_{token}.conf": b"PORT=9123\nDEBUG_LEVEL=0\nMODE=test\nDEBUG_LEVEL=0\n",
            f"plain_{token}.conf": b"PORT=8123\nMODE=production\n",
        }
        rejected = {
            f"parent_{token}.conf": b"SOURCE=../../private/data\nDEBUG_LEVEL=0\n",
            f"shell_{token}.conf": b"COMMAND=/bin/sh -c payload\n",
            f"code_{token}.conf": b"HANDLER=eval(payload)\n",
            f"bad name {token}.conf": b"PORT=7000\nDEBUG_LEVEL=0\n",
            f".{token}.conf": b"PORT=7001\nDEBUG_LEVEL=0\n",
            f"tab\t{token}.conf": b"PORT=7002\nDEBUG_LEVEL=0\n",
        }
        ignored_name = f"ignore_{token}.txt"
        ignored_content = b"DEBUG_LEVEL=0\n../\n"

        for name, content in {**accepted, **rejected}.items():
            with open(os.path.join(corpus, name), "wb") as f:
                f.write(content)
        with open(os.path.join(corpus, ignored_name), "wb") as f:
            f.write(ignored_content)

        result = run_archiver(rebuilt, corpus)
        assert result.returncode == 0, f"Generated-corpus run failed: {result.stderr}"
        lines = (result.stdout + "\n" + result.stderr).splitlines()

        for name, original in accepted.items():
            assert f"ACCEPTED: {name}" in lines, f"Generated clean file was not accepted: {name}"
            assert f"REJECTED: {name}" not in lines, f"Generated clean file was also rejected: {name}"
            with open(os.path.join(corpus, name), "rb") as f:
                actual = f.read()
            expected = original.replace(b"DEBUG_LEVEL=0", b"DEBUG_LEVEL=1")
            assert actual == expected, f"Transformation was incorrect for {name}"

        for name, original in rejected.items():
            assert f"REJECTED: {name}" in lines, f"Generated malicious/invalid file bypassed checks: {name!r}"
            assert f"ACCEPTED: {name}" not in lines, f"Generated rejected file was also accepted: {name!r}"
            with open(os.path.join(corpus, name), "rb") as f:
                assert f.read() == original, f"Rejected file was modified: {name!r}"

        assert not any(ignored_name in line for line in lines), "A non-.conf file was processed."
        with open(os.path.join(corpus, ignored_name), "rb") as f:
            assert f.read() == ignored_content


def test_adversarial_corpus_clean():
    result = run_archiver("/home/user/archiver", CLEAN_DIR)
    output = result.stdout + "\n" + result.stderr

    clean_files = [f for f in os.listdir(CLEAN_DIR) if f.endswith(".conf")]
    bypassed = []
    for f in clean_files:
        expected_str = f"ACCEPTED: {f}"
        if expected_str not in output:
            bypassed.append(f)

    if bypassed:
        pytest.fail(f"{len(bypassed)} of {len(clean_files)} clean modified/rejected. Offending files: {', '.join(bypassed)}")


def test_adversarial_corpus_evil():
    result = run_archiver("/home/user/archiver", EVIL_DIR)
    output = result.stdout + "\n" + result.stderr

    evil_files = [f for f in os.listdir(EVIL_DIR) if f.endswith(".conf")]
    bypassed = []
    for f in evil_files:
        expected_str = f"REJECTED: {f}"
        if expected_str not in output:
            bypassed.append(f)

    if bypassed:
        pytest.fail(f"{len(bypassed)} of {len(evil_files)} evil bypassed. Offending files: {', '.join(bypassed)}")


def test_final_archive_exists_and_correct():
    archive_path = "/home/user/final_backup_omega.tar.gz"
    assert os.path.isfile(archive_path), f"Final archive missing: {archive_path}"

    transcript = subprocess.run(
        ["/usr/local/bin/whisper", "/app/incident_report.wav"],
        capture_output=True, text=True, timeout=20, check=True
    ).stdout
    match = re.search(r"The archive key is\s+([A-Za-z]+)", transcript, re.IGNORECASE)
    assert match, f"Could not derive archive key from transcription: {transcript!r}"
    assert match.group(1).lower() == "omega"

    expected_contents = {
        name: content.replace(b"DEBUG_LEVEL=0", b"DEBUG_LEVEL=1")
        for name, content in INITIAL_CLEAN.items()
        if not any(x in content for x in (b"../", b"/bin/sh", b"eval("))
        and " " not in name
        and not name.startswith(".")
        and not any(ord(ch) < 32 or ord(ch) == 127 for ch in name)
    }

    with tarfile.open(archive_path, "r:gz") as tar:
        members = tar.getmembers()
        names = tar.getnames()
        conf_files = [m for m in names if m.endswith(".conf")]

        assert len(conf_files) == 2, f"Archive should contain exactly 2 .conf files, found {len(conf_files)}"
        expected_basenames = {"server1.conf", "server2.conf"}
        actual_basenames = {os.path.basename(m) for m in conf_files}
        assert expected_basenames.issubset(actual_basenames), f"Archive missing expected files. Found: {actual_basenames}"

        for m in conf_files:
            f = tar.extractfile(m)
            content = f.read().decode("utf-8")
            assert "DEBUG_LEVEL=1" in content, f"File {m} in archive was not properly transformed. Content: {content}"
            assert "DEBUG_LEVEL=0" not in content, f"File {m} in archive still contains DEBUG_LEVEL=0."

        for member in members:
            normalized = os.path.normpath(member.name)
            assert not os.path.isabs(member.name), f"Archive contains an absolute path: {member.name}"
            assert normalized != ".." and not normalized.startswith("../"), f"Archive contains path traversal: {member.name}"
            assert member.isfile() or member.isdir(), f"Archive contains a non-file entry: {member.name}"

        regular = [m for m in members if m.isfile()]
        assert len(regular) == len(expected_contents), "Archive must contain only the accepted clean files."
        assert {os.path.basename(m.name) for m in regular} == set(expected_contents), \
            "Archive file set does not match the independently derived accepted set."

        for name, expected in expected_contents.items():
            matches = [m for m in regular if os.path.basename(m.name) == name]
            assert len(matches) == 1, f"Expected exactly one archive member for {name}."
            extracted = tar.extractfile(matches[0])
            assert extracted is not None
            assert extracted.read() == expected, f"Archived content for {name} was not derived by the required transformation."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
