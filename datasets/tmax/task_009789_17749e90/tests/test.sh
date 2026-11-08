#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import shutil
import struct
import subprocess
import sys
import sysconfig

PROJECT = "/home/user/pcap_parser"
RESULT = "/home/user/crash_packet.txt"


def test_crash_packet_file_exists():
    """Check that the crash_packet.txt file has been created."""
    assert os.path.isfile(RESULT), f"File {RESULT} does not exist. Did you save the packet number?"


def test_crash_packet_content():
    """Verify that the crash_packet.txt file contains the correct packet number."""
    assert os.path.isfile(RESULT), f"File {RESULT} does not exist."
    with open(RESULT, "r") as f:
        content = f.read().strip()
    assert content == "42", f"Expected crash packet number '42', but got '{content}'."


def test_extension_builds_and_program_reproduces_crash():
    setup_py = os.path.join(PROJECT, "setup.py")
    assert os.path.isfile(setup_py), "setup.py is missing"

    # Force setup.py to produce the extension from the submitted source rather
    # than accepting an extension left over from an earlier build.
    shutil.rmtree(os.path.join(PROJECT, "build"), ignore_errors=True)
    for path in glob.glob(os.path.join(PROJECT, "fastparser*.so")):
        os.remove(path)

    built = subprocess.run(
        [sys.executable, "setup.py", "build_ext", "--inplace"],
        cwd=PROJECT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=120,
    )
    assert built.returncode == 0, "Extension build failed:\n" + built.stdout

    suffix = sysconfig.get_config_var("EXT_SUFFIX") or ".so"
    candidates = glob.glob(os.path.join(PROJECT, "fastparser*" + suffix))
    assert candidates, "setup.py did not build an in-place fastparser extension"
    with open(candidates[0], "rb") as f:
        assert f.read(4) == b"\x7fELF", "fastparser output is not a native ELF extension"

    run = subprocess.run(
        [sys.executable, "main.py", "traffic.pcap"],
        cwd=PROJECT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    output = run.stdout + run.stderr
    assert run.returncode != 0, "main.py unexpectedly completed without the packet crash"
    assert "ValueError" in output, "main.py did not terminate with the expected ValueError:\n" + output


def test_reported_index_matches_extension_on_capture():
    # Import the freshly built native extension and independently enumerate the
    # capture, deriving the first packet that raises ValueError.
    sys.path.insert(0, PROJECT)
    import fastparser

    assert os.path.realpath(fastparser.__file__).startswith(os.path.realpath(PROJECT) + os.sep)

    first_bad = None
    with open(os.path.join(PROJECT, "traffic.pcap"), "rb") as f:
        global_header = f.read(24)
        assert len(global_header) == 24, "traffic.pcap has a truncated global header"
        packet_num = 1
        while True:
            header = f.read(16)
            if not header:
                break
            assert len(header) == 16, "traffic.pcap has a truncated packet header"
            _, _, incl_len, _ = struct.unpack("<IIII", header)
            payload = f.read(incl_len)
            assert len(payload) == incl_len, "traffic.pcap has a truncated packet payload"
            try:
                fastparser.parse_packet(payload)
            except ValueError:
                first_bad = packet_num
                break
            packet_num += 1

    assert first_bad is not None, "The built extension did not reject any packet in traffic.pcap"
    with open(RESULT, "r") as f:
        reported = f.read().strip()
    assert reported == str(first_bad), (
        f"crash_packet.txt reports {reported}, but the built extension first raises "
        f"ValueError on packet {first_bad}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
