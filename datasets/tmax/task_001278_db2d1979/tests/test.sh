#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import tarfile
import tempfile
import uuid

SCRIPT_PATH = "/home/user/filter.sh"
EXPECTED_SIGNATURE = "Signature: BLUE JAY VOCALIZATION IN NORTHERN WOODS"
EXPECTED_KEYS = ["Date", "Location", "Species", "Recorder_ID"]


def run_filter(input_dir, output_dir):
    return subprocess.run(
        ["bash", SCRIPT_PATH, input_dir, output_dir],
        capture_output=True,
        text=True,
        timeout=20,
    )


def assert_transformed(input_path, output_path):
    with open(input_path, "r") as f_in, open(output_path, "r") as f_out:
        in_content = f_in.read()
        out_content = f_out.read()

    in_lines = in_content.strip("\n").split("\n")
    out_lines = out_content.strip("\n").split("\n")
    assert out_lines and out_lines[-1] == EXPECTED_SIGNATURE
    assert out_lines[:-1] == in_lines


def test_filter_script_exists():
    assert os.path.isfile(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}"


def test_filter_behavior_on_corpora():
    clean_corpus = "/app/corpus/clean"
    evil_corpus = "/app/corpus/evil"

    assert os.path.isdir(clean_corpus), f"Clean corpus missing at {clean_corpus}"
    assert os.path.isdir(evil_corpus), f"Evil corpus missing at {evil_corpus}"

    with tempfile.TemporaryDirectory() as clean_out, tempfile.TemporaryDirectory() as evil_out:
        res_clean = run_filter(clean_corpus, clean_out)
        assert res_clean.returncode == 0, f"Script failed on clean corpus. stderr: {res_clean.stderr}"

        res_evil = run_filter(evil_corpus, evil_out)
        assert res_evil.returncode == 0, f"Script failed on evil corpus. stderr: {res_evil.stderr}"

        clean_in_files = set(os.listdir(clean_corpus))
        clean_out_files = set(os.listdir(clean_out))
        evil_in_files = set(os.listdir(evil_corpus))
        evil_out_files = set(os.listdir(evil_out))

        missing_clean = clean_in_files - clean_out_files
        assert not missing_clean, (
            f"{len(missing_clean)} of {len(clean_in_files)} clean files were incorrectly rejected: "
            f"{', '.join(missing_clean)}"
        )

        modified_clean = []
        for name in clean_in_files:
            try:
                assert_transformed(
                    os.path.join(clean_corpus, name),
                    os.path.join(clean_out, name),
                )
            except AssertionError:
                modified_clean.append(name)

        assert not modified_clean, (
            f"{len(modified_clean)} of {len(clean_in_files)} clean files were improperly modified "
            f"or missing the correct signature: {', '.join(modified_clean)}"
        )

        bypassed_evil = evil_out_files
        assert not bypassed_evil, (
            f"{len(bypassed_evil)} of {len(evil_in_files)} evil files bypassed the filter and "
            f"were copied to output: {', '.join(bypassed_evil)}"
        )


def test_archive_extraction_and_integrated_output():
    archive = "/app/incoming_data.tar.gz"
    staging = "/app/staging"
    final_dataset = "/home/user/final_dataset"

    assert os.path.isfile(archive), "Incoming archive is missing"
    integrity = subprocess.run(
        ["tar", "-tzf", archive], capture_output=True, text=True, timeout=20
    )
    assert integrity.returncode == 0, f"Archive integrity check failed: {integrity.stderr}"
    assert os.path.isdir(staging), "Archive was not extracted to /app/staging"
    assert os.path.isdir(final_dataset), "Integrated output /home/user/final_dataset is missing"

    with open("/app/dataset.conf", "r") as conf:
        configured_keys = [part.strip() for part in conf.read().strip().split(",")]
    assert configured_keys == EXPECTED_KEYS, "The supplied dataset configuration was altered"

    archive_files = {}
    with tarfile.open(archive, "r:gz") as tf:
        for member in tf.getmembers():
            if member.isfile() and member.name.endswith(".txt"):
                name = os.path.basename(member.name)
                extracted = tf.extractfile(member)
                assert extracted is not None
                archive_files[name] = extracted.read()

    staging_files = {
        name for name in os.listdir(staging)
        if name.endswith(".txt") and os.path.isfile(os.path.join(staging, name))
    }
    assert staging_files == set(archive_files), "Staging does not contain exactly the archive metadata files"
    for name, expected_bytes in archive_files.items():
        with open(os.path.join(staging, name), "rb") as f:
            assert f.read() == expected_bytes, f"Extracted file {name} differs from the archive"

    accepted = set()
    forbidden = ";|&$`"
    for name in staging_files:
        path = os.path.join(staging, name)
        with open(path, "r") as f:
            content = f.read()
        present = {
            line.split(":", 1)[0]
            for line in content.splitlines()
            if ":" in line
        }
        if all(key in present for key in EXPECTED_KEYS) and not any(ch in content for ch in forbidden):
            accepted.add(name)

    final_files = set(os.listdir(final_dataset))
    assert final_files == accepted, "Integrated final_dataset has missing, rejected, or extra files"
    for name in accepted:
        assert_transformed(os.path.join(staging, name), os.path.join(final_dataset, name))


def test_filter_on_randomized_hidden_corpus_and_configuration():
    conf_path = "/app/dataset.conf"
    with open(conf_path, "rb") as f:
        original_conf = f.read()

    token = uuid.uuid4().hex
    required = [f"Key{token[i:i+6]}" for i in (0, 6, 12, 18)]

    try:
        with open(conf_path, "w") as f:
            f.write(",".join(required) + "\n")

        with tempfile.TemporaryDirectory(prefix=f"input-{token}-") as input_dir, \
             tempfile.TemporaryDirectory(prefix=f"output-{token}-") as output_dir:

            def write_file(name, lines):
                with open(os.path.join(input_dir, name), "w") as f:
                    f.write("\n".join(lines) + "\n")

            base_lines = [
                f"{required[0]}: 2026-09-11",
                f"{required[1]}: Northern Woods",
                f"{required[2]}: Blue Jay (adult)",
                f"{required[3]}: Recorder-{token[:8]}",
            ]

            accepted = {
                f"valid_{token}_a.txt": base_lines,
                f"valid_{token}_b.txt": list(reversed(base_lines)),
                f"valid name {token}.txt": base_lines + ["Optional: Calm morning recording"],
            }
            for name, lines in accepted.items():
                write_file(name, lines)

            for index, missing_key in enumerate(required):
                lines = [line for line in base_lines if not line.startswith(missing_key + ":")]
                lines.append(f"Prefix{missing_key}: decoy value")
                write_file(f"missing_{index}_{token}.txt", lines)

            for index, metachar in enumerate([";", "|", "&", "$", "`"]):
                lines = list(base_lines)
                lines[index % len(lines)] += f" unsafe{metachar}payload"
                write_file(f"metachar_{index}_{token}.txt", lines)

            write_file(f"empty_{token}.txt", [])
            write_file(f"partial_{token}.txt", base_lines[:2])

            result = run_filter(input_dir, output_dir)
            assert result.returncode == 0, f"Script failed on hidden corpus: {result.stderr}"

            output_names = set(os.listdir(output_dir))
            assert output_names == set(accepted), (
                f"Hidden corpus mismatch: expected {sorted(accepted)}, got {sorted(output_names)}"
            )
            for name in accepted:
                assert_transformed(
                    os.path.join(input_dir, name),
                    os.path.join(output_dir, name),
                )
    finally:
        with open(conf_path, "wb") as f:
            f.write(original_conf)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
