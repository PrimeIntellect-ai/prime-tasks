#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import shlex
import shutil
import stat
import subprocess
from pathlib import Path

PROJECT = Path("/home/user/project_dir")
WORKSPACE = PROJECT / "organized_workspace"
SOURCE_DIR = PROJECT / "source_files"
MANIFEST = PROJECT / "deployment_manifest.json"
LOG = PROJECT / "path_escapes.log"


def test_path_escapes_log():
    assert LOG.is_file(), f"Log file {LOG} was not created."

    with LOG.open("r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = [
        "Invalid path escape attempt: ../database_backup.csv",
        "Invalid path escape attempt: conf/../../etc/passwd",
        "Invalid path escape attempt: src/nested/../../../app.py",
    ]

    assert len(lines) == len(expected_lines), (
        f"Expected {len(expected_lines)} lines in log file, but found {len(lines)}."
    )
    for expected in expected_lines:
        assert expected in lines, f"Missing expected log entry: '{expected}'"


def test_valid_symlinks_created():
    app_py_link = WORKSPACE / "src/app.py"
    assert app_py_link.is_symlink(), f"{app_py_link} should be a symlink."
    assert os.readlink(app_py_link) == str(SOURCE_DIR / "app.py"), (
        f"{app_py_link} does not point to the correct source file."
    )

    db_csv_link = WORKSPACE / "data/db.csv"
    assert db_csv_link.is_symlink(), f"{db_csv_link} should be a symlink."
    assert os.readlink(db_csv_link) == str(SOURCE_DIR / "database.csv"), (
        f"{db_csv_link} does not point to the correct source file."
    )


def test_valid_hardlinks_created():
    style_css_link = WORKSPACE / "assets/style.css"
    style_css_src = SOURCE_DIR / "style.css"

    assert style_css_link.is_file(), f"{style_css_link} should exist."
    assert not style_css_link.is_symlink(), (
        f"{style_css_link} should be a hardlink, not a symlink."
    )
    assert style_css_link.stat().st_ino == style_css_src.stat().st_ino, (
        f"{style_css_link} is not a hardlink to {style_css_src}."
    )


def test_escaped_files_not_created():
    escaped_files = [
        PROJECT / "database_backup.csv",
        PROJECT / "app.py",
        PROJECT / "etc/passwd",
    ]
    for path in escaped_files:
        assert not os.path.lexists(path), (
            f"Escaped file {path} should not have been created."
        )


def candidate_scripts():
    excluded = {
        MANIFEST.resolve(),
        LOG.resolve(),
    }
    candidates = []
    for root, dirs, files in os.walk(PROJECT):
        root_path = Path(root)
        dirs[:] = [
            d for d in dirs
            if (root_path / d) not in (SOURCE_DIR, WORKSPACE)
        ]
        for name in files:
            path = root_path / name
            try:
                resolved = path.resolve()
            except OSError:
                continue
            if resolved in excluded or path.is_symlink() or not path.is_file():
                continue

            suffix = path.suffix.lower()
            executable = bool(path.stat().st_mode & stat.S_IXUSR)
            has_shebang = False
            try:
                with path.open("rb") as f:
                    has_shebang = f.read(2) == b"#!"
            except OSError:
                pass

            if suffix in {".py", ".sh", ".bash"} or executable or has_shebang:
                candidates.append(path)
    return sorted(candidates)


def command_for(path):
    suffix = path.suffix.lower()
    if suffix == ".py":
        return ["python3", str(path)]
    if suffix in {".sh", ".bash"}:
        return ["bash", str(path)]

    try:
        first = path.open("r", errors="ignore").readline().strip()
    except OSError:
        first = ""
    if first.startswith("#!"):
        return shlex.split(first[2:].strip()) + [str(path)]
    if path.stat().st_mode & stat.S_IXUSR:
        return [str(path)]
    return None


def remove_path(path):
    if not os.path.lexists(path):
        return
    if path.is_dir() and not path.is_symlink():
        shutil.rmtree(path)
    else:
        path.unlink()


