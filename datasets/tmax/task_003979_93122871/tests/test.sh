#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import io
import json
import os
import secrets
import shutil
import subprocess
import tarfile
import tempfile
import zipfile


def test_processed_logs_directory_exists():
    path = "/home/user/processed_logs"
    assert os.path.isdir(path), f"Directory {path} does not exist."


def test_processed_files_exist_and_content_is_utf8():
    expected_files = {
        "1001.txt": "ARCHIVE-ID: 1001\nSystem status: échoué\n",
        "2005.txt": "ARCHIVE-ID: 2005\nTemperature: 45°C\n",
        "99X3.txt": "ARCHIVE-ID: 99X3\nUser: mädchen\n"
    }

    for filename, expected_content in expected_files.items():
        filepath = os.path.join("/home/user/processed_logs", filename)
        assert os.path.isfile(filepath), f"File {filepath} does not exist."

        with open(filepath, "r", encoding="utf-8") as f:
            content = f.read()

        assert content == expected_content, f"Content of {filepath} does not match expected UTF-8 content. Got: {repr(content)}"


def test_processed_manifest_exists_and_correct():
    path = "/home/user/processed_manifest.txt"
    assert os.path.isfile(path), f"Manifest file {path} does not exist."

    with open(path, "r", encoding="utf-8") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    expected_lines = ["1001.txt", "2005.txt", "99X3.txt"]
    assert lines == expected_lines, f"Manifest file content does not match. Expected {expected_lines}, got {lines}"


def test_original_archive_exists():
    path = "/home/user/legacy_backups.tar.gz"
    assert os.path.isfile(path), f"Original archive {path} was deleted or is not a file."


def test_archive_processor_is_rust_cargo_program():
    project = "/home/user/archive_processor"
    manifest = os.path.join(project, "Cargo.toml")
    assert os.path.isdir(project), f"Cargo project directory {project} does not exist."
    assert os.path.isfile(manifest), f"Cargo manifest {manifest} does not exist."

    env = os.environ.copy()
    env["HOME"] = "/home/user"
    env["CARGO_NET_OFFLINE"] = "true"
    result = subprocess.run(
        ["cargo", "metadata", "--no-deps", "--format-version", "1", "--manifest-path", manifest],
        cwd=project,
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=60,
    )
    assert result.returncode == 0, f"Invalid Cargo project:\n{result.stderr}"
    metadata = json.loads(result.stdout)
    project_real = os.path.realpath(project)
    rust_bins = []
    for package in metadata.get("packages", []):
        for target in package.get("targets", []):
            if "bin" in target.get("kind", []):
                source = target.get("src_path", "")
                if source.endswith(".rs") and os.path.isfile(source):
                    try:
                        inside = os.path.commonpath([project_real, os.path.realpath(source)]) == project_real
                    except ValueError:
                        inside = False
                    if inside:
                        rust_bins.append(source)
    assert rust_bins, "The Cargo project does not contain a Rust binary target."


def _zip_bytes(entries):
    output = io.BytesIO()
    with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for name, data in entries:
            archive.writestr(name, data)
    return output.getvalue()


def test_z_program_executes_and_processes_unseen_archive():
    project = "/home/user/archive_processor"
    archive_path = "/home/user/legacy_backups.tar.gz"
    output_dir = "/home/user/processed_logs"
    manifest_path = "/home/user/processed_manifest.txt"

    token = secrets.token_hex(8).upper()
    records = [
        (f"A{token[:7]}", f"ARCHIVE-ID: A{token[:7]}\nRésultat: café numéro {token[0]}\n"),
        (f"B{token[1:8]}", f"ARCHIVE-ID: B{token[1:8]}\nTempérature: 37° et déjà vérifiée\n"),
        (f"C{token[2:9]}", f"ARCHIVE-ID: C{token[2:9]}\nUtilisateur: Jürgen, façade {token[-1]}\n"),
    ]
    expected = {f"{record_id}.txt": text for record_id, text in records}

    with tempfile.TemporaryDirectory(prefix="archive-verifier-") as temp:
        archive_backup = os.path.join(temp, "legacy_backups.tar.gz")
        shutil.copy2(archive_path, archive_backup)

        logs_backup = os.path.join(temp, "processed_logs")
        had_logs = os.path.isdir(output_dir)
        if had_logs:
            shutil.copytree(output_dir, logs_backup)

        manifest_backup = os.path.join(temp, "processed_manifest.txt")
        had_manifest = os.path.isfile(manifest_path)
        if had_manifest:
            shutil.copy2(manifest_path, manifest_backup)

        stale_names = {"part1.zip", "part2.zip", "legacy_1.log", "legacy_2.log", "legacy_3.log"}
        stashed = []
        stale_dir = os.path.join(temp, "stale")
        os.makedirs(stale_dir)
        for root, dirs, files in os.walk("/home/user"):
            if os.path.realpath(root).startswith(os.path.realpath(output_dir) + os.sep):
                dirs[:] = []
                continue
            for name in files:
                if name in stale_names:
                    source = os.path.join(root, name)
                    destination = os.path.join(stale_dir, str(len(stashed)))
                    shutil.move(source, destination)
                    stashed.append((source, destination))

        try:
            zip1 = _zip_bytes([
                ("legacy_1.log", records[0][1].encode("iso-8859-1")),
                ("legacy_2.log", records[1][1].encode("iso-8859-1")),
            ])
            zip2 = _zip_bytes([
                ("legacy_3.log", records[2][1].encode("iso-8859-1")),
                ("ignore.dat", b"not a log"),
            ])
            with tarfile.open(archive_path, "w:gz") as outer:
                for name, payload in (("part1.zip", zip1), ("part2.zip", zip2)):
                    info = tarfile.TarInfo(name)
                    info.size = len(payload)
                    outer.addfile(info, io.BytesIO(payload))

            shutil.rmtree(output_dir, ignore_errors=True)
            if os.path.exists(manifest_path):
                os.remove(manifest_path)

            env = os.environ.copy()
            env["HOME"] = "/home/user"
            env["CARGO_NET_OFFLINE"] = "true"
            result = subprocess.run(
                ["cargo", "run", "--quiet", "--manifest-path", os.path.join(project, "Cargo.toml")],
                cwd=project,
                env=env,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=180,
            )
            assert result.returncode == 0, (
                f"Rust archive processor failed when executed.\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
            )
            assert os.path.isdir(output_dir), "Executing the Rust program did not create processed_logs."
            actual_names = sorted(name for name in os.listdir(output_dir) if os.path.isfile(os.path.join(output_dir, name)))
            assert actual_names == sorted(expected), f"Unexpected processed files: {actual_names}"
            for name, wanted in expected.items():
                with open(os.path.join(output_dir, name), "r", encoding="utf-8") as handle:
                    actual = handle.read()
                assert actual == wanted, f"Rust program produced incorrect decoded content for {name}: {actual!r}"
        finally:
            shutil.copy2(archive_backup, archive_path)
            shutil.rmtree(output_dir, ignore_errors=True)
            if had_logs:
                shutil.copytree(logs_backup, output_dir)
            if os.path.exists(manifest_path):
                os.remove(manifest_path)
            if had_manifest:
                shutil.copy2(manifest_backup, manifest_path)
            for original, saved in stashed:
                if os.path.exists(original):
                    os.remove(original)
                os.makedirs(os.path.dirname(original), exist_ok=True)
                shutil.move(saved, original)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
