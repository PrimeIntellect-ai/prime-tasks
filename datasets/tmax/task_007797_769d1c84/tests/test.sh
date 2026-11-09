#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import tarfile
import tempfile
from datetime import datetime, timezone

SOURCE_ARCHIVE = "/home/user/research_data/raw_dump.tar.gz"
WORKSPACE = "/home/user/workspace"
ORGANIZED = "/home/user/organized_dataset"
DATA_DIR = os.path.join(ORGANIZED, "data")
CLEAN_ARCHIVE = "/home/user/clean_dataset.tar.gz"


def normalized_member_name(name):
    name = name.rstrip("/")
    while name.startswith("./"):
        name = name[2:]
    return name


def source_members():
    with tarfile.open(SOURCE_ARCHIVE, "r:gz") as tar:
        members = tar.getmembers()
        names = [normalized_member_name(m.name) for m in members]
        assert len(names) == len(set(names)), "Source archive contains duplicate member names."
        return members


def test_workspace_extracted():
    workspace_dir = "/home/user/workspace/messy"
    assert os.path.isdir(workspace_dir), f"Expected extracted directory {workspace_dir} to exist."
    assert os.path.isfile(os.path.join(workspace_dir, "dir1/alpha.dat")), "alpha.dat missing in workspace."
    assert os.path.isfile(os.path.join(workspace_dir, "dir3/delta.dat")), "delta.dat missing in workspace."
    assert os.path.isfile(os.path.join(workspace_dir, "logs/run2.log")), "run2.log missing in workspace."

    expected_entries = set()
    with tarfile.open(SOURCE_ARCHIVE, "r:gz") as tar:
        for member in tar.getmembers():
            name = normalized_member_name(member.name)
            assert name and not os.path.isabs(name), f"Invalid source member path: {member.name}"
            assert ".." not in name.split("/"), f"Invalid source member path: {member.name}"
            expected_entries.add(name)
            path = os.path.join(WORKSPACE, name)

            if member.isdir():
                assert os.path.isdir(path) and not os.path.islink(path), f"Directory {name} was not extracted correctly."
            elif member.isfile():
                assert os.path.isfile(path) and not os.path.islink(path), f"File {name} was not extracted correctly."
                assert os.path.getsize(path) == member.size, f"File {name} has the wrong size."
                assert int(os.stat(path).st_mtime) == int(member.mtime), f"File {name} has the wrong modification time."
                archived = tar.extractfile(member)
                assert archived is not None
                with archived, open(path, "rb") as actual:
                    assert actual.read() == archived.read(), f"File {name} does not match the source archive."
            elif member.issym():
                assert os.path.islink(path), f"Symlink {name} was not extracted correctly."
                assert os.readlink(path) == member.linkname, f"Symlink {name} has the wrong target."
            else:
                assert False, f"Unsupported source archive member type for {name}."

    actual_entries = set()
    for root, dirs, files in os.walk(WORKSPACE, followlinks=False):
        for entry in dirs + files:
            actual_entries.add(os.path.relpath(os.path.join(root, entry), WORKSPACE))
    assert actual_entries == expected_entries, "Workspace does not exactly contain the full extracted source archive."


def qualifying_data_files():
    cutoff = datetime(2023, 1, 1, tzinfo=timezone.utc).timestamp()
    matches = []
    for root, dirs, files in os.walk(WORKSPACE, followlinks=False):
        for filename in files:
            path = os.path.join(root, filename)
            if filename.endswith(".dat") and not os.path.islink(path):
                st = os.stat(path)
                if st.st_mtime > cutoff and st.st_size > 10240:
                    matches.append(path)
    return sorted(matches, key=lambda p: (os.path.basename(p), p))


def test_organized_dataset_hardlinks():
    data_dir = "/home/user/organized_dataset/data"
    assert os.path.isdir(data_dir), f"Directory {data_dir} does not exist."

    sub1 = os.path.join(data_dir, "subject_001.dat")
    sub2 = os.path.join(data_dir, "subject_002.dat")

    assert os.path.isfile(sub1), f"File {sub1} does not exist."
    assert os.path.isfile(sub2), f"File {sub2} does not exist."
    assert os.path.getsize(sub1) == 15000, f"{sub1} has incorrect size. Expected 15000 bytes."
    assert os.path.getsize(sub2) == 12000, f"{sub2} has incorrect size. Expected 12000 bytes."

    alpha_path = "/home/user/workspace/messy/dir1/alpha.dat"
    delta_path = "/home/user/workspace/messy/dir3/delta.dat"
    assert os.path.exists(alpha_path), f"{alpha_path} does not exist."
    assert os.path.exists(delta_path), f"{delta_path} does not exist."
    assert os.stat(sub1).st_ino == os.stat(alpha_path).st_ino, f"{sub1} is not a hard link to {alpha_path}."
    assert os.stat(sub2).st_ino == os.stat(delta_path).st_ino, f"{sub2} is not a hard link to {delta_path}."

    sources = qualifying_data_files()
    expected_names = [f"subject_{i:03d}.dat" for i in range(1, len(sources) + 1)]
    assert sorted(os.listdir(data_dir)) == expected_names, "organized_dataset/data has missing, extra, or incorrectly named entries."

    for name, source in zip(expected_names, sources):
        linked = os.path.join(data_dir, name)
        assert os.path.isfile(linked) and not os.path.islink(linked), f"{linked} is not a regular file."
        source_stat = os.stat(source)
        linked_stat = os.stat(linked)
        assert (linked_stat.st_dev, linked_stat.st_ino) == (source_stat.st_dev, source_stat.st_ino), \
            f"{linked} is not a hard link to {source}."
        assert linked_stat.st_size == source_stat.st_size, f"{linked} has the wrong size."


