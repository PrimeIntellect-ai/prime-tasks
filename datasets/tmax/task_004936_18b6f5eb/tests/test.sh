#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import shutil
import struct
import subprocess
import tempfile
import time
import uuid
from pathlib import Path

EXECUTABLE = "/home/user/fast_parser"
OUTPUT = "/home/user/output.pack"
LIBRARY = "/app/libdata-packer-1.0/libdatapacker.a"
SOURCE = "/home/user/parser.cpp"
ROOT = Path("/workspace/project_files")
HELPER = "/tmp/packer_expected"
DIR_HELPER = "/tmp/packer_directory_probe"


def run_checked(cmd, **kwargs):
    result = subprocess.run(cmd, capture_output=True, text=True, **kwargs)
    assert result.returncode == 0, (
        f"Command failed: {cmd}\nstdout: {result.stdout}\nstderr: {result.stderr}"
    )
    return result


def build_helpers():
    expected_src = r'''
#include "Packer.h"
#include <fstream>
#include <iterator>
#include <string>
#include <vector>

int main(int argc, char** argv) {
    if (argc != 4) return 2;
    std::ifstream in(argv[3], std::ios::binary);
    if (!in) return 3;
    std::vector<char> data((std::istreambuf_iterator<char>(in)),
                           std::istreambuf_iterator<char>());
    Packer packer(argv[1]);
    packer.add_file(argv[2], data.data(), data.size());
    packer.save();
    return 0;
}
'''
    directory_src = r'''
#include "Packer.h"
int main(int argc, char** argv) {
    if (argc != 3) return 2;
    Packer packer(argv[1]);
    packer.add_directory(argv[2]);
    packer.save();
    return 0;
}
'''
    Path("/tmp/packer_expected.cpp").write_text(expected_src)
    Path("/tmp/packer_directory_probe.cpp").write_text(directory_src)
    run_checked([
        "g++", "-std=c++17", "-O2", "-I/app/libdata-packer-1.0",
        "/tmp/packer_expected.cpp", LIBRARY, "-o", HELPER,
    ])
    run_checked([
        "g++", "-std=c++17", "-O2", "-I/app/libdata-packer-1.0",
        "/tmp/packer_directory_probe.cpp", LIBRARY, "-o", DIR_HELPER,
    ])


def expected_archive(entry_name, payload):
    payload_path = f"/tmp/payload-{uuid.uuid4().hex}.bin"
    Path(payload_path).write_bytes(payload)
    try:
        if os.path.lexists(OUTPUT):
            os.remove(OUTPUT)
        run_checked([HELPER, OUTPUT, entry_name, payload_path], timeout=5)
        assert os.path.isfile(OUTPUT), "Packer::save() did not create an archive."
        data = Path(OUTPUT).read_bytes()
        assert data, "Packer::save() created an empty archive."
        return data
    finally:
        if os.path.lexists(OUTPUT):
            os.remove(OUTPUT)
        if os.path.exists(payload_path):
            os.remove(payload_path)


def reset_dataset():
    if ROOT.exists() or ROOT.is_symlink():
        if ROOT.is_symlink():
            ROOT.unlink()
        else:
            shutil.rmtree(ROOT)
    ROOT.mkdir(parents=True)


def execute_parser(timeout=5):
    if os.path.lexists(OUTPUT):
        os.remove(OUTPUT)
    start_time = time.time()
    result = subprocess.run([EXECUTABLE], capture_output=True, timeout=timeout)
    runtime = time.time() - start_time
    assert result.returncode == 0, (
        f"Execution failed with return code {result.returncode}.\n"
        f"stdout: {result.stdout.decode(errors='replace')}\n"
        f"stderr: {result.stderr.decode(errors='replace')}"
    )
    assert os.path.isfile(OUTPUT), f"Output file {OUTPUT} was not created."
    assert os.path.getsize(OUTPUT) > 0, f"Output file {OUTPUT} is empty."
    return runtime, Path(OUTPUT).read_bytes()


def test_fixed_library_exists():
    assert os.path.isfile(LIBRARY), (
        f"Static library {LIBRARY} not found. Did you compile the fixed library?"
    )


def test_parser_source_exists():
    assert os.path.isfile(SOURCE), f"Source file {SOURCE} not found."


