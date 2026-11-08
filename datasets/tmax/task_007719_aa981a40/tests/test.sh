#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib
import os
from pathlib import Path
import subprocess
import sys
import tempfile

EXPECTED_METHODS = [
    "CreateItem",
    "DeleteItem",
    "GetItem",
    "ListItems",
    "UpdateItem",
]
REPO = Path("/home/user/repo")
PROTO = REPO / "inventory.proto"
PB2 = REPO / "inventory_pb2.py"
PB2_GRPC = REPO / "inventory_pb2_grpc.py"
MANIFEST = Path("/home/user/rpc_methods.txt")


def test_compiled_pb2_files_exist():
    assert PB2.is_file(), f"Expected file {PB2} does not exist. Did you compile the proto file?"
    assert PB2_GRPC.is_file(), f"Expected file {PB2_GRPC} does not exist. Did you compile the proto file with grpc stubs?"


def test_rpc_methods_txt_exists_and_correct():
    assert MANIFEST.is_file(), f"Expected file {MANIFEST} does not exist."

    with MANIFEST.open("r") as f:
        content = f.read().strip().splitlines()

    # Preserve the original expected-list assertion.
    actual_methods = [line.strip() for line in content if line.strip()]
    assert actual_methods == EXPECTED_METHODS, (
        f"Contents of {MANIFEST} do not match the expected sorted method names. "
        f"Expected {EXPECTED_METHODS}, got {actual_methods}."
    )

    # Also enforce exactly one unadorned method name per line.
    raw = MANIFEST.read_text()
    assert raw.splitlines() == EXPECTED_METHODS, (
        "rpc_methods.txt contains blank lines or extra leading/trailing whitespace"
    )


def test_inventory_proto_is_fixed():
    assert PROTO.is_file(), f"File {PROTO} does not exist."
    content = PROTO.read_text()

    assert "rpc CreateItem" in content, "The CreateItem rpc is missing from the proto file. Was the patch applied?"
    assert "rpc UpdateItem" in content, "The UpdateItem rpc is missing from the proto file. Was the patch applied?"

    lines = content.splitlines()
    create_item_line = next((line for line in lines if "rpc CreateItem" in line), None)
    assert create_item_line is not None, "Could not find 'rpc CreateItem' line."
    assert create_item_line.strip().endswith(";"), "The 'rpc CreateItem' line is missing the closing semicolon."


def test_proto_compiles_and_generated_artifacts_are_current():
    assert PROTO.is_file()
    assert PB2.is_file()
    assert PB2_GRPC.is_file()

    # Compile the submitted proto independently. This validates the complete proto
    # and provides canonical generated files for the installed compiler.
    with tempfile.TemporaryDirectory() as output_dir:
        result = subprocess.run(
            [
                sys.executable,
                "-m",
                "grpc_tools.protoc",
                f"-I{REPO}",
                f"--python_out={output_dir}",
                f"--grpc_python_out={output_dir}",
                str(PROTO),
            ],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        assert result.returncode == 0, f"inventory.proto does not compile:\n{result.stderr}"

        canonical_pb2 = Path(output_dir) / "inventory_pb2.py"
        canonical_pb2_grpc = Path(output_dir) / "inventory_pb2_grpc.py"
        assert canonical_pb2.is_file() and canonical_pb2_grpc.is_file()
        assert PB2.read_bytes() == canonical_pb2.read_bytes(), (
            "inventory_pb2.py is not the output of compiling the final inventory.proto"
        )
        assert PB2_GRPC.read_bytes() == canonical_pb2_grpc.read_bytes(), (
            "inventory_pb2_grpc.py is not the output of compiling the final inventory.proto"
        )

    # Execute/import both submitted generated artifacts and inspect the compiled
    # service descriptor rather than relying only on text greps.
    sys.path.insert(0, str(REPO))
    importlib.invalidate_caches()
    pb2 = importlib.import_module("inventory_pb2")
    pb2_grpc = importlib.import_module("inventory_pb2_grpc")

    service = pb2.DESCRIPTOR.services_by_name.get("InventoryService")
    assert service is not None, "Compiled descriptor has no InventoryService"
    descriptor_methods = sorted(method.name for method in service.methods)
    assert descriptor_methods == EXPECTED_METHODS, (
        f"InventoryService methods are {descriptor_methods}, expected {EXPECTED_METHODS}"
    )

    assert hasattr(pb2_grpc, "InventoryServiceStub")
    assert hasattr(pb2_grpc, "InventoryServiceServicer")
    assert hasattr(pb2_grpc, "add_InventoryServiceServicer_to_server")

    # The manifest must be derived from all methods in the successfully compiled
    # InventoryService descriptor.
    assert MANIFEST.read_text().splitlines() == descriptor_methods
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
