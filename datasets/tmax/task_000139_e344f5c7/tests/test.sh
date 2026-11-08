#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import ctypes
import importlib.util
import ipaddress
import json
import os
import random
import struct
import subprocess
import tempfile

import pytest

SO_PATH = "/home/user/build/aggregator.so"
EXE_PATH = "/home/user/build/aggregator.exe"
TRIE_PATH = "/home/user/ip_trie.py"
APP_PATH = "/home/user/app.py"
RESULTS_PATH = "/home/user/results.json"


def load_trie_module():
    name = "submitted_ip_trie_" + os.urandom(6).hex()
    spec = importlib.util.spec_from_file_location(name, TRIE_PATH)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_aggregator_so_exists_and_elf():
    """Verify aggregator.so is a loadable amd64 ELF shared library exporting GetIPs."""
    assert os.path.isfile(SO_PATH), f"File {SO_PATH} does not exist."
    with open(SO_PATH, "rb") as f:
        header = f.read(64)
    assert header[:4] == b"\x7fELF", f"File {SO_PATH} is not a valid ELF file."
    assert len(header) >= 64
    assert header[4] == 2, "aggregator.so is not a 64-bit ELF file"
    endian = "<" if header[5] == 1 else ">" if header[5] == 2 else None
    assert endian is not None, "Invalid ELF byte order"
    assert struct.unpack_from(endian + "H", header, 16)[0] == 3, "ELF is not a shared object"
    assert struct.unpack_from(endian + "H", header, 18)[0] == 62, "ELF is not amd64"
    assert os.path.getsize(SO_PATH) > 4096, "aggregator.so is implausibly small"

    lib = ctypes.CDLL(SO_PATH)
    get_ips = lib.GetIPs
    get_ips.argtypes = []
    get_ips.restype = ctypes.c_char_p
    raw = get_ips()
    assert raw is not None, "GetIPs returned NULL"
    text = raw.decode("ascii")
    ips = text.split(",") if text else []
    assert ips, "GetIPs returned no IP addresses"
    for ip in ips:
        ipaddress.IPv4Address(ip)


def test_aggregator_exe_exists_and_pe():
    """Verify aggregator.exe is a structurally valid amd64 PE executable."""
    assert os.path.isfile(EXE_PATH), f"File {EXE_PATH} does not exist."
    with open(EXE_PATH, "rb") as f:
        data = f.read()
    assert data[:2] == b"MZ", f"File {EXE_PATH} is not a valid PE (Windows) executable."
    assert len(data) > 4096, "aggregator.exe is implausibly small"
    assert len(data) >= 0x40
    pe_offset = struct.unpack_from("<I", data, 0x3C)[0]
    assert pe_offset + 24 <= len(data)
    assert data[pe_offset:pe_offset + 4] == b"PE\0\0", "Missing PE signature"
    machine, sections, _, _, _, optional_size, characteristics = struct.unpack_from(
        "<HHIIIHH", data, pe_offset + 4
    )
    assert machine == 0x8664, "aggregator.exe is not windows/amd64"
    assert sections > 0 and optional_size >= 2
    assert characteristics & 0x0002, "PE file is not marked executable"
    optional_offset = pe_offset + 24
    assert optional_offset + optional_size <= len(data)
    assert struct.unpack_from("<H", data, optional_offset)[0] == 0x20B, "PE is not PE32+"


def test_results_json_correct():
    """Verify the requested initial results.json has the correct subnet counts."""
    assert os.path.isfile(RESULTS_PATH), f"File {RESULTS_PATH} does not exist."
    with open(RESULTS_PATH, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {RESULTS_PATH} does not contain valid JSON.")
    expected = {
        "10.0.0.0/8": 50,
        "172.16.0.0/12": 30,
        "192.168.1.0/24": 20,
    }
    assert data == expected, f"Content of {RESULTS_PATH} does not match the expected output. Got: {data}"


def test_ip_trie_ast():
    """Retain the class/method checks and reject the explicitly forbidden list-comprehension query."""
    assert os.path.isfile(TRIE_PATH), f"File {TRIE_PATH} does not exist."
    with open(TRIE_PATH, "r") as f:
        source = f.read()
    try:
        tree = ast.parse(source)
    except SyntaxError as e:
        pytest.fail(f"Syntax error in {TRIE_PATH}: {e}")

    trie_class = next(
        (node for node in tree.body if isinstance(node, ast.ClassDef) and node.name == "IPTrie"),
        None,
    )
    assert trie_class is not None, "Class 'IPTrie' not found in ip_trie.py"
    methods = [n.name for n in trie_class.body if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef))]
    assert "insert" in methods, "Method 'insert' not found in IPTrie class"
    assert "count_subnet" in methods, "Method 'count_subnet' not found in IPTrie class"
    count_method = next(n for n in trie_class.body if isinstance(n, ast.FunctionDef) and n.name == "count_subnet")
    assert not any(isinstance(n, ast.ListComp) for n in ast.walk(count_method)), (
        "count_subnet must not use naive list-comprehension filtering"
    )