def test_library_api_and_cycle_fix():
    build_helpers()

    # A real packer must preserve distinctions in both payload and archive path.
    archive_a = expected_archive("one/file.bin", b"alpha\x00payload")
    archive_b = expected_archive("one/file.bin", b"beta\x00payload")
    archive_c = expected_archive("different/file.bin", b"alpha\x00payload")
    assert len({archive_a, archive_b, archive_c}) == 3, (
        "The library archive does not distinguish file paths and payload data."
    )

    library_sources = "\n".join(
        p.read_text(errors="replace")
        for p in Path("/app/libdata-packer-1.0").glob("*.[ch]*")
        if p.is_file()
    )
    assert "follow_directory_symlink" in library_sources, (
        "The library no longer follows directory symlinks."
    )
    assert re.search(
        r"visited|canonical|weakly_canonical|equivalent|st_ino|inode",
        library_sources,
        re.IGNORECASE,
    ), "No filesystem-location cycle detection was found in the library source."

    cycle_root = Path(tempfile.mkdtemp(prefix="packer-cycle-"))
    try:
        (cycle_root / "child").mkdir()
        (cycle_root / "child" / "file.bin").write_bytes(b"x")
        os.symlink(cycle_root, cycle_root / "child" / "back")
        cycle_output = "/tmp/cycle.pack"
        if os.path.lexists(cycle_output):
            os.remove(cycle_output)
        # This directly exercises the fixed vendored traversal on a parent cycle.
        run_checked([DIR_HELPER, cycle_output, str(cycle_root)], timeout=2)
    finally:
        shutil.rmtree(cycle_root)
        if os.path.lexists("/tmp/cycle.pack"):
            os.remove("/tmp/cycle.pack")


def test_fast_parser_runtime_and_output():
    executable = EXECUTABLE
    assert os.path.isfile(executable), f"Executable {executable} not found."
    assert os.access(executable, os.X_OK), f"File {executable} is not executable."

    source_text = Path(SOURCE).read_text(errors="replace")
    symbols = subprocess.run(
        ["nm", "-D", EXECUTABLE], capture_output=True, text=True
    ).stdout
    uses_mmap = re.search(r"\bmmap(?:64)?(?:@|\b)", symbols) is not None
    direct_mmap_syscall = (
        "syscall" in source_text
        and re.search(r"SYS_mmap|__NR_mmap", source_text) is not None
    )
    assert uses_mmap or direct_mmap_syscall, (
        "The submitted executable does not use mmap (or a direct mmap syscall)."
    )

    reset_dataset()
    token = uuid.uuid4().hex[:12]
    external = Path(tempfile.mkdtemp(prefix="linked-data-"))
    payload = os.urandom(257) + b"\x00DATA\xff"
    good_name = f"good-{token}.bin"
    alias_name = f"alias-{token}"
    try:
        (external / good_name).write_bytes(
            b"DATA" + struct.pack("<I", len(payload)) + payload + b"ignored trailer"
        )
        # The valid directory symlink must be followed, while this link back to
        # the dataset root must be detected as a cycle.
        os.symlink(ROOT, external / "back-to-root")
        os.symlink(external, ROOT / alias_name)

        (ROOT / "wrong-magic.bin").write_bytes(b"NOPE" + struct.pack("<I", 4) + b"junk")
        (ROOT / "truncated.bin").write_bytes(b"DATA" + struct.pack("<I", 100) + b"short")
        (ROOT / "tiny.bin").write_bytes(b"DAT")

        # Sparse 500 MiB decoy: mmap-based inspection is fast, while reading the
        # complete dataset through ordinary streams violates the runtime target.
        with open(ROOT / "large-decoy.bin", "wb") as f:
            f.truncate(500 * 1024 * 1024)

        expected = expected_archive(f"{alias_name}/{good_name}", payload)

        output_file = OUTPUT
        if os.path.exists(output_file):
            os.remove(output_file)

        runtime, actual = execute_parser(timeout=5)
        assert runtime <= 1.5, f"Runtime {runtime:.4f}s exceeded the 1.5s threshold."
        assert actual == expected, (
            "Archive contents do not match the files, relative paths, and extracted "
            "DATA payloads in the generated dataset."
        )
    finally:
        reset_dataset()
        shutil.rmtree(external)


def test_regular_file_symlink_is_archived():
    reset_dataset()
    external_dir = Path(tempfile.mkdtemp(prefix="linked-file-"))
    payload = b"regular-symlink-" + os.urandom(73)
    link_name = f"file-link-{uuid.uuid4().hex[:10]}.bin"
    target = external_dir / "target.bin"
    try:
        target.write_bytes(b"DATA" + struct.pack("<I", len(payload)) + payload)
        os.symlink(target, ROOT / link_name)
        expected = expected_archive(link_name, payload)
        _, actual = execute_parser(timeout=3)
        assert actual == expected, (
            "A valid symlink to a regular DATA file was not archived under its "
            "relative source path."
        )
    finally:
        reset_dataset()
        shutil.rmtree(external_dir)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
