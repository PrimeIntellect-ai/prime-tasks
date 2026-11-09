#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import pathlib
import secrets
import subprocess
import tempfile
import pytest

SCRIPT_PATH = "/home/user/run_filter.sh"
PROJECT_DIR = "/home/user/log_sanitizer"
MANIFEST_PATH = os.path.join(PROJECT_DIR, "Cargo.toml")
VENDORED_DIR = "/app/vendored/log-chrono-0.1.5"


def test_run_filter_sh_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Wrapper script {SCRIPT_PATH} does not exist."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Wrapper script {SCRIPT_PATH} is not executable."


def test_adversarial_corpus():
    evil_dir = "/app/corpora/evil"
    clean_dir = "/app/corpora/clean"

    assert os.path.isdir(evil_dir), f"Evil corpus directory {evil_dir} missing."
    assert os.path.isdir(clean_dir), f"Clean corpus directory {clean_dir} missing."

    evil_files = [f for f in os.listdir(evil_dir) if os.path.isfile(os.path.join(evil_dir, f))]
    clean_files = [f for f in os.listdir(clean_dir) if os.path.isfile(os.path.join(clean_dir, f))]

    evil_bypassed = []
    clean_modified = []

    with tempfile.TemporaryDirectory() as tmpdir:
        for filename in evil_files:
            input_file = os.path.join(evil_dir, filename)
            output_file = os.path.join(tmpdir, f"out_{filename}")

            result = subprocess.run([SCRIPT_PATH, input_file, output_file], capture_output=True, text=True)
            if result.returncode != 0:
                evil_bypassed.append(f"{filename} (script failed with code {result.returncode})")
                continue

            if not os.path.exists(output_file):
                continue

            with open(output_file, "r") as f:
                content = f.read().strip()
                if content:
                    evil_bypassed.append(filename)

        for filename in clean_files:
            input_file = os.path.join(clean_dir, filename)
            output_file = os.path.join(tmpdir, f"out_{filename}")

            result = subprocess.run([SCRIPT_PATH, input_file, output_file], capture_output=True, text=True)
            if result.returncode != 0:
                clean_modified.append(f"{filename} (script failed with code {result.returncode})")
                continue

            if not os.path.exists(output_file):
                clean_modified.append(f"{filename} (output file missing)")
                continue

            with open(input_file, "r") as f_in, open(output_file, "r") as f_out:
                in_lines = f_in.readlines()
                out_lines = f_out.readlines()
                if in_lines != out_lines:
                    clean_modified.append(filename)

    error_messages = []
    if evil_bypassed:
        error_messages.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_modified:
        error_messages.append(f"{len(clean_modified)} of {len(clean_files)} clean modified: {', '.join(clean_modified)}")

    if error_messages:
        pytest.fail(" | ".join(error_messages))


def mixed_case(value):
    return "".join(c.upper() if secrets.randbelow(2) else c.lower() for c in value)


def make_generated_corpus():
    nonce = secrets.token_hex(12)
    valid_ts = "ts-" + nonce
    records = []

    def encoded(timestamp, level, message):
        return json.dumps(
            {"timestamp": timestamp, "level": level, "message": message},
            separators=(",", ":"),
        )

    for message in [
        "request completed " + nonce,
        "ordinary database warning " + nonce,
        "the words union and select are separate " + nonce,
        "dash - but not a comment marker " + nonce,
    ]:
        line = encoded(valid_ts, "INFO", message)
        records.append((line, True))

    # Patterns outside the message field must not cause a record to be dropped.
    line = encoded("valid--timestamp-" + nonce, "DROP TABLE", "benign message " + nonce)
    records.append((line, True))

    for pattern in ["union select", "drop table", "or 1=1", "--"]:
        line = encoded(valid_ts, "WARN", "prefix " + mixed_case(pattern) + " suffix " + nonce)
        records.append((line, False))

    # These patterns only become visible after parsing JSON escapes.
    records.append((
        '{"level":"INFO","message":"prefix UNION\\u0020SELECT suffix ' + nonce + '","timestamp":"' + valid_ts + '"}',
        False,
    ))
    records.append((
        '{ "message" : "please dr\\u006fp table audit", "timestamp" : "' + valid_ts + '", "level" : "WARN" }',
        False,
    ))

    # log_chrono::parse_ts rejects strings of length five or less.
    for timestamp in ["", "x", "12345"]:
        records.append((encoded(timestamp, "INFO", "otherwise benign " + nonce), False))

    # The vendored parser accepts any timestamp longer than five characters.
    records.append((encoded("abcdef", "INFO", "accepted unusual timestamp " + nonce), True))

    secrets.SystemRandom().shuffle(records)
    input_bytes = "".join(line + "\n" for line, _ in records).encode("utf-8")
    expected_bytes = "".join(line + "\n" for line, keep in records if keep).encode("utf-8")
    return input_bytes, expected_bytes


