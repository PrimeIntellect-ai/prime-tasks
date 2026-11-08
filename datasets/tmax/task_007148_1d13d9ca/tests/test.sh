#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import pathlib
import shutil
import subprocess
import uuid


def run_checked(command, timeout=10):
    result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            text=True, timeout=timeout)
    assert result.returncode == 0, (
        f"Command {command!r} failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def test_prep_config_script_exists():
    script_path = "/home/user/prep_config.sh"
    assert os.path.isfile(script_path), f"Shell script {script_path} does not exist."


def test_prep_config_script_runs_on_original_input():
    clean_config_path = "/home/user/clean_config.txt"
    if os.path.exists(clean_config_path):
        os.remove(clean_config_path)
    run_checked(["bash", "/home/user/prep_config.sh"])
    assert os.path.isfile(clean_config_path), (
        f"Running /home/user/prep_config.sh did not create {clean_config_path}."
    )


def test_clean_config_contents():
    clean_config_path = "/home/user/clean_config.txt"
    assert os.path.isfile(clean_config_path), f"File {clean_config_path} does not exist."

    with open(clean_config_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = [
        "INCLUDE /home/user/project/data",
        "INCLUDE /home/user/project/src",
        "EXCLUDE .tmp",
        "EXCLUDE .o"
    ]

    assert lines == expected_lines, (
        f"Content of {clean_config_path} is incorrect. Expected {expected_lines}, got {lines}."
    )


def test_prep_config_handles_unseen_input():
    raw_path = "/home/user/config.raw"
    clean_path = "/home/user/clean_config.txt"
    original_raw = pathlib.Path(raw_path).read_bytes()
    original_clean = pathlib.Path(clean_path).read_bytes() if os.path.exists(clean_path) else None
    token = uuid.uuid4().hex
    test_input = (
        "   # ignored comment\n"
        "\t\n"
        f"   INCLUDE\t\t/home/user/{token}/alpha   beta \t\n"
        " EXCLUDE    .tmp\n"
        f"\tWORD\t{token}\t\ttail   \n"
        "  # another ignored comment\n"
    )
    expected = [
        f"INCLUDE /home/user/{token}/alpha beta",
        "EXCLUDE .tmp",
        f"WORD {token} tail",
    ]

    try:
        pathlib.Path(raw_path).write_text(test_input)
        if os.path.exists(clean_path):
            os.remove(clean_path)
        run_checked(["bash", "/home/user/prep_config.sh"])
        assert os.path.isfile(clean_path), "The prep script did not create clean_config.txt."
        actual = pathlib.Path(clean_path).read_text().splitlines()
        assert actual == expected, (
            f"The prep script failed on an unseen configuration. Expected {expected}, got {actual}."
        )
    finally:
        pathlib.Path(raw_path).write_bytes(original_raw)
        if original_clean is None:
            if os.path.exists(clean_path):
                os.remove(clean_path)
        else:
            pathlib.Path(clean_path).write_bytes(original_clean)


def test_c_program_exists():
    source_path = "/home/user/build_manifest.c"
    bin_path = "/home/user/build_manifest"

    assert os.path.isfile(source_path), f"C source file {source_path} does not exist."
    assert os.path.isfile(bin_path), f"Compiled binary {bin_path} does not exist."
    assert os.access(bin_path, os.X_OK), f"Binary {bin_path} is not executable."
    with open(bin_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{bin_path} is not a compiled executable."


def test_generate_original_manifest():
    run_checked(["bash", "/home/user/prep_config.sh"])
    manifest_path = "/home/user/manifest.txt"
    if os.path.exists(manifest_path):
        os.remove(manifest_path)
    run_checked(["/home/user/build_manifest"])
    assert os.path.isfile(manifest_path), (
        "Running /home/user/build_manifest did not create /home/user/manifest.txt."
    )


def test_manifest_contents_and_sorting():
    manifest_path = "/home/user/manifest.txt"
    assert os.path.isfile(manifest_path), f"Manifest file {manifest_path} does not exist."

    expected_files = [
        "/home/user/project/data/f1.dat",
        "/home/user/project/data/f2.dat",
        "/home/user/project/src/main.c"
    ]

    expected_lines = []
    for filepath in expected_files:
        assert os.path.isfile(filepath), f"Expected test file {filepath} is missing."
        with open(filepath, "rb") as f:
            file_hash = hashlib.sha256(f.read()).hexdigest()
        expected_lines.append(f"{file_hash} {filepath}")

    with open(manifest_path, "r") as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert len(actual_lines) == len(expected_lines), (
        f"Expected exactly {len(expected_lines)} lines in manifest (symlinks and excluded extensions "
        f"must be ignored), but got {len(actual_lines)}."
    )

    for line in expected_lines:
        assert line in actual_lines, f"Expected entry '{line}' not found in manifest."

    sorted_by_full_line = sorted(actual_lines)

    def extract_path(line):
        parts = line.split(maxsplit=1)
        return parts[1] if len(parts) == 2 else line

    sorted_by_path = sorted(actual_lines, key=extract_path)
    is_sorted_by_line = actual_lines == sorted_by_full_line
    is_sorted_by_path = actual_lines == sorted_by_path

    assert is_sorted_by_line or is_sorted_by_path, (
        "Manifest is not sorted. It must be sorted either by the absolute file path or "
        "by the entire line (if using the standard `sort` command)."
    )


def test_manifest_generator_on_unseen_tree_and_config(tmp_path):
    clean_path = pathlib.Path("/home/user/clean_config.txt")
    manifest_path = pathlib.Path("/home/user/manifest.txt")
    old_clean = clean_path.read_bytes() if clean_path.exists() else None
    old_manifest = manifest_path.read_bytes() if manifest_path.exists() else None

    root = pathlib.Path("/home/user") / ("verify_manifest_" + uuid.uuid4().hex)
    first = root / "first"
    nested = first / "nested"
    second = root / "second"
    external = root / "external.txt"
    nested.mkdir(parents=True)
    second.mkdir(parents=True)

    files = {
        first / "zeta.txt": b"zeta unseen data\n",
        nested / "alpha.dat": b"alpha unseen data\n",
        second / "beta.c": b"int beta(void) { return 7; }\n",
        second / "keep.o.txt": b"this does not end in .o\n",
    }
    excluded = {
        nested / "drop.tmp": b"excluded tmp\n",
        second / "drop.o": b"excluded object\n",
    }
    for path, content in {**files, **excluded}.items():
        path.write_bytes(content)
    external.write_bytes(b"must only be reachable through a symlink\n")

    os.symlink(str(root), str(nested / "loop"))
    os.symlink(str(second), str(first / "second_link"))
    os.symlink(str(external), str(first / "linked_regular"))

    config = (
        f"INCLUDE {first}\n"
        f"INCLUDE {second}\n"
        "EXCLUDE .tmp\n"
        "EXCLUDE .o\n"
    )
    expected = [f"{hashlib.sha256(content).hexdigest()} {path}" for path, content in files.items()]

    def verify_run(executable):
        if manifest_path.exists():
            manifest_path.unlink()
        run_checked([str(executable)], timeout=10)
        assert manifest_path.is_file(), f"{executable} did not create the manifest."
        actual = manifest_path.read_text().splitlines()
        assert len(actual) == len(expected), (
            f"Expected exactly {len(expected)} dynamically derived entries, got {actual}."
        )
        assert set(actual) == set(expected), (
            f"Manifest from {executable} is incorrect. Expected {expected}, got {actual}."
        )
        by_line = sorted(actual)
        by_path = sorted(actual, key=lambda line: line.split(maxsplit=1)[1])
        assert actual == by_line or actual == by_path, "The generated manifest is not sorted."

    try:
        clean_path.write_text(config)
        verify_run("/home/user/build_manifest")

        rebuilt = tmp_path / "build_manifest_rebuilt"
        run_checked(["gcc", "/home/user/build_manifest.c", "-o", str(rebuilt)], timeout=20)
        verify_run(rebuilt)
    finally:
        shutil.rmtree(root, ignore_errors=True)
        if old_clean is None:
            if clean_path.exists():
                clean_path.unlink()
        else:
            clean_path.write_bytes(old_clean)
        if old_manifest is None:
            if manifest_path.exists():
                manifest_path.unlink()
        else:
            manifest_path.write_bytes(old_manifest)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
