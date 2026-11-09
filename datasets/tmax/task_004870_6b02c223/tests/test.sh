#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import shlex
import shutil
import sqlite3
import subprocess

PROJECT = "/home/user/project"
SCRIPT = os.path.join(PROJECT, "build_fixed.sh")
OUT_DIR = os.path.join(PROJECT, "out")
DB_PATH = os.path.join(PROJECT, "assets.db")
COMPILER = os.path.join(PROJECT, "bin", "asset_compiler")
MAGIC = "COMPILED ASSET MAGIC"


def clear_directory(path):
    os.makedirs(path, exist_ok=True)
    for name in os.listdir(path):
        item = os.path.join(path, name)
        if os.path.isdir(item) and not os.path.islink(item):
            shutil.rmtree(item)
        else:
            os.remove(item)


def run_build():
    return subprocess.run(
        [SCRIPT], cwd=PROJECT, capture_output=True, text=True, timeout=30
    )


def test_failing_assets_txt():
    path = "/home/user/failing_assets.txt"
    assert os.path.isfile(path), f"File {path} does not exist."
    with open(path, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(lines) == 1, f"Expected exactly one line in {path}, found {len(lines)}."
    assert lines[0] == "ui background.png", f"Expected 'ui background.png' in {path}, got '{lines[0]}'."


def test_build_fixed_sh_exists_and_executable():
    assert os.path.isfile(SCRIPT), f"File {SCRIPT} does not exist."
    assert os.access(SCRIPT, os.X_OK), f"File {SCRIPT} is not executable."
    with open(SCRIPT, "rb") as f:
        first_line = f.readline().lower()
    assert first_line.startswith(b"#!") and b"bash" in first_line, "build_fixed.sh must be a Bash script."
    syntax = subprocess.run(["bash", "-n", SCRIPT], capture_output=True, text=True)
    assert syntax.returncode == 0, f"build_fixed.sh has invalid Bash syntax: {syntax.stderr}"


def test_build_fixed_sh_execution_and_output():
    clear_directory(OUT_DIR)
    result = run_build()
    assert result.returncode == 0, f"build_fixed.sh failed with return code {result.returncode}.\nstdout: {result.stdout}\nstderr: {result.stderr}"

    expected_files = [
        "logo.png.out",
        "ui background.png.out",
        "icon.png.out"
    ]
    unexpected_files = [
        "hero image.jpg.out"
    ]

    for name in expected_files:
        path = os.path.join(OUT_DIR, name)
        assert os.path.isfile(path), f"Expected output file {path} is missing."
        with open(path, "r") as out_file:
            content = out_file.read().strip()
        assert content == MAGIC, f"File {path} has incorrect content: '{content}'."

    for name in unexpected_files:
        path = os.path.join(OUT_DIR, name)
        assert not os.path.exists(path), f"Unexpected output file {path} exists (asset should be inactive)."


def test_build_handles_dynamic_database_and_invokes_compiler():
    token = secrets.token_hex(8)
    dynamic_rows = [
        (f"panel {token} one.png", 1),
        (f"panel {token} two.png", 0),
        (f"panel [{token}] three.png", 1),
    ]
    created_assets = [os.path.join(PROJECT, "assets", name) for name, _ in dynamic_rows]
    db_backup = f"/tmp/assets-{token}.db"
    compiler_backup = f"/tmp/asset_compiler-{token}"
    call_log = f"/tmp/compiler-calls-{token}"

    shutil.copy2(DB_PATH, db_backup)
    os.replace(COMPILER, compiler_backup)
    wrapper = f'''#!/bin/bash
printf '%s\\0%s\\0' "$1" "$2" >> {shlex.quote(call_log)}
exec {shlex.quote(compiler_backup)} "$@"
'''
    with open(COMPILER, "w") as f:
        f.write(wrapper)
    os.chmod(COMPILER, 0o755)

    try:
        with sqlite3.connect(DB_PATH) as db:
            db.executemany(
                "INSERT INTO assets(filename, active) VALUES (?, ?)", dynamic_rows
            )

        for path in created_assets:
            with open(path, "wb") as f:
                f.write(secrets.token_bytes(17))

        with sqlite3.connect(DB_PATH) as db:
            active = [row[0] for row in db.execute(
                "SELECT filename FROM assets WHERE active=1"
            )]
            inactive = [row[0] for row in db.execute(
                "SELECT filename FROM assets WHERE active=0"
            )]

        clear_directory(OUT_DIR)
        result = run_build()
        assert result.returncode == 0, f"Dynamic build failed with return code {result.returncode}.\nstdout: {result.stdout}\nstderr: {result.stderr}"

        expected_outputs = {name + ".out" for name in active}
        actual_outputs = set(os.listdir(OUT_DIR))
        assert actual_outputs == expected_outputs, (
            f"Output set does not match active database rows. Expected {expected_outputs}, "
            f"got {actual_outputs}."
        )
        for name in expected_outputs:
            path = os.path.join(OUT_DIR, name)
            assert os.path.isfile(path), f"Expected compiled output {path} is not a regular file."
            with open(path, "r") as f:
                assert f.read().strip() == MAGIC, f"Compiler output {path} has incorrect content."

        assert os.path.isfile(call_log), "build_fixed.sh did not invoke bin/asset_compiler."
        with open(call_log, "rb") as f:
            fields = f.read().split(b"\0")
        if fields and fields[-1] == b"":
            fields.pop()
        assert len(fields) % 2 == 0, "Malformed compiler invocation log."
        calls = []
        for i in range(0, len(fields), 2):
            source = os.path.abspath(os.path.join(PROJECT, os.fsdecode(fields[i])))
            destination = os.path.abspath(os.path.join(PROJECT, os.fsdecode(fields[i + 1])))
            calls.append((source, destination))

        expected_calls = {
            (os.path.join(PROJECT, "assets", name), os.path.join(OUT_DIR, name + ".out"))
            for name in active
        }
        assert expected_calls.issubset(set(calls)), (
            "asset_compiler was not invoked with the correct source and destination "
            f"for every active asset. Calls: {calls}"
        )
        inactive_sources = {os.path.join(PROJECT, "assets", name) for name in inactive}
        assert not any(source in inactive_sources for source, _ in calls), (
            "asset_compiler was invoked for an inactive asset."
        )
    finally:
        if os.path.exists(COMPILER):
            os.remove(COMPILER)
        if os.path.exists(compiler_backup):
            os.replace(compiler_backup, COMPILER)
        if os.path.exists(db_backup):
            os.replace(db_backup, DB_PATH)
        for path in created_assets:
            if os.path.exists(path):
                os.remove(path)
        if os.path.exists(call_log):
            os.remove(call_log)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
