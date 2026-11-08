#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import os
import secrets
import shutil
import subprocess
import tempfile

import pytest
from google.protobuf import descriptor_pb2

CLEAN_CORPUS = "/home/user/manifests/clean/"
EVIL_CORPUS = "/home/user/manifests/evil/"
SCRIPT_PATH = "/home/user/pipeline_guard.py"
PROTO_PATH = "/home/user/manifest.proto"
PB2_PATH = "/home/user/manifest_pb2.py"
LIB_PATH = "/home/user/libcert.so"


def test_pipeline_guard_exists():
    assert os.path.isfile(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}"
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script is not executable: {SCRIPT_PATH}"


def test_manifest_schema_and_generated_binding():
    assert os.path.isfile(PROTO_PATH), f"Schema not found at {PROTO_PATH}"
    assert os.path.isfile(PB2_PATH), f"Generated Python binding not found at {PB2_PATH}"

    with tempfile.TemporaryDirectory() as td:
        descriptor_path = os.path.join(td, "manifest.desc")
        result = subprocess.run(
            ["protoc", "-I/home/user", f"--descriptor_set_out={descriptor_path}", PROTO_PATH],
            capture_output=True,
            text=True,
        )
        assert result.returncode == 0, f"manifest.proto does not compile: {result.stderr}"

        descriptor_set = descriptor_pb2.FileDescriptorSet()
        descriptor_set.ParseFromString(open(descriptor_path, "rb").read())
        assert len(descriptor_set.file) == 1
        file_desc = descriptor_set.file[0]
        assert file_desc.syntax == "proto3"
        messages = [m for m in file_desc.message_type if m.name == "Manifest"]
        assert len(messages) == 1, "manifest.proto must define message Manifest"
        fields = messages[0].field
        actual = [(f.name, f.number, f.type, f.label) for f in fields]
        expected = [
            ("package_name", 1, descriptor_pb2.FieldDescriptorProto.TYPE_STRING, descriptor_pb2.FieldDescriptorProto.LABEL_OPTIONAL),
            ("version", 2, descriptor_pb2.FieldDescriptorProto.TYPE_STRING, descriptor_pb2.FieldDescriptorProto.LABEL_OPTIONAL),
            ("peer_deps", 3, descriptor_pb2.FieldDescriptorProto.TYPE_STRING, descriptor_pb2.FieldDescriptorProto.LABEL_REPEATED),
            ("is_signed", 4, descriptor_pb2.FieldDescriptorProto.TYPE_BOOL, descriptor_pb2.FieldDescriptorProto.LABEL_OPTIONAL),
        ]
        assert actual == expected, f"Unexpected Manifest fields: {actual}"

        check_code = r'''
import importlib.util
import sys
from google.protobuf import descriptor_pb2
spec = importlib.util.spec_from_file_location("submitted_manifest_pb2", sys.argv[1])
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
out = descriptor_pb2.FileDescriptorProto()
module.DESCRIPTOR.CopyToProto(out)
open(sys.argv[2], "wb").write(out.SerializeToString())
'''
        binding_desc_path = os.path.join(td, "binding.desc")
        imported = subprocess.run(
            ["python3", "-c", check_code, PB2_PATH, binding_desc_path],
            capture_output=True,
            text=True,
        )
        assert imported.returncode == 0, f"Generated binding cannot be imported: {imported.stderr}"
        binding_desc = descriptor_pb2.FileDescriptorProto()
        binding_desc.ParseFromString(open(binding_desc_path, "rb").read())
        assert binding_desc == file_desc, "manifest_pb2.py was not generated from manifest.proto"


def test_ctypes_ffi_is_declared():
    source = open(SCRIPT_PATH, "r", encoding="utf-8").read()
    tree = ast.parse(source, filename=SCRIPT_PATH)
    imports_ctypes = any(
        (isinstance(node, ast.Import) and any(alias.name == "ctypes" for alias in node.names))
        or (isinstance(node, ast.ImportFrom) and node.module == "ctypes")
        for node in ast.walk(tree)
    )
    assert imports_ctypes, "pipeline_guard.py must use Python ctypes"
    assert "CDLL" in source or "LoadLibrary" in source, "libcert.so must be loaded through ctypes"
    assert "check_pkg_cert" in source, "check_pkg_cert is not called"
    assert "argtypes" in source and "restype" in source, "ctypes function signature is not declared"
    assert "c_char_p" in source and "c_int" in source, "Incorrect ctypes types for check_pkg_cert"


