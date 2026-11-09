#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import stat
import subprocess
from pathlib import Path

RAW = Path("/home/user/raw_translations.csv")
OUTPUT = Path("/home/user/processed_samples.csv")
SCRIPT = Path("/home/user/run_pipeline.sh")
PROJECT = Path("/home/user/loc_pipeline")
MANIFEST = PROJECT / "Cargo.toml"

ORIGINAL_EXPECTED = """bucket,locale,masked_id,cleaned_text
2023-10-24-14,es_ES,MASKED,Hola
2023-10-24-14,fr_FR,MASKED,Bonjour\\nle monde
2023-10-24-14,fr_FR,MASKED,Merci beaucoup
2023-10-24-15,es_ES,MASKED,Hola\\nAmigo
2023-10-24-15,es_ES,MASKED,Adiós
2023-10-25-09,de_DE,MASKED,Guten\\nMorgen"""


def read_rows():
    with OUTPUT.open("r", encoding="utf-8", newline="") as f:
        return list(csv.reader(f))


def assert_rows(expected):
    assert OUTPUT.is_file(), "processed_samples.csv was not created."
    actual = read_rows()
    assert actual == expected, f"Unexpected processed CSV. Expected {expected!r}, got {actual!r}"


def write_fixture(data):
    RAW.write_bytes(data)
    if OUTPUT.exists():
        OUTPUT.unlink()


def test_complete_pipeline_and_rust_artifact():
    # Preserve all original final-state assertions.
    assert SCRIPT.is_file(), f"File {SCRIPT} is missing."
    st = SCRIPT.stat()
    assert bool(st.st_mode & stat.S_IXUSR), f"File {SCRIPT} is not executable."
    assert OUTPUT.is_file(), f"File {OUTPUT} is missing."
    assert PROJECT.is_dir(), f"Directory {PROJECT} is missing. A Rust project was expected here."
    assert MANIFEST.is_file(), f"File {MANIFEST} is missing. Not a valid Rust project."

    original_raw = RAW.read_bytes()
    original_output = OUTPUT.read_bytes()

    try:
        # Execute the submitted script on the supplied fixture before checking the
        # original exact expected result.
        subprocess.run([str(SCRIPT)], cwd="/home/user", check=True, timeout=180)
        assert OUTPUT.is_file(), f"File {OUTPUT} is missing."
        content = OUTPUT.read_text(encoding="utf-8").strip()
        assert content == ORIGINAL_EXPECTED.strip(), (
            "Content of processed_samples.csv does not match the expected final state."
        )
        canonical_output = OUTPUT.read_bytes()

        # Exercise run_pipeline.sh on an independent fixture containing unsorted
        # timestamps, CSV quoting, stratification, LF, and embedded CRLF.
        script_fixture = (
            b'timestamp,translator_id,locale,translation_text\n'
            b'2024-02-03T08:50:00Z,secret5,fr_FR,"discard me"\n'
            b'2024-02-03T08:20:00Z,secret4,fr_FR,"Deuxieme\r\nligne"\n'
            b'2024-02-03T07:59:59Z,secret1,en_US,"Earlier\nline"\n'
            b'2024-02-03T08:05:00Z,secret3,fr_FR,"Premier, ""mot"""\n'
            b'2024-02-03T08:10:00Z,secret2,en_US,"Only"\n'
        )
        script_expected = [
            ["bucket", "locale", "masked_id", "cleaned_text"],
            ["2024-02-03-07", "en_US", "MASKED", "Earlier\\nline"],
            ["2024-02-03-08", "en_US", "MASKED", "Only"],
            ["2024-02-03-08", "fr_FR", "MASKED", 'Premier, "mot"'],
            ["2024-02-03-08", "fr_FR", "MASKED", "Deuxieme\\nligne"],
        ]
        write_fixture(script_fixture)
        subprocess.run([str(SCRIPT)], cwd="/home/user", check=True, timeout=180)
        assert_rows(script_expected)

        # Confirm Cargo describes a real binary target whose Rust source is in the
        # requested project, build it, and execute the Rust artifact directly.
        metadata_proc = subprocess.run(
            ["cargo", "metadata", "--no-deps", "--format-version", "1", "--manifest-path", str(MANIFEST)],
            cwd=str(PROJECT), check=True, capture_output=True, text=True, timeout=120,
        )
        metadata = json.loads(metadata_proc.stdout)
        members = set(metadata.get("workspace_members", []))
        candidates = []
        project_real = PROJECT.resolve()
        for package in metadata.get("packages", []):
            if members and package.get("id") not in members:
                continue
            for target in package.get("targets", []):
                if "bin" not in target.get("kind", []):
                    continue
                source = Path(target["src_path"]).resolve()
                assert source.is_file() and source.suffix == ".rs", f"Binary target source is not a Rust file: {source}"
                assert os.path.commonpath([str(project_real), str(source)]) == str(project_real), (
                    f"Rust binary source must be within {PROJECT}: {source}"
                )
                candidates.append((package["name"], target["name"]))
        assert candidates, "Cargo.toml does not define a Rust binary target."

        direct_fixture = (
            b'timestamp,translator_id,locale,translation_text\n'
            b'2022-12-31T23:59:00Z,id4,ja_JP,"third"\n'
            b'2023-01-01T00:01:00Z,id5,ja_JP,"new\nyear"\n'
            b'2022-12-31T23:01:00Z,id1,ja_JP,"first"\n'
            b'2022-12-31T23:02:00Z,id2,ja_JP,"second"\n'
            b'2022-12-31T22:30:00Z,id3,de_DE,"frueher"\n'
        )
        direct_expected = [
            ["bucket", "locale", "masked_id", "cleaned_text"],
            ["2022-12-31-22", "de_DE", "MASKED", "frueher"],
            ["2022-12-31-23", "ja_JP", "MASKED", "first"],
            ["2022-12-31-23", "ja_JP", "MASKED", "second"],
            ["2023-01-01-00", "ja_JP", "MASKED", "new\\nyear"],
        ]
        env = os.environ.copy()
        env["CARGO_TARGET_DIR"] = "/tmp/loc_pipeline_verifier_target"
        artifact_passed = False
        errors = []
        for package_name, target_name in candidates:
            try:
                build = subprocess.run(
                    ["cargo", "build", "--manifest-path", str(MANIFEST), "--package", package_name,
                     "--bin", target_name, "--message-format=json"],
                    cwd=str(PROJECT), env=env, check=True, capture_output=True, text=True, timeout=180,
                )
                executable = None
                for line in build.stdout.splitlines():
                    try:
                        message = json.loads(line)
                    except json.JSONDecodeError:
                        continue
                    if (message.get("reason") == "compiler-artifact" and
                            message.get("target", {}).get("name") == target_name and
                            message.get("executable")):
                        executable = message["executable"]
                assert executable and os.path.isfile(executable), "Cargo did not produce the binary executable."
                write_fixture(direct_fixture)
                subprocess.run([executable], cwd=str(PROJECT), check=True, timeout=120)
                assert_rows(direct_expected)
                artifact_passed = True
                break
            except Exception as exc:
                errors.append(f"{package_name}/{target_name}: {exc}")
        assert artifact_passed, "No Rust binary target implemented the pipeline: " + "; ".join(errors)

    finally:
        RAW.write_bytes(original_raw)
        # Leave the requested supplied-fixture output in place when possible.
        if 'canonical_output' in locals():
            OUTPUT.write_bytes(canonical_output)
        else:
            OUTPUT.write_bytes(original_output)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
