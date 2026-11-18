#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import json
import os
import urllib.request
import pytest

LIB_PATH = "/home/user/lib/libchecksum.so"
SCHEMA_PATH = "/home/user/schema_v1.json"
READY_PATH = "/home/user/server_ready.txt"

ORIGINAL_SCHEMA = {
    "legacy_flag": True,
    "users": [
        {"id": 1, "name": "Alice"},
        {"id": 2, "name": "Bob"},
    ],
    "environment": "production",
}


def load_checksum_library():
    assert os.path.isfile(LIB_PATH), f"Shared library not found at {LIB_PATH}. Did you compile checksum.c?"
    try:
        library = ctypes.CDLL(LIB_PATH)
        function = library.compute_checksum
    except (OSError, AttributeError) as exc:
        pytest.fail(f"libchecksum.so is not a loadable shared library exporting compute_checksum: {exc}")
    function.argtypes = [ctypes.c_char_p, ctypes.c_int]
    function.restype = ctypes.c_uint32
    return library, function


def expected_checksum(raw):
    return sum(raw) % 256


def listening_pids(port):
    socket_inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table, "r", encoding="ascii") as stream:
                next(stream, None)
                for line in stream:
                    fields = line.split()
                    if len(fields) >= 10:
                        local_address = fields[1]
                        state = fields[3]
                        if state == "0A" and int(local_address.rsplit(":", 1)[1], 16) == port:
                            socket_inodes.add(fields[9])
        except OSError:
            pass

    pids = set()
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in socket_inodes:
                    pids.add(int(entry))
                    break
        except OSError:
            continue
    return pids


def process_maps_library(pid, library_path):
    wanted = os.path.realpath(library_path)
    try:
        with open(f"/proc/{pid}/maps", "r", encoding="utf-8", errors="replace") as stream:
            for line in stream:
                fields = line.rstrip().split(None, 5)
                if len(fields) == 6:
                    mapped_path = fields[5]
                    if mapped_path.endswith(" (deleted)"):
                        mapped_path = mapped_path[:-10]
                    if mapped_path.startswith("/") and os.path.realpath(mapped_path) == wanted:
                        return True
    except OSError:
        pass
    return False


def test_shared_library_compiled_and_functional():
    """Verify the submitted artifact is a loadable shared library implementing the legacy function."""
    _library, checksum = load_checksum_library()
    probes = [b"", b"abc", bytes(range(256)), os.urandom(257), os.urandom(1021)]
    for probe in probes:
        actual = int(checksum(probe, len(probe)))
        assert actual == expected_checksum(probe), (
            f"compute_checksum returned {actual} for a probe whose expected checksum is "
            f"{expected_checksum(probe)}"
        )


def test_server_ready_file_exists():
    """Verify that the server_ready.txt file was created."""
    assert os.path.isfile(READY_PATH), (
        f"Ready flag file not found at {READY_PATH}. Ensure the server is started and the file is created."
    )


def test_api_endpoint_response():
    """Verify the endpoint returns the complete migration and the library-derived checksum."""
    with open(SCHEMA_PATH, "r", encoding="utf-8") as stream:
        source_schema = json.load(stream)
    assert source_schema == ORIGINAL_SCHEMA, "The provided schema_v1.json was modified."

    expected_schema = dict(source_schema)
    expected_schema["account_holders"] = expected_schema.pop("users")
    expected_schema["version"] = 2
    expected_schema.pop("legacy_flag", None)

    canonical = json.dumps(
        expected_schema,
        sort_keys=True,
        separators=(",", ":"),
        ensure_ascii=True,
    ).encode("utf-8")

    _library, checksum = load_checksum_library()
    native_checksum = int(checksum(canonical, len(canonical)))
    assert native_checksum == expected_checksum(canonical), (
        "The compiled library did not produce the checksum required by the supplied legacy algorithm."
    )

    url = "http://127.0.0.1:8080/schema/v2"
    try:
        req = urllib.request.Request(url, method="GET")
        with urllib.request.urlopen(req, timeout=5) as response:
            assert response.status == 200, f"Expected HTTP status 200, got {response.status}"
            body = response.read().decode("utf-8")
    except Exception as exc:
        pytest.fail(f"Failed to connect to the API or read response: {exc}")

    try:
        data = json.loads(body)
    except json.JSONDecodeError:
        pytest.fail("API response is not valid JSON.")

    assert "checksum" in data, "Response JSON is missing the 'checksum' key."
    assert "data" in data, "Response JSON is missing the 'data' key."
    assert isinstance(data["checksum"], int) and not isinstance(data["checksum"], bool), (
        "The 'checksum' field must be an integer."
    )
    assert data["checksum"] == native_checksum, (
        f"Incorrect checksum. Expected {native_checksum}, got {data['checksum']}."
    )

    schema_data = data["data"]
    assert isinstance(schema_data, dict), "The 'data' field should be a JSON object."
    assert schema_data == expected_schema, "The returned schema is not the complete required migration."

    # Retain the original migration assertions explicitly.
    assert "account_holders" in schema_data, "Missing 'account_holders' in migrated schema."
    assert "users" not in schema_data, "The 'users' key was not renamed/removed."
    assert "version" in schema_data, "Missing 'version' in migrated schema."
    assert schema_data["version"] == 2, f"Expected version 2, got {schema_data['version']}."
    assert "legacy_flag" not in schema_data, "The 'legacy_flag' was not removed from the schema."
    assert "environment" in schema_data, "Missing 'environment' in migrated schema."
    assert schema_data["environment"] == "production", (
        f"Expected environment 'production', got {schema_data['environment']}."
    )
    assert len(schema_data["account_holders"]) == 2, "Incorrect number of account_holders."

    pids = listening_pids(8080)
    assert pids, "No process was found listening on port 8080."
    assert any(process_maps_library(pid, LIB_PATH) for pid in pids), (
        "The REST server process has not loaded /home/user/lib/libchecksum.so via FFI."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