def run_and_check(command, input_bytes, expected_bytes, directory, output_name):
    input_path = os.path.join(directory, "input-" + secrets.token_hex(8) + ".jsonl")
    output_path = os.path.join(directory, output_name)
    with open(input_path, "wb") as f:
        f.write(input_bytes)

    result = subprocess.run(
        command + [input_path, output_path],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"filter failed with code {result.returncode}; stdout={result.stdout!r}, stderr={result.stderr!r}"
    )
    assert os.path.isfile(output_path), "filter did not create its output file"
    with open(output_path, "rb") as f:
        actual = f.read()
    assert actual == expected_bytes, "generated mixed corpus was not filtered and preserved correctly"


def test_generated_hidden_mixed_corpus_through_wrapper():
    input_bytes, expected_bytes = make_generated_corpus()
    with tempfile.TemporaryDirectory(prefix="sanitizer-check-") as tmpdir:
        run_and_check([SCRIPT_PATH], input_bytes, expected_bytes, tmpdir, "result-" + secrets.token_hex(8))


def test_rust_project_vendor_fix_and_compiled_binary():
    assert os.path.isdir(PROJECT_DIR), f"Rust project {PROJECT_DIR} is missing"
    assert os.path.isfile(MANIFEST_PATH), f"Cargo manifest {MANIFEST_PATH} is missing"
    assert os.path.isfile(os.path.join(PROJECT_DIR, "src", "main.rs")), "Rust src/main.rs is missing"

    vendor_manifest = os.path.join(VENDORED_DIR, "Cargo.toml")
    assert os.path.isfile(vendor_manifest), "vendored log-chrono Cargo.toml is missing"
    with open(vendor_manifest, encoding="utf-8") as f:
        vendor_text = f.read()
    assert "../missing-cc" not in vendor_text, "the deliberate missing-cc perturbation was not fixed"

    build = subprocess.run(
        ["cargo", "build", "--offline", "--manifest-path", MANIFEST_PATH],
        capture_output=True,
        text=True,
        timeout=120,
    )
    assert build.returncode == 0, f"Rust project does not build: {build.stderr}"

    metadata_result = subprocess.run(
        ["cargo", "metadata", "--offline", "--format-version", "1", "--manifest-path", MANIFEST_PATH],
        capture_output=True,
        text=True,
        timeout=60,
    )
    assert metadata_result.returncode == 0, f"cargo metadata failed: {metadata_result.stderr}"
    metadata = json.loads(metadata_result.stdout)

    project_manifest = str(pathlib.Path(MANIFEST_PATH).resolve())
    project_packages = [p for p in metadata["packages"] if str(pathlib.Path(p["manifest_path"]).resolve()) == project_manifest]
    assert project_packages, "cargo metadata did not contain the requested project package"
    package = project_packages[0]

    vendor_path = pathlib.Path(VENDORED_DIR).resolve()
    matching_dependencies = [d for d in package["dependencies"] if d["name"] == "log-chrono"]
    assert matching_dependencies, "project does not declare the required log-chrono dependency"
    assert any(d.get("path") and pathlib.Path(d["path"]).resolve() == vendor_path for d in matching_dependencies), (
        "log-chrono is not referenced using the required vendored path"
    )

    bin_targets = [t for t in package["targets"] if "bin" in t["kind"]]
    assert bin_targets, "project has no Rust binary target"
    target_dir = pathlib.Path(metadata["target_directory"])
    executables = [target_dir / "debug" / target["name"] for target in bin_targets]
    executables = [str(path) for path in executables if path.is_file() and os.access(path, os.X_OK)]
    assert executables, "cargo build did not produce an executable Rust binary"

    input_bytes, expected_bytes = make_generated_corpus()
    successes = []
    with tempfile.TemporaryDirectory(prefix="rust-binary-check-") as tmpdir:
        for index, executable in enumerate(executables):
            try:
                run_and_check([executable], input_bytes, expected_bytes, tmpdir, f"binary-output-{index}")
                successes.append(executable)
            except (AssertionError, subprocess.SubprocessError, OSError):
                pass
    assert successes, "none of the compiled Rust binary targets implements the required sanitizer"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
