#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import tarfile
import csv
import subprocess
import time
import uuid
from pathlib import Path, PurePosixPath

DATA_VOLUME = Path("/home/user/data_volume")


def test_csv_report():
    report_path = Path("/home/user/archive_report.csv")
    assert report_path.exists(), f"Report file {report_path} is missing."
    assert report_path.is_file(), f"Report {report_path} must be a regular file."

    with open(report_path, "r", newline="", encoding="utf-8") as f:
        reader = csv.reader(f)
        rows = list(reader)

    assert len(rows) > 0, "CSV report is empty."
    assert rows[0] == ["filepath", "new_status"], f"CSV header mismatch. Got: {rows[0]}"

    data_rows = rows[1:]
    expected_rows = [
        ["dir D/file 5.json", "archived"],
        ["dir_A/file1.json", "archived"]
    ]

    assert data_rows == expected_rows, (
        f"CSV data rows mismatch or not sorted correctly.\n"
        f"Expected: {expected_rows}\n"
        f"Got:      {data_rows}"
    )


def test_tarball_archive():
    tar_path = Path("/home/user/cold_storage.tar.gz")
    assert tar_path.exists(), f"Archive {tar_path} is missing."
    assert tarfile.is_tarfile(tar_path), f"File {tar_path} is not a valid tar archive."

    expected_files = {
        "dir D/file 5.json",
        "dir_A/file1.json"
    }

    with tarfile.open(tar_path, "r:gz") as tar:
        members = tar.getmembers()
        file_members = [m for m in members if m.isfile()]
        archived_paths = {m.name for m in file_members}
        normalized_paths = {p.lstrip("./") for p in archived_paths}

        assert normalized_paths == expected_files, (
            f"Tarball contents mismatch.\n"
            f"Expected: {expected_files}\n"
            f"Got:      {normalized_paths}"
        )

        for member in file_members:
            norm_name = member.name.lstrip("./")
            if norm_name in expected_files:
                f = tar.extractfile(member)
                assert f is not None, f"Could not read {member.name} from archive."
                content = f.read().decode("utf-8")
                try:
                    data = json.loads(content)
                except json.JSONDecodeError:
                    assert False, f"Archived file {member.name} is not valid JSON."

                assert data.get("status") == "archived", (
                    f"Archived file {member.name} does not have status 'archived'. "
                    f"Got: {data.get('status')}"
                )


def test_active_volume_cleanup():
    data_volume = Path("/home/user/data_volume")

    deleted_files = [
        "dir_A/file1.json",
        "dir D/file 5.json"
    ]
    for rel_path in deleted_files:
        file_path = data_volume / rel_path
        assert not file_path.exists(), f"File {file_path} should have been deleted from active volume."

    untouched_files = {
        "dir_A/file2.json": {"id": 2, "status": "archivable", "data": "content B"},
        "dir_B/sub_C/file3.json": {"id": 3, "status": "archivable", "data": "content C"},
        "dir_B/sub_C/file4.json": {"id": 4, "status": "active", "data": "content D"}
    }

    for rel_path, expected_content in untouched_files.items():
        file_path = data_volume / rel_path
        assert file_path.exists(), f"File {file_path} should not have been deleted."

        with open(file_path, "r", encoding="utf-8") as f:
            try:
                data = json.load(f)
            except json.JSONDecodeError:
                assert False, f"File {file_path} is no longer valid JSON."

            assert data == expected_content, (
                f"Content of {file_path} was modified.\n"
                f"Expected: {expected_content}\n"
                f"Got:      {data}"
            )


def _write_json(path, value, age_days):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False) + "\n", encoding="utf-8")
    stamp = time.time() - age_days * 86400
    os.utime(path, (stamp, stamp))


def _normalized_member_name(name):
    while name.startswith("./"):
        name = name[2:]
    return name


