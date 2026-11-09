#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import pathlib
import secrets
import shutil
import stat
import struct
import subprocess


def assert_regular_file(path):
    p = pathlib.Path(path)
    assert p.exists(), f"Required file {path} is missing."
    assert not p.is_symlink(), f"Required file {path} must not be a symlink."
    assert stat.S_ISREG(p.stat().st_mode), f"Required path {path} is not a regular file."


def assert_output(target_dir, expected_files):
    assert os.path.exists(target_dir), f"Directory {target_dir} is missing."
    assert os.path.isdir(target_dir), f"{target_dir} is not a directory."

    actual_files = os.listdir(target_dir)
    assert len(actual_files) == len(expected_files), (
        f"Expected exactly {len(expected_files)} files in {target_dir}, "
        f"but found {len(actual_files)}: {actual_files}"
    )

    for filename, expected_content in expected_files.items():
        filepath = os.path.join(target_dir, filename)
        assert os.path.exists(filepath), f"Expected file {filepath} is missing."
        assert os.path.isfile(filepath), f"{filepath} is not a file."
        with open(filepath, "rb") as f:
            actual_content = f.read()
        assert actual_content == expected_content, (
            f"Content mismatch in {filepath}. Expected {expected_content}, got {actual_content}"
        )


def write_archive(path, entries):
    with open(path, "wb") as f:
        for entry_path, data in entries:
            encoded_path = entry_path.encode("utf-8")
            f.write(struct.pack("<H", len(encoded_path)))
            f.write(encoded_path)
            f.write(struct.pack("<I", len(data)))
            f.write(data)


def test_project_and_extractor_behavior():
    target_dir = "/home/user/extracted_docs"

    # Preserve the original final-state assertions.
    expected_files = {
        "doc_intro.html": b"<html><body><p>Welcome to the system.</p></body></html>",
        "doc_id_rsa.txt": b"fake_key_data_123",
        "doc_important_notice.html": b"<html><body><p>System maintenance on Friday.</p></body></html>",
        "doc_config.json": b'{"status": "ok"}'
    }
    assert_output(target_dir, expected_files)

    project_dir = pathlib.Path("/home/user/extractor")
    assert project_dir.is_dir(), "/home/user/extractor is missing or is not a directory."
    manifest = project_dir / "Cargo.toml"
    main_rs = project_dir / "src" / "main.rs"
    assert_regular_file(manifest)
    assert_regular_file(main_rs)

    metadata_result = subprocess.run(
        ["cargo", "metadata", "--no-deps", "--format-version", "1", "--manifest-path", str(manifest)],
        cwd=project_dir,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=60,
    )
    assert metadata_result.returncode == 0, f"Invalid Cargo project: {metadata_result.stderr}"
    metadata = json.loads(metadata_result.stdout)
    project_manifest = manifest.resolve()
    packages = [p for p in metadata["packages"] if pathlib.Path(p["manifest_path"]).resolve() == project_manifest]
    assert packages, "Cargo metadata does not contain the /home/user/extractor package."
    binary_targets = [t for t in packages[0]["targets"] if "bin" in t.get("kind", [])]
    assert binary_targets, "The Cargo project has no Rust binary target."
    assert any(pathlib.Path(t["src_path"]).resolve() == main_rs.resolve() for t in binary_targets), (
        "The Cargo binary target must use /home/user/extractor/src/main.rs."
    )

    token = secrets.token_hex(12)
    md_data = b"dynamic markdown " + secrets.token_bytes(24)
    traversal_data = b"relative traversal " + secrets.token_bytes(19)
    absolute_data = b"absolute traversal " + secrets.token_bytes(21)
    raw_data = b"\x00\xffdynamic raw\n" + secrets.token_bytes(23)

    relative_escape = f"/tmp/ESCAPE_{token}.txt"
    absolute_escape = f"/tmp/ABS_{token}.BIN"
    for escaped in (relative_escape, absolute_escape):
        try:
            os.remove(escaped)
        except FileNotFoundError:
            pass

    entries = [
        (f"Dir/Sub/MiXeD_{token}.Md", md_data),
        (f"../../../tmp/ESCAPE_{token}.txt", traversal_data),
        (absolute_escape, absolute_data),
        (f"nested/RAW_{token}.dat", raw_data),
    ]
    write_archive("/home/user/legacy_docs.bin", entries)

    for name in os.listdir(target_dir):
        path = os.path.join(target_dir, name)
        if os.path.isdir(path) and not os.path.islink(path):
            shutil.rmtree(path)
        else:
            os.unlink(path)

    build_result = subprocess.run(
        ["cargo", "build", "--quiet", "--manifest-path", str(manifest)],
        cwd=project_dir,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=120,
    )
    assert build_result.returncode == 0, f"Cargo build failed: {build_result.stderr}"

    run_result = subprocess.run(
        ["cargo", "run", "--quiet", "--manifest-path", str(manifest)],
        cwd=project_dir,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=120,
    )
    assert run_result.returncode == 0, f"Rust extractor failed: {run_result.stderr}"

    dynamic_expected = {
        f"doc_mixed_{token}.html": b"<html><body><p>" + md_data + b"</p></body></html>",
        f"doc_escape_{token}.txt": traversal_data,
        f"doc_abs_{token}.bin": absolute_data,
        f"doc_raw_{token}.dat": raw_data,
    }
    assert_output(target_dir, dynamic_expected)
    assert not os.path.lexists(relative_escape), f"Traversal wrote outside the target directory: {relative_escape}"
    assert not os.path.lexists(absolute_escape), f"Absolute path wrote outside the target directory: {absolute_escape}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
