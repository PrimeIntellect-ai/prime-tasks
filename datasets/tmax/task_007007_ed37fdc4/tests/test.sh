#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import ctypes
import importlib.util
import os
import secrets
import shutil
import string
import subprocess
import sys
import tempfile

from google.protobuf import descriptor_pb2, descriptor_pool, message_factory

WORKDIR = "/home/user/polyglot_test"


def trusted_record_list_class():
    file_desc = descriptor_pb2.FileDescriptorProto()
    file_desc.name = "verifier_data.proto"
    file_desc.syntax = "proto3"
    message = file_desc.message_type.add()
    message.name = "RecordList"
    field = message.field.add()
    field.name = "payloads"
    field.number = 1
    field.label = descriptor_pb2.FieldDescriptorProto.LABEL_REPEATED
    field.type = descriptor_pb2.FieldDescriptorProto.TYPE_STRING
    pool = descriptor_pool.DescriptorPool()
    pool.Add(file_desc)
    return message_factory.GetMessageClass(pool.FindMessageTypeByName("RecordList"))


RecordList = trusted_record_list_class()


def random_words(count=9):
    rng = secrets.SystemRandom()
    alphabet = string.ascii_letters + string.digits
    words = set()
    while len(words) < count:
        words.add("".join(rng.choice(alphabet) for _ in range(rng.randint(5, 18))))
    return list(words)


def write_input(words):
    msg = RecordList()
    msg.payloads.extend(
        base64.b64encode(word.encode("utf-8")).decode("ascii") for word in words
    )
    with open(os.path.join(WORKDIR, "input.bin"), "wb") as f:
        f.write(msg.SerializeToString())


def check_outputs(words):
    expected = sorted(words, key=lambda value: value.encode("utf-8"))
    txt_path = os.path.join(WORKDIR, "sorted_payloads.txt")
    bin_path = os.path.join(WORKDIR, "output.bin")
    assert os.path.isfile(txt_path), f"Output file {txt_path} was not generated."
    assert os.path.isfile(bin_path), f"Output file {bin_path} was not generated."

    with open(txt_path, "r", encoding="utf-8") as f:
        assert f.read().splitlines() == expected

    with open(bin_path, "rb") as f:
        raw = f.read()
    parsed = RecordList()
    parsed.ParseFromString(raw)
    expected_payloads = [
        base64.b64encode(word.encode("utf-8")).decode("ascii") for word in expected
    ]
    assert list(parsed.payloads) == expected_payloads
    assert raw == parsed.SerializeToString(), "output.bin contains unexpected protobuf data"


