#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "requests:requests"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import socket
import subprocess
import tarfile
import tempfile
import uuid
from collections import Counter
from pathlib import Path

import requests


def test_no_broken_symlinks():
    path = Path("/home/user/research_data")
    broken_symlinks = []
    for p in path.rglob("*.log"):
        if p.is_symlink() and not p.exists():
            broken_symlinks.append(p)
    assert len(broken_symlinks) == 0, f"Found broken symlinks that should have been deleted: {broken_symlinks}"


def test_tar_gz_extracted():
    # Retain the original assertion that extraction produced log files.
    path = Path("/home/user/research_data")
    log_files = list(path.rglob("*.log"))
    assert len(log_files) > 0, "No .log files found, extraction might have failed or files were deleted."

    # Verify the files from every archive originally supplied by the task.
    expected = {
        path / "subset_1" / "test1.log": (
            b"THIS RECORD HAS FIVE VOWELS A E I O U\n"
            b"---END_RECORD---\n"
            b"this record has none\n"
            b"---END_RECORD---\n"
            b"ANOTHER RECORD WITH A E I O U\n"
        ),
        path / "subset_2" / "test2.log": (
            b"JUST A NORMAL RECORD A E I O U\n"
            b"---END_RECORD---\n"
            b"SHORT\n"
        ),
    }
    for extracted_path, expected_bytes in expected.items():
        assert extracted_path.is_file(), f"Archive member was not extracted: {extracted_path}"
        assert extracted_path.read_bytes() == expected_bytes, f"Extracted archive member has incorrect contents: {extracted_path}"

    # If archives remain, check every regular member rather than merely checking
    # that some unrelated .log file exists.
    for archive_path in path.rglob("*.tar.gz"):
        with tarfile.open(archive_path, "r:gz") as archive:
            base = archive_path.parent.resolve()
            for member in archive.getmembers():
                if not member.isfile():
                    continue
                destination = (base / member.name).resolve()
                assert destination == base or base in destination.parents, f"Unsafe archive member path: {member.name}"
                assert destination.is_file(), f"Archive member was not extracted: {destination}"
                source = archive.extractfile(member)
                assert source is not None
                assert destination.read_bytes() == source.read(), f"Extracted member differs from archive: {destination}"


def test_rust_server_process_endpoint():
    # Retain the original controlled endpoint test and assertions.
    with tempfile.TemporaryDirectory() as tmpdir:
        log_path = Path(tmpdir) / "test_data.log"

        record1 = "This record has no uppercase vowels."
        record2 = "This record has A E I O U and should score eighty-five."
        record3 = "This record has A E I and should score fifty."
        record4 = "Another record with U U U U U to score high."

        with open(log_path, "w") as f:
            f.write(f"{record1}\n---END_RECORD---\n{record2}\n---END_RECORD---\n{record3}\n---END_RECORD---\n{record4}\n")

        try:
            response = requests.post("http://127.0.0.1:9090/process", data=tmpdir, timeout=5)
        except requests.exceptions.RequestException as e:
            assert False, f"Failed to connect to the Rust server on 127.0.0.1:9090 or request failed: {e}"

        assert response.status_code == 200, f"Expected HTTP 200 OK, got {response.status_code}"

        expected_output = f"{record2}\n\n{record4}\n"
        actual_records = [r.strip() for r in response.text.split("\n\n") if r.strip()]
        expected_records = [record2, record4]

        assert actual_records == expected_records, f"Server returned incorrect records. Expected: {expected_records}, Got: {actual_records}"


def score_record(record):
    result = subprocess.run(
        ["/app/log_scorer"],
        input=record,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=3,
        check=True,
    )
    return int(result.stdout.strip())


def write_records(path, records):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n---END_RECORD---\n".join(records))


def returned_records(response):
    assert response.status_code == 200, f"Expected HTTP 200 OK, got {response.status_code}"
    assert "---END_RECORD---" not in response.text, "Response included an original record separator"
    return [part.strip() for part in response.text.split("\n\n") if part.strip()]