def latest_log():
    logs = []
    for root, dirs, files in os.walk(WORKSPACE, followlinks=False):
        for filename in files:
            path = os.path.join(root, filename)
            if filename.endswith(".log") and not os.path.islink(path):
                logs.append(path)
    assert logs, "No log files were extracted."
    newest_time = max(os.stat(path).st_mtime_ns for path in logs)
    newest = [path for path in logs if os.stat(path).st_mtime_ns == newest_time]
    assert len(newest) == 1, "Source archive does not have a single newest log."
    return newest[0]


def test_organized_dataset_symlink():
    symlink_path = "/home/user/organized_dataset/latest_run.log"
    assert os.path.islink(symlink_path), f"{symlink_path} is not a symbolic link."

    target = os.readlink(symlink_path)
    resolved_target = os.path.abspath(os.path.join(os.path.dirname(symlink_path), target))
    expected_target = "/home/user/workspace/messy/logs/run2.log"
    assert resolved_target == expected_target, f"Symlink points to {resolved_target}, expected {expected_target}."
    assert os.path.realpath(symlink_path) == os.path.realpath(latest_log()), "Symlink does not point to the newest extracted log."


def test_clean_dataset_archive():
    archive_path = "/home/user/clean_dataset.tar.gz"
    assert os.path.isfile(archive_path), f"Archive {archive_path} does not exist."

    expected_data_names = [f"subject_{i:03d}.dat" for i in range(1, len(qualifying_data_files()) + 1)]
    expected_files = {f"organized_dataset/data/{name}" for name in expected_data_names}
    expected_files.add("organized_dataset/latest_run.log")
    allowed_names = expected_files | {"organized_dataset", "organized_dataset/data"}

    with tarfile.open(archive_path, "r:gz") as tar:
        members = tar.getmembers()
        names = [normalized_member_name(member.name) for member in members]
        assert len(names) == len(set(names)), "Archive contains duplicate member names."
        assert any(name == "organized_dataset" or name.startswith("organized_dataset/") for name in names), \
            "Archive does not contain 'organized_dataset' at its root."

        original_expected_files = [
            "organized_dataset/data/subject_001.dat",
            "organized_dataset/data/subject_002.dat",
            "organized_dataset/latest_run.log"
        ]
        for ef in original_expected_files:
            assert any(name.endswith(ef) for name in names), f"Expected file {ef} missing in archive."

        assert set(names).issubset(allowed_names), "Archive contains extra or incorrectly rooted members."
        assert expected_files.issubset(set(names)), "Archive is missing organized dataset files."
        assert "organized_dataset" in set(names), "Archive lacks an explicit organized_dataset root directory."

        by_name = {normalized_member_name(member.name): member for member in members}
        for name in expected_data_names:
            archive_name = f"organized_dataset/data/{name}"
            member = by_name[archive_name]
            assert member.isfile(), f"{archive_name} is not archived as a regular file."
            extracted_stream = tar.extractfile(member)
            assert extracted_stream is not None
            with extracted_stream, open(os.path.join(DATA_DIR, name), "rb") as live:
                assert extracted_stream.read() == live.read(), f"Archived content for {name} is incorrect."

        link_member = by_name["organized_dataset/latest_run.log"]
        assert link_member.issym(), "latest_run.log is not a symbolic link in the archive."
        assert link_member.linkname == os.readlink(os.path.join(ORGANIZED, "latest_run.log")), \
            "Archived latest_run.log has the wrong link target."

        with tempfile.TemporaryDirectory() as tempdir:
            tar.extractall(tempdir)
            extracted_root = os.path.join(tempdir, "organized_dataset")
            assert os.path.isdir(extracted_root), "Extracting the final archive did not yield organized_dataset/."
            extracted_data = os.path.join(extracted_root, "data")
            assert sorted(os.listdir(extracted_data)) == expected_data_names, "Extracted final archive has incorrect data files."
            for name in expected_data_names:
                extracted_path = os.path.join(extracted_data, name)
                live_path = os.path.join(DATA_DIR, name)
                assert os.path.isfile(extracted_path) and not os.path.islink(extracted_path)
                with open(extracted_path, "rb") as archived, open(live_path, "rb") as live:
                    assert archived.read() == live.read(), f"Extracted archive content for {name} is incorrect."
            extracted_link = os.path.join(extracted_root, "latest_run.log")
            assert os.path.islink(extracted_link), "Extracted latest_run.log is not a symlink."
            assert os.readlink(extracted_link) == os.readlink(os.path.join(ORGANIZED, "latest_run.log")), \
                "Extracted latest_run.log has the wrong target."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