def test_ip_trie_randomized_behavior():
    """Exercise insert/count_subnet against independently derived answers."""
    module = load_trie_module()
    assert hasattr(module, "IPTrie")
    trie = module.IPTrie()
    rng = random.Random(int.from_bytes(os.urandom(16), "big"))

    inserted = []
    for _ in range(700):
        value = rng.getrandbits(32)
        ip = str(ipaddress.IPv4Address(value))
        repeats = 1 + (rng.randrange(4) == 0)
        for _ in range(repeats):
            trie.insert(ip)
            inserted.append(ipaddress.IPv4Address(ip))

    prefixes = [0, 1, 7, 8, 9, 12, 16, 23, 24, 25, 31, 32]
    networks = [ipaddress.IPv4Network((rng.getrandbits(32), rng.choice(prefixes)), strict=False) for _ in range(100)]
    networks += [
        ipaddress.IPv4Network("10.0.0.0/8"),
        ipaddress.IPv4Network("172.16.0.0/12"),
        ipaddress.IPv4Network("192.168.1.0/24"),
        ipaddress.IPv4Network("0.0.0.0/0"),
    ]
    for network in networks:
        expected = sum(1 for ip in inserted if ip in network)
        assert trie.count_subnet(str(network)) == expected, f"Incorrect count for {network}"


def test_app_executes_real_integration_on_unseen_input():
    """Run app.py with a temporary GetIPs implementation whose expected answers are derived here."""
    assert os.path.isfile(APP_PATH), f"File {APP_PATH} does not exist."
    rng = random.Random(int.from_bytes(os.urandom(16), "big"))
    ips = []
    for _ in range(rng.randint(7, 19)):
        ips.append(f"10.{rng.randrange(256)}.{rng.randrange(256)}.{rng.randrange(1, 255)}")
    for _ in range(rng.randint(8, 21)):
        ips.append(f"172.{rng.randrange(16, 32)}.{rng.randrange(256)}.{rng.randrange(1, 255)}")
    for _ in range(rng.randint(9, 23)):
        ips.append(f"192.168.1.{rng.randrange(1, 255)}")
    for _ in range(rng.randint(6, 15)):
        ips.append(f"192.168.2.{rng.randrange(1, 255)}")
    ips.extend(ips[:rng.randint(2, 7)])
    rng.shuffle(ips)

    networks = {
        "10.0.0.0/8": ipaddress.IPv4Network("10.0.0.0/8"),
        "172.16.0.0/12": ipaddress.IPv4Network("172.16.0.0/12"),
        "192.168.1.0/24": ipaddress.IPv4Network("192.168.1.0/24"),
    }
    expected = {
        cidr: sum(1 for ip in ips if ipaddress.IPv4Address(ip) in network)
        for cidr, network in networks.items()
    }
    assert expected != {"10.0.0.0/8": 50, "172.16.0.0/12": 30, "192.168.1.0/24": 20}

    payload = ",".join(ips).encode("ascii")
    c_bytes = ", ".join(str(b) for b in payload + b"\0")
    c_source = f"static unsigned char payload[] = {{{c_bytes}}};\nchar *GetIPs(void) {{ return (char *)payload; }}\n"

    backup = SO_PATH + ".verifier-backup"
    assert not os.path.exists(backup)
    with tempfile.TemporaryDirectory() as td:
        source_path = os.path.join(td, "fixture.c")
        fixture_path = os.path.join(td, "fixture.so")
        with open(source_path, "w") as f:
            f.write(c_source)
        subprocess.run(
            ["gcc", "-shared", "-fPIC", "-O2", "-o", fixture_path, source_path],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        os.replace(SO_PATH, backup)
        try:
            subprocess.run(
                ["python3", APP_PATH],
                cwd="/home/user",
                check=True,
                timeout=30,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                env={**os.environ, "PYTHONDONTWRITEBYTECODE": "1"},
            )
            assert os.path.isfile(RESULTS_PATH), "app.py did not generate results.json"
            with open(RESULTS_PATH, "r") as f:
                actual = json.load(f)
            assert actual == expected, f"app.py integration produced {actual}, expected {expected}"
        finally:
            if os.path.exists(SO_PATH):
                os.unlink(SO_PATH)
            os.replace(backup, SO_PATH)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