def test_dynamic_directory_specific_recursive_processing():
    # Randomized records prevent a server from passing by returning fixed strings.
    nonce = uuid.uuid4().hex
    with tempfile.TemporaryDirectory() as parent:
        parent = Path(parent)
        first = parent / ("requested_" + uuid.uuid4().hex)
        second = parent / ("requested_" + uuid.uuid4().hex)

        first_records_root = [
            f"rhythm crypt glyph {nonce}",
            f"first high {nonce}\nA E I O U",
        ]
        first_records_nested = [
            f"nested high {nonce}\nU U U U U",
            f"short low {nonce} A E",
        ]
        second_records = [
            f"different high {nonce}\nO O O O O",
            f"different low {nonce}",
        ]

        write_records(first / "root.log", first_records_root)
        write_records(first / "deep" / "deeper" / "nested.log", first_records_nested)
        write_records(second / "only.log", second_records)

        # A high-scoring non-log file must not be processed.
        (first / "ignore.txt").write_text(f"decoy {nonce}\nA E I O U")

        expected_first = [r for r in first_records_root + first_records_nested if score_record(r) >= 75]
        expected_second = [r for r in second_records if score_record(r) >= 75]
        assert expected_first and expected_second and Counter(expected_first) != Counter(expected_second)

        response_first = requests.post("http://127.0.0.1:9090/process", data=str(first), timeout=5)
        response_second = requests.post("http://127.0.0.1:9090/process", data=str(second), timeout=5)

        actual_first = returned_records(response_first)
        actual_second = returned_records(response_second)
        assert Counter(actual_first) == Counter(expected_first), f"Incorrect result for requested directory {first}: {actual_first}"
        assert Counter(actual_second) == Counter(expected_second), f"Incorrect result for requested directory {second}: {actual_second}"

        # A third requested directory has no qualifying records, so constants fail.
        empty_result_dir = parent / ("no_matches_" + uuid.uuid4().hex)
        write_records(empty_result_dir / "deep" / "low.log", [f"rhythm {nonce}", f"A E {nonce}"])
        response_empty = requests.post("http://127.0.0.1:9090/process", data=str(empty_result_dir), timeout=5)
        assert returned_records(response_empty) == [], "Server returned records for a directory with no score >= 75"


def listening_pids(port):
    socket_inodes = set()
    wanted_port = f"{port:04X}"
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            local_address = fields[1]
            state = fields[3]
            inode = fields[9]
            if local_address.rsplit(":", 1)[-1].upper() == wanted_port and state == "0A":
                socket_inodes.add(inode)

    owners = set()
    for proc_dir in Path("/proc").iterdir():
        if not proc_dir.name.isdigit():
            continue
        fd_dir = proc_dir / "fd"
        try:
            for fd in fd_dir.iterdir():
                try:
                    target = os.readlink(fd)
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in socket_inodes:
                    owners.add(int(proc_dir.name))
        except (OSError, PermissionError):
            continue
    return owners


def test_listener_is_a_rust_executable():
    pids = listening_pids(9090)
    assert pids, "No process owns a listening socket on port 9090"

    rust_owners = []
    details = []
    for pid in pids:
        exe_link = Path(f"/proc/{pid}/exe")
        try:
            exe_name = os.readlink(exe_link)
            binary = exe_link.read_bytes()
        except OSError as exc:
            details.append(f"pid {pid}: {exc}")
            continue
        is_elf = binary.startswith(b"\x7fELF")
        has_rust_runtime = b"/rustc/" in binary or b"rust_begin_unwind" in binary
        details.append(f"pid {pid}: {exe_name}, ELF={is_elf}, RustRuntime={has_rust_runtime}")
        if is_elf and has_rust_runtime:
            rust_owners.append(pid)

    assert rust_owners, "The process actually listening on port 9090 is not a Rust executable: " + "; ".join(details)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
