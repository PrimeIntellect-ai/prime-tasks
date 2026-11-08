#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import os
import secrets
import subprocess
import sys

import numpy as np
from scapy.all import Ether, IP, Raw, TCP, rdpcap, wrpcap

WORKSPACE_DIR = "/home/user/workspace"
FLAG_PATH = os.path.join(WORKSPACE_DIR, "flag.txt")
ANALYZE_SCRIPT_PATH = os.path.join(WORKSPACE_DIR, "analyze.py")
PCAP_PATH = os.path.join(WORKSPACE_DIR, "traffic.pcap")


def decoder_so_files():
    return glob.glob(os.path.join(WORKSPACE_DIR, "decoder*.so"))


def extract_payload(path):
    payloads = []
    for packet in rdpcap(path):
        if packet.haslayer(TCP) and packet[TCP].dport == 8080 and packet.haslayer(Raw):
            payloads.append(json.loads(bytes(packet[Raw].load).decode("utf-8")))
    assert len(payloads) == 1, f"Expected one TCP/8080 JSON payload, found {len(payloads)}"
    assert isinstance(payloads[0], list)
    assert all(isinstance(value, int) for value in payloads[0])
    return payloads[0]


def run_analyze():
    return subprocess.run(
        [sys.executable, ANALYZE_SCRIPT_PATH],
        cwd=WORKSPACE_DIR,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )


def test_flag_file_exists_and_correct():
    assert os.path.isfile(FLAG_PATH), f"Flag file not found at {FLAG_PATH}"
    with open(FLAG_PATH, "r") as f:
        content = f.read().strip()
    expected_value = "45"
    assert content == expected_value, f"Flag content is incorrect. Expected '{expected_value}', got '{content}'."


def test_analyze_script_exists():
    assert os.path.isfile(ANALYZE_SCRIPT_PATH), f"Analysis script not found at {ANALYZE_SCRIPT_PATH}"


def test_extension_compiled():
    so_files = decoder_so_files()
    assert len(so_files) > 0, "Compiled decoder extension (.so file) not found in the workspace. Build may have failed or was not run in-place."


def test_setup_can_build_extension_in_place():
    old_files = decoder_so_files()
    backups = []
    try:
        for index, path in enumerate(old_files):
            backup = path + f".pre_verifier_{index}"
            os.replace(path, backup)
            backups.append((path, backup))

        result = subprocess.run(
            [sys.executable, "setup.py", "build_ext", "--inplace", "--force"],
            cwd=WORKSPACE_DIR,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=120,
        )
        assert result.returncode == 0, f"Extension rebuild failed:\n{result.stdout}\n{result.stderr}"
        assert decoder_so_files(), "setup.py did not create an in-place decoder shared object"
    except BaseException:
        for path in decoder_so_files():
            os.remove(path)
        for original, backup in backups:
            os.replace(backup, original)
        raise
    else:
        for _, backup in backups:
            os.remove(backup)


def test_compiled_decoder_behavior():
    probe = [7, -3, 19, 41]
    expected = sum(value * (index + 1) for index, value in enumerate(probe)) % 9973
    code = (
        "import decoder, numpy as np; "
        f"a=np.array({probe!r}, dtype=np.int64); "
        "print(decoder.decode(a))"
    )
    result = subprocess.run(
        [sys.executable, "-c", code],
        cwd=WORKSPACE_DIR,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, f"Compiled decoder could not be imported or called: {result.stderr}"
    assert result.stdout.strip() == str(expected)


def test_analyze_executes_against_real_artifacts():
    payload = extract_payload(PCAP_PATH)
    expected = sum(value * (index + 1) for index, value in enumerate(payload)) % 9973
    if os.path.exists(FLAG_PATH):
        os.remove(FLAG_PATH)

    result = run_analyze()
    assert result.returncode == 0, f"analyze.py failed:\n{result.stdout}\n{result.stderr}"
    assert os.path.isfile(FLAG_PATH), "analyze.py did not create flag.txt"
    with open(FLAG_PATH) as f:
        assert f.read().strip() == str(expected)


def test_analyze_extracts_pcap_and_calls_decoder_with_int64_array():
    original_pcap = open(PCAP_PATH, "rb").read()
    original_flag = open(FLAG_PATH, "rb").read() if os.path.exists(FLAG_PATH) else None
    decoder_py = os.path.join(WORKSPACE_DIR, "decoder.py")
    original_decoder_py = open(decoder_py, "rb").read() if os.path.exists(decoder_py) else None
    call_log = "/tmp/decoder_call.json"
    sentinel = 8123457
    probe = [secrets.randbelow(200000) - 100000 for _ in range(7)]
    moved_extensions = []

    try:
        packet = Ether()/IP(dst="192.168.1.100")/TCP(dport=8080)/Raw(load=json.dumps(probe).encode())
        wrpcap(PCAP_PATH, [packet])

        for index, path in enumerate(decoder_so_files()):
            backup = path + f".verifier_probe_{index}"
            os.replace(path, backup)
            moved_extensions.append((path, backup))

        if os.path.exists(call_log):
            os.remove(call_log)
        cache_dir = os.path.join(WORKSPACE_DIR, "__pycache__")
        for cached in glob.glob(os.path.join(cache_dir, "decoder*.pyc")):
            os.remove(cached)

        with open(decoder_py, "w") as f:
            f.write(
                "import json\n"
                "import numpy as np\n"
                "def decode(data):\n"
                "    record = {\n"
                "        'is_ndarray': isinstance(data, np.ndarray),\n"
                "        'dtype': str(getattr(data, 'dtype', None)),\n"
                "        'ndim': getattr(data, 'ndim', None),\n"
                "        'values': data.tolist() if isinstance(data, np.ndarray) else None,\n"
                "    }\n"
                f"    with open({call_log!r}, 'w') as out: json.dump(record, out)\n"
                f"    return {sentinel}\n"
            )

        if os.path.exists(FLAG_PATH):
            os.remove(FLAG_PATH)
        result = run_analyze()
        assert result.returncode == 0, f"analyze.py failed on a valid PCAP payload:\n{result.stdout}\n{result.stderr}"
        assert os.path.isfile(call_log), "analyze.py did not import decoder and call decoder.decode()"
        with open(call_log) as f:
            record = json.load(f)
        assert record["is_ndarray"], "decoder.decode() was not passed a NumPy array"
        assert record["dtype"] == "int64", f"Expected numpy.int64 data, got {record['dtype']}"
        assert record["ndim"] == 1
        assert record["values"] == probe, "The array passed to decode() was not extracted from traffic.pcap"
        assert os.path.isfile(FLAG_PATH), "analyze.py did not write flag.txt"
        with open(FLAG_PATH) as f:
            assert f.read().strip() == str(sentinel), "flag.txt was not written from decoder.decode()'s return value"
    finally:
        with open(PCAP_PATH, "wb") as f:
            f.write(original_pcap)
        if original_flag is None:
            if os.path.exists(FLAG_PATH):
                os.remove(FLAG_PATH)
        else:
            with open(FLAG_PATH, "wb") as f:
                f.write(original_flag)
        if original_decoder_py is None:
            if os.path.exists(decoder_py):
                os.remove(decoder_py)
        else:
            with open(decoder_py, "wb") as f:
                f.write(original_decoder_py)
        for original, backup in moved_extensions:
            os.replace(backup, original)
        if os.path.exists(call_log):
            os.remove(call_log)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