def test_zz_execute_bash_script_on_derived_filesystem_state():
    scripts = sorted(
        p for p in Path("/home/user").rglob("*.sh")
        if p.is_file() and not p.is_symlink()
    )
    assert scripts, "No Bash script was written under /home/user."
    assert len(scripts) == 1, f"Expected one submitted Bash script, found: {scripts}"
    script = scripts[0]

    syntax = subprocess.run(
        ["bash", "-n", str(script)], capture_output=True, text=True, timeout=20
    )
    assert syntax.returncode == 0, f"Submitted Bash script has invalid syntax: {syntax.stderr}"

    token = uuid.uuid4().hex
    fixture_root = DATA_VOLUME / f"verification {token} [special]"
    _write_json(fixture_root / f"eligible one;{token}.json",
                {"id": token, "status": "archivable", "data": "old one"}, 45)
    _write_json(fixture_root / "nested dir" / f"eligible_two_{token}.json",
                {"id": token + "-2", "status": "archivable", "data": [1, 2, 3]}, 70)
    locked = fixture_root / f"locked file {token}.json"
    _write_json(locked, {"id": "locked", "status": "archivable"}, 60)
    Path(str(locked) + ".lock").write_text("locked\n", encoding="utf-8")
    _write_json(fixture_root / f"new_{token}.json",
                {"id": "new", "status": "archivable"}, 2)
    _write_json(fixture_root / f"active_{token}.json",
                {"id": "active", "status": "active"}, 80)
    _write_json(fixture_root / f"missing_{token}.json",
                {"id": "missing", "data": "no status"}, 80)
    _write_json(fixture_root / f"nested_status_{token}.json",
                {"id": "nested", "metadata": {"status": "archivable"}}, 80)
    invalid = fixture_root / f"invalid_{token}.json"
    invalid.write_text("{not valid json\n", encoding="utf-8")
    old_stamp = time.time() - 80 * 86400
    os.utime(invalid, (old_stamp, old_stamp))

    cutoff = time.time() - 30 * 86400
    expected = {}
    untouched = {}
    for path in DATA_VOLUME.rglob("*.json"):
        if not path.is_file():
            continue
        rel = path.relative_to(DATA_VOLUME).as_posix()
        raw = path.read_bytes()
        eligible = False
        parsed = None
        try:
            parsed = json.loads(raw.decode("utf-8"))
            eligible = (
                path.stat().st_mtime < cutoff
                and not Path(str(path) + ".lock").exists()
                and isinstance(parsed, dict)
                and parsed.get("status") == "archivable"
            )
        except (UnicodeDecodeError, json.JSONDecodeError):
            pass

        if eligible:
            archived = dict(parsed)
            archived["status"] = "archived"
            expected[rel] = archived
        else:
            untouched[rel] = raw

    assert len(expected) >= 2, "Verifier failed to construct eligible test files."

    result = subprocess.run(
        ["bash", str(script)], capture_output=True, text=True, timeout=120,
        cwd=str(script.parent)
    )
    assert result.returncode == 0, (
        f"Submitted script failed when executed.\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )

    for rel in expected:
        assert not (DATA_VOLUME / rel).exists(), f"Archived source was not deleted: {rel}"
    for rel, original_bytes in untouched.items():
        path = DATA_VOLUME / rel
        assert path.exists(), f"Ineligible JSON file was deleted: {rel}"
        assert path.read_bytes() == original_bytes, f"Ineligible JSON file was modified: {rel}"
    assert Path(str(locked) + ".lock").is_file(), "The lock file was removed."
    assert fixture_root.is_dir(), "A source directory was deleted."
    assert (fixture_root / "nested dir").is_dir(), "A nested source directory was deleted."

    report_path = Path("/home/user/archive_report.csv")
    assert report_path.is_file(), "CSV report was not created by the executed script."
    with report_path.open("r", newline="", encoding="utf-8") as f:
        rows = list(csv.reader(f))
    expected_rows = [[rel, "archived"] for rel in sorted(expected)]
    assert rows == [["filepath", "new_status"], *expected_rows], (
        f"Dynamically derived CSV mismatch. Expected {expected_rows}, got {rows[1:]}"
    )

    tar_path = Path("/home/user/cold_storage.tar.gz")
    assert tar_path.is_file(), "Archive was not created by the executed script."
    try:
        tar = tarfile.open(tar_path, "r:gz")
    except (tarfile.TarError, OSError) as exc:
        assert False, f"Output is not a gzip-compressed tar archive: {exc}"

    with tar:
        members = tar.getmembers()
        assert all(member.isfile() for member in members), "Archive contains non-file entries."
        normalized = []
        for member in members:
            name = _normalized_member_name(member.name)
            pure = PurePosixPath(name)
            assert not pure.is_absolute(), f"Archive contains an absolute path: {member.name}"
            assert name and ".." not in pure.parts, f"Archive contains an unsafe path: {member.name}"
            normalized.append(name)
        assert len(normalized) == len(set(normalized)), "Archive contains duplicate file entries."
        assert set(normalized) == set(expected), (
            f"Dynamically derived archive mismatch. Expected {set(expected)}, got {set(normalized)}"
        )

        by_name = {_normalized_member_name(m.name): m for m in members}
        for rel, expected_json in expected.items():
            extracted = tar.extractfile(by_name[rel])
            assert extracted is not None, f"Could not read archived member {rel}"
            try:
                actual_json = json.loads(extracted.read().decode("utf-8"))
            except (UnicodeDecodeError, json.JSONDecodeError) as exc:
                assert False, f"Archived member {rel} is not valid JSON: {exc}"
            assert actual_json == expected_json, (
                f"Archived JSON {rel} was not preserved except for its status. "
                f"Expected {expected_json}, got {actual_json}"
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