def test_adversarial_corpus():
    assert os.path.isdir(CLEAN_CORPUS), f"Clean corpus missing: {CLEAN_CORPUS}"
    assert os.path.isdir(EVIL_CORPUS), f"Evil corpus missing: {EVIL_CORPUS}"

    clean_files = [os.path.join(CLEAN_CORPUS, f) for f in os.listdir(CLEAN_CORPUS) if os.path.isfile(os.path.join(CLEAN_CORPUS, f))]
    evil_files = [os.path.join(EVIL_CORPUS, f) for f in os.listdir(EVIL_CORPUS) if os.path.isfile(os.path.join(EVIL_CORPUS, f))]

    assert len(clean_files) > 0, "No files in clean corpus."
    assert len(evil_files) > 0, "No files in evil corpus."

    failed_clean = []
    failed_evil = []

    for f in clean_files:
        result = subprocess.run(["python3", SCRIPT_PATH, f], capture_output=True)
        if result.returncode != 0:
            failed_clean.append(os.path.basename(f))

    for f in evil_files:
        result = subprocess.run(["python3", SCRIPT_PATH, f], capture_output=True)
        if result.returncode != 1:
            failed_evil.append(os.path.basename(f))

    errors = []
    if failed_clean:
        errors.append(f"{len(failed_clean)} of {len(clean_files)} clean modified/rejected: {', '.join(failed_clean)}")
    if failed_evil:
        errors.append(f"{len(failed_evil)} of {len(evil_files)} evil bypassed/accepted: {', '.join(failed_evil)}")

    if errors:
        pytest.fail(" | ".join(errors))


def _varint(value):
    out = bytearray()
    while value > 0x7f:
        out.append((value & 0x7f) | 0x80)
        value >>= 7
    out.append(value)
    return bytes(out)


def _string_field(tag, value):
    raw = value.encode("utf-8")
    return bytes([(tag << 3) | 2]) + _varint(len(raw)) + raw


def _manifest(package_name, version, peer_deps=(), is_signed=False):
    data = _string_field(1, package_name) + _string_field(2, version)
    for peer in peer_deps:
        data += _string_field(3, peer)
    if is_signed:
        data += bytes([4 << 3, 1])
    return data


def test_randomized_manifests_and_real_ffi_call():
    assert os.path.isfile(LIB_PATH), f"Library missing: {LIB_PATH}"
    token = secrets.token_hex(12)
    invalid_pkg = "certprobe_" + token
    invalid_version = "v_" + secrets.token_hex(8)
    normal_pkg = "normal_" + secrets.token_hex(8)

    with tempfile.TemporaryDirectory(prefix="guard_inputs_") as td:
        backup = os.path.join(td, "libcert.original.so")
        log_path = os.path.join(td, "ffi_calls.log")
        c_path = os.path.join(td, "cert_probe.c")
        replacement = os.path.join(td, "libcert.probe.so")
        shutil.copy2(LIB_PATH, backup)

        c_source = f'''#include <stdio.h>
#include <string.h>
int check_pkg_cert(const char* pkg_name, const char* pkg_version) {{
    FILE *f = fopen({json.dumps(log_path)}, "a");
    if (f) {{
        fprintf(f, "%s\\t%s\\n", pkg_name ? pkg_name : "(null)", pkg_version ? pkg_version : "(null)");
        fclose(f);
    }}
    if (pkg_name && strstr(pkg_name, "legacy") != NULL) return 0;
    if (pkg_name && pkg_version && strcmp(pkg_name, {json.dumps(invalid_pkg)}) == 0 && strcmp(pkg_version, {json.dumps(invalid_version)}) == 0) return 0;
    return 1;
}}
'''
        open(c_path, "w", encoding="utf-8").write(c_source)
        built = subprocess.run(["gcc", "-shared", "-fPIC", "-o", replacement, c_path], capture_output=True, text=True)
        assert built.returncode == 0, built.stderr

        try:
            shutil.copy2(replacement, LIB_PATH)
            cases = [
                (invalid_pkg, invalid_version, [], False, 1),
                (invalid_pkg, invalid_version, [], True, 0),
                (invalid_pkg, invalid_version + "_near", [], False, 0),
                (normal_pkg, invalid_version, [], False, 0),
                (normal_pkg, "1.0", ["left-pad-malicious"], True, 1),
                (normal_pkg, "1.0", ["left-pad-malicious-near"], True, 0),
                ("typo_" + secrets.token_hex(8), "2.0", [], True, 1),
                ("not_typo_" + secrets.token_hex(8), "2.0", ["express"], True, 0),
            ]

            for index, (pkg, version, peers, signed, expected) in enumerate(cases):
                manifest_path = os.path.join(td, f"input_{secrets.token_hex(8)}_{index}.dat")
                open(manifest_path, "wb").write(_manifest(pkg, version, peers, signed))
                if os.path.exists(log_path):
                    os.unlink(log_path)
                result = subprocess.run([SCRIPT_PATH, manifest_path], capture_output=True, timeout=10)
                assert result.returncode == expected, (
                    f"Wrong result for randomized manifest {index}: expected {expected}, "
                    f"got {result.returncode}; stdout={result.stdout!r}, stderr={result.stderr!r}"
                )
                assert os.path.isfile(log_path), "Instrumented libcert.so was not called"
                calls = open(log_path, "r", encoding="utf-8").read().splitlines()
                assert f"{pkg}\t{version}" in calls, (
                    "check_pkg_cert was not called with the manifest package_name and version"
                )
        finally:
            shutil.copy2(backup, LIB_PATH)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