def test_script_processes_unseen_manifest_safely():
    scripts = candidate_scripts()
    assert scripts, "No processing script was found in the project directory."

    token = secrets.token_hex(8)
    symlink_src_name = f"source_{token}.txt"
    hardlink_src_name = f"hard_{token}.txt"
    symlink_src = SOURCE_DIR / symlink_src_name
    hardlink_src = SOURCE_DIR / hardlink_src_name
    symlink_src.write_text(f"symlink-{token}\n")
    hardlink_src.write_text(f"hardlink-{token}\n")

    symlink_dest = f"generated_{token}/nested/result.txt"
    hardlink_dest = f"assets_{token}/result.dat"
    escape_one = f"../escape_{token}.txt"
    escape_two = f"conf/../../etc/secret_{token}"
    pivot_name = f"pivot_{token}"
    pivot_dest = f"{pivot_name}/through_{token}.txt"
    exact_workspace = "."

    dynamic_manifest = [
        {"src": symlink_src_name, "dest": symlink_dest, "link_type": "symlink"},
        {"src": hardlink_src_name, "dest": hardlink_dest, "link_type": "hardlink"},
        {"src": symlink_src_name, "dest": escape_one, "link_type": "symlink"},
        {"src": hardlink_src_name, "dest": escape_two, "link_type": "hardlink"},
        {"src": symlink_src_name, "dest": pivot_dest, "link_type": "symlink"},
        {"src": hardlink_src_name, "dest": exact_workspace, "link_type": "hardlink"},
    ]
    expected_log = {
        f"Invalid path escape attempt: {escape_one}",
        f"Invalid path escape attempt: {escape_two}",
        f"Invalid path escape attempt: {pivot_dest}",
        f"Invalid path escape attempt: {exact_workspace}",
    }

    escaped_one_path = PROJECT / f"escape_{token}.txt"
    escaped_two_path = PROJECT / "etc" / f"secret_{token}"
    pivot_target = PROJECT / f"pivot_target_{token}"
    pivot_escaped_path = pivot_target / f"through_{token}.txt"
    failures = []

    for script in scripts:
        command = command_for(script)
        if not command:
            failures.append(f"{script}: could not determine how to execute it")
            continue

        remove_path(WORKSPACE)
        WORKSPACE.mkdir(parents=True)
        remove_path(LOG)
        remove_path(escaped_one_path)
        remove_path(escaped_two_path)
        remove_path(pivot_target)
        pivot_target.mkdir(parents=True)
        (WORKSPACE / pivot_name).symlink_to(pivot_target, target_is_directory=True)
        MANIFEST.write_text(json.dumps(dynamic_manifest, indent=2))

        try:
            result = subprocess.run(
                command,
                cwd=PROJECT,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                timeout=15,
            )
        except Exception as exc:
            failures.append(f"{script}: execution failed: {exc}")
            continue

        problems = []
        symlink_output = WORKSPACE / symlink_dest
        hardlink_output = WORKSPACE / hardlink_dest

        if not symlink_output.is_symlink():
            problems.append("unseen symlink was not created")
        elif os.readlink(symlink_output) != str(symlink_src):
            problems.append("unseen symlink did not use the absolute source path")

        if not hardlink_output.is_file() or hardlink_output.is_symlink():
            problems.append("unseen hardlink was not created as a regular hardlink")
        elif hardlink_output.stat().st_ino != hardlink_src.stat().st_ino:
            problems.append("unseen hardlink does not share the source inode")

        if not LOG.is_file():
            problems.append("escape log was not generated")
        else:
            actual_log = {
                line.strip() for line in LOG.read_text().splitlines() if line.strip()
            }
            if actual_log != expected_log:
                problems.append(
                    f"unexpected dynamic log entries: expected {sorted(expected_log)}, "
                    f"got {sorted(actual_log)}"
                )

        for escaped in (escaped_one_path, escaped_two_path, pivot_escaped_path):
            if os.path.lexists(escaped):
                problems.append(f"escaped output was created at {escaped}")

        if result.returncode != 0:
            problems.append(f"script exited with status {result.returncode}: {result.stdout}")

        if not problems:
            return
        failures.append(f"{script}: " + "; ".join(problems))

    raise AssertionError(
        "No submitted processing script correctly handled an unseen manifest:\n"
        + "\n".join(failures)
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
