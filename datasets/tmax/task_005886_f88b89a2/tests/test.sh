#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import base64
import ctypes
import json
import os
import secrets
import shutil
import subprocess
import tempfile

LIB_RS = "/home/user/rust_parser/src/lib.rs"
SO_PATH = "/home/user/rust_parser/target/release/librust_parser.so"
PY_PATH = "/home/user/test_migration.py"
INPUT_PATH = "/home/user/legacy_input.txt"
OUTPUT_PATH = "/home/user/migrated_output.json"


def run_script():
    subprocess.run(["python3", PY_PATH], cwd="/home/user", check=True, timeout=20)


def test_complete_ffi_integration():
    # Preserve the original source-level assertion that the known dangling-pointer
    # implementation is gone, without requiring one particular safe implementation.
    assert os.path.isfile(LIB_RS), f"File {LIB_RS} does not exist."
    with open(LIB_RS, "r", encoding="utf-8") as f:
        rust_source = f.read()
    assert "c_result.as_ptr() as *mut c_char" not in rust_source, \
        "The buggy as_ptr() return is still present in lib.rs."

    assert os.path.isfile(SO_PATH), \
        f"The compiled Rust library was not found at {SO_PATH}. Did you run cargo build --release?"
    assert os.path.getsize(SO_PATH) > 0, "The compiled shared library is empty."
    assert os.path.isfile(PY_PATH), f"The Python script was not found at {PY_PATH}."

    with open(PY_PATH, "r", encoding="utf-8") as f:
        python_source = f.read()
    tree = ast.parse(python_source, filename=PY_PATH)
    ffi_declarations = set()
    for node in ast.walk(tree):
        if isinstance(node, (ast.Assign, ast.AnnAssign)):
            targets = node.targets if isinstance(node, ast.Assign) else [node.target]
            for target in targets:
                if (isinstance(target, ast.Attribute)
                        and target.attr in {"argtypes", "restype"}
                        and isinstance(target.value, ast.Attribute)
                        and target.value.attr in {"migrate_schema", "free_string"}):
                    ffi_declarations.add((target.value.attr, target.attr))
    required = {
        ("migrate_schema", "argtypes"),
        ("migrate_schema", "restype"),
        ("free_string", "argtypes"),
        ("free_string", "restype"),
    }
    assert required <= ffi_declarations, \
        "The script must declare argtypes and restype for both FFI functions."

    with tempfile.TemporaryDirectory() as td:
        saved_input = os.path.join(td, "legacy_input.txt")
        saved_library = os.path.join(td, "librust_parser.so")
        shutil.copy2(INPUT_PATH, saved_input)
        shutil.copy2(SO_PATH, saved_library)

        try:
            # Execute the submitted script on the supplied input rather than trusting
            # a pre-created output file.
            if os.path.exists(OUTPUT_PATH):
                os.unlink(OUTPUT_PATH)
            run_script()
            assert os.path.isfile(OUTPUT_PATH), \
                f"The output JSON was not generated at {OUTPUT_PATH}."
            with open(OUTPUT_PATH, "r", encoding="utf-8") as f:
                data = json.load(f)
            expected = {
                "schema_version": "v2",
                "user_id": "bob123",
                "status": "active",
            }
            assert data == expected, \
                f"The JSON content in {OUTPUT_PATH} does not match the expected output."

            # Independently load and exercise the submitted Rust library on fresh,
            # verifier-generated inputs. Running this in a subprocess also turns an
            # invalid pointer/free implementation into a clean test failure.
            cases = []
            for _ in range(12):
                user = "user_" + secrets.token_hex(10)
                status = "status_" + secrets.token_hex(10)
                cases.append({"legacy_user": user, "data_payload": status})

            helper = r'''
import ctypes, json, sys
lib = ctypes.CDLL(sys.argv[1])
lib.migrate_schema.argtypes = [ctypes.c_char_p]
lib.migrate_schema.restype = ctypes.c_void_p
lib.free_string.argtypes = [ctypes.c_void_p]
lib.free_string.restype = None
cases = json.loads(sys.argv[2])
results = []
for case in cases:
    raw = json.dumps(case, separators=(",", ":")).encode("utf-8")
    ptr = lib.migrate_schema(raw)
    if not ptr:
        raise RuntimeError("migrate_schema returned NULL for valid JSON")
    try:
        results.append(json.loads(ctypes.string_at(ptr).decode("utf-8")))
    finally:
        lib.free_string(ptr)
print(json.dumps(results))
'''
            proc = subprocess.run(
                ["python3", "-c", helper, SO_PATH, json.dumps(cases)],
                text=True, capture_output=True, timeout=20
            )
            assert proc.returncode == 0, \
                f"The Rust FFI library failed when called or freed:\n{proc.stderr}"
            results = json.loads(proc.stdout)
            expected_results = [
                {
                    "schema_version": "v2",
                    "user_id": case["legacy_user"],
                    "status": case["data_payload"],
                }
                for case in cases
            ]
            assert results == expected_results, \
                "The Rust library did not migrate verifier-generated inputs correctly."

            # Replace the library temporarily with an instrumented ABI-compatible
            # shim. Its unpredictable return value and markers prove that the Python
            # script passes the decoded bytes to FFI, consumes the returned pointer,
            # and calls free_string on that same pointer.
            nonce = secrets.token_hex(16)
            shim_input_obj = {
                "legacy_user": "shim_user_" + secrets.token_hex(8),
                "data_payload": "shim_status_" + secrets.token_hex(8),
            }
            shim_input = json.dumps(shim_input_obj, separators=(",", ":"))
            shim_result_obj = {
                "verifier_nonce": nonce,
                "source": "instrumented_ffi",
            }
            shim_result = json.dumps(shim_result_obj, separators=(",", ":"))
            marker = os.path.join(td, "ffi_marker")

            def c_string(value):
                return json.dumps(value)

            c_source = f'''
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
static char *last_ptr = NULL;
static void mark(char c) {{
    FILE *f = fopen({c_string(marker)}, "ab");
    if (f) {{ fputc(c, f); fclose(f); }}
}}
__attribute__((visibility("default")))
char *migrate_schema(const char *input) {{
    if (!input || strcmp(input, {c_string(shim_input)}) != 0) {{
        mark('B');
        return NULL;
    }}
    mark('M');
    const char *answer = {c_string(shim_result)};
    last_ptr = (char *)malloc(strlen(answer) + 1);
    if (!last_ptr) return NULL;
    strcpy(last_ptr, answer);
    return last_ptr;
}}
__attribute__((visibility("default")))
void free_string(char *ptr) {{
    if (ptr == last_ptr && ptr != NULL) {{
        mark('F');
        free(ptr);
        last_ptr = NULL;
    }} else {{
        mark('X');
    }}
}}
'''
            c_path = os.path.join(td, "shim.c")
            shim_so = os.path.join(td, "shim.so")
            with open(c_path, "w", encoding="utf-8") as f:
                f.write(c_source)
            compile_proc = subprocess.run(
                ["cc", "-shared", "-fPIC", "-O2", "-o", shim_so, c_path],
                text=True, capture_output=True, timeout=20
            )
            assert compile_proc.returncode == 0, \
                f"Could not build verifier FFI shim:\n{compile_proc.stderr}"

            shutil.copy2(shim_so, SO_PATH)
            encoded = base64.b64encode(shim_input.encode("utf-8")).decode("ascii")
            with open(INPUT_PATH, "w", encoding="ascii") as f:
                f.write(encoded)
            if os.path.exists(OUTPUT_PATH):
                os.unlink(OUTPUT_PATH)
            run_script()

            with open(OUTPUT_PATH, "r", encoding="utf-8") as f:
                shim_output = json.load(f)
            assert shim_output == shim_result_obj, \
                "The Python script did not write the JSON returned by the FFI function."
            with open(marker, "rb") as f:
                calls = f.read()
            assert b"M" in calls, "The Python script did not call migrate_schema with the decoded bytes."
            assert b"F" in calls, "The Python script did not pass the returned pointer to free_string."
            assert b"B" not in calls and b"X" not in calls, \
                "The Python script passed incorrect data or freed a different pointer."
        finally:
            shutil.copy2(saved_input, INPUT_PATH)
            shutil.copy2(saved_library, SO_PATH)

        # Leave the required final artifact generated by the submitted script using
        # the restored real library and original legacy input.
        if os.path.exists(OUTPUT_PATH):
            os.unlink(OUTPUT_PATH)
        run_script()
        with open(OUTPUT_PATH, "r", encoding="utf-8") as f:
            final_data = json.load(f)
        assert final_data == {
            "schema_version": "v2",
            "user_id": "bob123",
            "status": "active",
        }
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