def run_pipeline(words):
    write_input(words)
    for name in ("sorted_payloads.txt", "output.bin"):
        path = os.path.join(WORKDIR, name)
        if os.path.exists(path):
            os.remove(path)
    result = subprocess.run(
        [sys.executable, os.path.join(WORKDIR, "test_pipeline.py")],
        cwd=WORKDIR,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"test_pipeline.py failed with exit code {result.returncode}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    check_outputs(words)


def test_complete_pipeline():
    # Preserve all assertions made by the original verifier.
    so_path = os.path.join(WORKDIR, "libsorter.so")
    pb2_path = os.path.join(WORKDIR, "data_pb2.py")
    txt_path = os.path.join(WORKDIR, "sorted_payloads.txt")
    bin_path = os.path.join(WORKDIR, "output.bin")
    pipeline_path = os.path.join(WORKDIR, "test_pipeline.py")

    assert os.path.isfile(so_path), f"Shared library {so_path} was not found."
    assert os.path.isfile(pb2_path), f"Protobuf bindings {pb2_path} were not found."
    assert os.path.isfile(txt_path), f"Output file {txt_path} was not found."
    assert os.path.isfile(bin_path), f"Output file {bin_path} was not found."

    with open(txt_path, "r", encoding="utf-8") as f:
        lines = [line.strip() for line in f if line.strip()]
    assert lines == ["Apple", "Banana", "Cherry", "Mango", "Xylophone", "Zebra"], (
        f"Contents of {txt_path} do not match the expected sorted decoded strings."
    )

    with open(bin_path, "rb") as f:
        content = f.read()
    expected_content = (
        b'\x0a\x08QXBwbGU='
        b'\x0a\x08QmFuYW5h'
        b'\x0a\x08Q2hlcnJ5'
        b'\x0a\x08TWFuZ28='
        b'\x0a\x0cWHlsb3Bob25l'
        b'\x0a\x08WmVicmE='
    )
    assert content == expected_content, (
        f"Contents of {bin_path} do not match the expected serialized protobuf message."
    )
    assert os.path.isfile(pipeline_path), f"Pipeline script {pipeline_path} was not found."

    # Ensure the binding is an importable protobuf module with the requested schema.
    spec = importlib.util.spec_from_file_location("submitted_data_pb2", pb2_path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    descriptor = module.RecordList.DESCRIPTOR
    payload_field = descriptor.fields_by_name.get("payloads")
    assert payload_field is not None
    assert payload_field.number == 1
    assert payload_field.is_repeated
    assert payload_field.type == payload_field.TYPE_STRING

    # Ensure libsorter.so is a real loadable library and exercise its exported C function.
    with open(so_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "libsorter.so is not an ELF shared library"
    library = ctypes.CDLL(so_path)
    function = library.get_sorted_indices
    function.argtypes = [
        ctypes.POINTER(ctypes.c_char_p),
        ctypes.c_int,
        ctypes.POINTER(ctypes.c_int),
    ]
    function.restype = None
    library_words = random_words(11)
    encoded = [word.encode("utf-8") for word in library_words]
    in_array = (ctypes.c_char_p * len(encoded))(*encoded)
    out_array = (ctypes.c_int * len(encoded))()
    function(in_array, len(encoded), out_array)
    expected_indices = sorted(range(len(encoded)), key=lambda i: encoded[i])
    assert list(out_array) == expected_indices, "get_sorted_indices returned incorrect indices"

    # Execute the submitted pipeline on verifier-generated data.
    run_pipeline(random_words())

    # Replace the library temporarily with an equivalent instrumented implementation.
    # This verifies that test_pipeline.py actually calls get_sorted_indices through FFI.
    token = secrets.token_hex(12)
    marker = f"/tmp/polyglot_ffi_{token}"
    with tempfile.TemporaryDirectory() as tempdir:
        backup = os.path.join(tempdir, "submitted_libsorter.so")
        spy_source = os.path.join(tempdir, "spy.c")
        spy_library = os.path.join(tempdir, "spy.so")
        shutil.copy2(so_path, backup)
        with open(spy_source, "w", encoding="utf-8") as f:
            f.write(f'''#include <stdio.h>\n#include <stdlib.h>\n#include <string.h>\nstruct item {{ const char *value; int index; }};\nstatic int cmp(const void *a, const void *b) {{\n    return strcmp(((const struct item*)a)->value, ((const struct item*)b)->value);\n}}\nvoid get_sorted_indices(const char **strings, int count, int *out_indices) {{\n    FILE *marker = fopen("{marker}", "wb");\n    if (marker) {{ fputs("called", marker); fclose(marker); }}\n    struct item *items = malloc((size_t)count * sizeof(struct item));\n    for (int i = 0; i < count; ++i) {{ items[i].value = strings[i]; items[i].index = i; }}\n    qsort(items, (size_t)count, sizeof(struct item), cmp);\n    for (int i = 0; i < count; ++i) out_indices[i] = items[i].index;\n    free(items);\n}}\n''')
        subprocess.run(
            ["gcc", "-shared", "-fPIC", "-O2", "-o", spy_library, spy_source],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        try:
            shutil.copy2(spy_library, so_path)
            if os.path.exists(marker):
                os.remove(marker)
            run_pipeline(random_words(10))
            assert os.path.isfile(marker), (
                "test_pipeline.py did not invoke get_sorted_indices from libsorter.so"
            )
        finally:
            shutil.copy2(backup, so_path)
            if os.path.exists(marker):
                os.remove(marker)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
