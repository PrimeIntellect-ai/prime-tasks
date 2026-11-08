#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import random
import shutil
import struct
import subprocess
import tempfile
import uuid

APP = "/app"
LIB = "/app/lib/libextractor.so"
SRC = "/app/c_src/extractor.c"
FILTER = "/app/filter.go"


def run(cmd, **kwargs):
    return subprocess.run(cmd, capture_output=True, text=True, **kwargs)


def test_libextractor_so_exists():
    assert os.path.isfile(LIB), f"Shared library missing at {LIB}"


def test_filter_go_exists():
    assert os.path.isfile(FILTER), f"Go CLI missing at {FILTER}"


def test_c_source_exists_and_both_libraries_implement_safe_abi(tmp_path):
    assert os.path.isfile(SRC), f"C source missing at {SRC}"

    rebuilt = str(tmp_path / "libextractor_rebuilt.so")
    build = run([
        "gcc", "-shared", "-fPIC", "-O1",
        "-fsanitize=undefined", "-fno-sanitize-recover=undefined",
        "-o", rebuilt, SRC,
    ])
    assert build.returncode == 0, f"Failed to compile extractor.c:\n{build.stdout}{build.stderr}"

    helper = tmp_path / "call_lib.py"
    helper.write_text(r'''
import ctypes, sys
lib = ctypes.CDLL(sys.argv[1])
fn = lib.process_data
fn.argtypes = [ctypes.POINTER(ctypes.c_ubyte), ctypes.c_int]
fn.restype = ctypes.c_int
data = bytes.fromhex(sys.argv[2])
arr = (ctypes.c_ubyte * max(1, len(data)))()
if data:
    ctypes.memmove(arr, data, len(data))
result = fn(arr, len(data))
print(result)
sys.exit(0 if result == int(sys.argv[3]) else 9)
''')

    rng = random.SystemRandom()
    cases = []
    for length in (0, 1, 2, 3, 5, 17, 64, 127, 128):
        payload = os.urandom(length)
        cases.append((struct.pack("<I", length) + payload, 0))
        cases.append((struct.pack("<I", length) + payload + os.urandom(rng.randrange(1, 20)), 0))
    cases.extend([
        (b"", -1),
        (os.urandom(1), -1),
        (os.urandom(3), -1),
        (struct.pack("<I", 1), -1),
        (struct.pack("<I", 40) + os.urandom(39), -1),
        (struct.pack("<I", 129) + os.urandom(129), -1),
        (struct.pack("<I", 500) + os.urandom(500), -1),
        (b"\xff\xff\xff\xff" + os.urandom(16), -1),
        (b"\x00\x00\x00\x80" + os.urandom(16), -1),
    ])

    for library in (LIB, rebuilt):
        for data, expected in cases:
            res = run(["python3", str(helper), library, data.hex(), str(expected)])
            assert res.returncode == 0, (
                f"{library} failed ABI/safety case len={len(data)}, expected {expected}; "
                f"rc={res.returncode}, stdout={res.stdout!r}, stderr={res.stderr!r}"
            )


def test_go_source_uses_cgo_exec_and_a_goroutine(tmp_path):
    inspector = tmp_path / "inspect.go"
    inspector.write_text(r'''
package main
import (
    "fmt"
    "go/ast"
    "go/parser"
    "go/token"
    "os"
    "strconv"
)
func main() {
    if len(os.Args) != 2 { os.Exit(2) }
    f, err := parser.ParseFile(token.NewFileSet(), os.Args[1], nil, 0)
    if err != nil { fmt.Fprintln(os.Stderr, err); os.Exit(2) }
    hasCImport, hasExecImport := false, false
    hasProcess, hasExecCommand, hasGo := false, false, false
    for _, i := range f.Imports {
        p, _ := strconv.Unquote(i.Path.Value)
        if p == "C" { hasCImport = true }
        if p == "os/exec" { hasExecImport = true }
    }
    ast.Inspect(f, func(n ast.Node) bool {
        switch x := n.(type) {
        case *ast.GoStmt:
            hasGo = true
        case *ast.CallExpr:
            if s, ok := x.Fun.(*ast.SelectorExpr); ok {
                if id, ok := s.X.(*ast.Ident); ok {
                    if id.Name == "C" && s.Sel.Name == "process_data" { hasProcess = true }
                    if id.Name == "exec" && s.Sel.Name == "Command" { hasExecCommand = true }
                }
            }
        }
        return true
    })
    if !(hasCImport && hasExecImport && hasProcess && hasExecCommand && hasGo) {
        fmt.Printf("CImport=%v ExecImport=%v C.process_data=%v exec.Command=%v GoStmt=%v\n",
            hasCImport, hasExecImport, hasProcess, hasExecCommand, hasGo)
        os.Exit(1)
    }
}
''')
    binary = str(tmp_path / "inspect")
    build = run(["go", "build", "-o", binary, str(inspector)])
    assert build.returncode == 0, build.stderr
    inspected = run([binary, FILTER])
    assert inspected.returncode == 0, (
        "filter.go must use cgo C.process_data, os/exec.Command, and a goroutine: "
        + inspected.stdout + inspected.stderr
    )


def test_adversarial_corpus():
    clean_dir = "/app/corpus/clean/"
    evil_dir = "/app/corpus/evil/"

    clean_files = glob.glob(os.path.join(clean_dir, "*"))
    evil_files = glob.glob(os.path.join(evil_dir, "*"))

    assert len(clean_files) > 0, "No clean files found"
    assert len(evil_files) > 0, "No evil files found"

    failed_clean = []
    for cf in clean_files:
        res = subprocess.run(["go", "run", "filter.go", cf], cwd=APP, capture_output=True)
        if res.returncode != 0:
            failed_clean.append(os.path.basename(cf))

    failed_evil = []
    for ef in evil_files:
        res = subprocess.run(["go", "run", "filter.go", ef], cwd=APP, capture_output=True)
        if res.returncode != 1:
            failed_evil.append(os.path.basename(ef))

    error_msgs = []
    if failed_clean:
        error_msgs.append(f"{len(failed_clean)} of {len(clean_files)} clean modified (expected exit 0, got otherwise): {', '.join(failed_clean)}")
    if failed_evil:
        error_msgs.append(f"{len(failed_evil)} of {len(evil_files)} evil bypassed (expected exit 1, got otherwise): {', '.join(failed_evil)}")

    assert not error_msgs, " | ".join(error_msgs)


def test_random_inputs_are_passed_to_library_and_return_value_controls_status(tmp_path):
    backup = str(tmp_path / "original_libextractor.so")
    shutil.copy2(LIB, backup)
    probe_c = tmp_path / "probe.c"
    probe_c.write_text(r'''
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
int process_data(const unsigned char *data, int len) {
    const char *expected_path = getenv("EXTRACTOR_PROBE_EXPECT");
    const char *marker_path = getenv("EXTRACTOR_PROBE_MARKER");
    const char *answer = getenv("EXTRACTOR_PROBE_RETURN");
    if (!expected_path || !marker_path || !answer || len < 0) return -77;
    FILE *f = fopen(expected_path, "rb");
    if (!f) return -77;
    if (fseek(f, 0, SEEK_END) != 0) { fclose(f); return -77; }
    long size = ftell(f);
    if (size < 0 || size != len || fseek(f, 0, SEEK_SET) != 0) { fclose(f); return -77; }
    unsigned char *expected = malloc(size ? (size_t)size : 1);
    if (!expected) { fclose(f); return -77; }
    size_t got = fread(expected, 1, (size_t)size, f);
    fclose(f);
    if (got != (size_t)size || (size && memcmp(expected, data, (size_t)size) != 0)) {
        free(expected); return -77;
    }
    free(expected);
    f = fopen(marker_path, "wb");
    if (!f) return -77;
    fputs("called", f);
    fclose(f);
    return atoi(answer);
}
''')

    try:
        built = run(["gcc", "-shared", "-fPIC", "-o", LIB, str(probe_c)])
        assert built.returncode == 0, built.stderr

        for c_return, expected_status in ((0, 0), (-1, 1)):
            data = os.urandom(random.SystemRandom().randrange(37, 211))
            input_path = tmp_path / ("input_" + uuid.uuid4().hex + ".bin")
            marker = tmp_path / ("marker_" + uuid.uuid4().hex)
            input_path.write_bytes(data)
            env = os.environ.copy()
            env.update({
                "EXTRACTOR_PROBE_EXPECT": str(input_path),
                "EXTRACTOR_PROBE_MARKER": str(marker),
                "EXTRACTOR_PROBE_RETURN": str(c_return),
                "LD_LIBRARY_PATH": "/app/lib" + (":" + env["LD_LIBRARY_PATH"] if env.get("LD_LIBRARY_PATH") else ""),
            })
            res = subprocess.run(
                ["go", "run", "filter.go", str(input_path)], cwd=APP,
                capture_output=True, env=env
            )
            assert marker.is_file(), "filter.go did not pass the randomized file bytes to process_data"
            assert res.returncode == expected_status, (
                f"filter.go did not map C return {c_return} to exit {expected_status}; "
                f"got {res.returncode}, stderr={res.stderr!r}"
            )
    finally:
        shutil.copy2(backup, LIB)


def test_extract_image():
    res = subprocess.run(["go", "run", "filter.go", "--extract-image"], cwd=APP, capture_output=True)
    assert res.returncode == 0, f"Expected Go tool to exit with 0 when extracting image, got {res.returncode}"

    output_path = "/app/recovered_text.txt"
    assert os.path.isfile(output_path), f"Output file missing at {output_path}"

    with open(output_path, "r") as f:
        content = f.read()

    assert "INVOICE-84920-XYZ" in content, "Recovered text does not contain the expected invoice number"


def test_extract_image_really_executes_tesseract_and_captures_raw_output(tmp_path):
    real_tesseract = "/usr/bin/tesseract"
    assert os.path.exists(real_tesseract), "tesseract executable is missing"
    backup = str(tmp_path / "tesseract.real")
    shutil.copy2(real_tesseract, backup)

    token = "OCR-" + uuid.uuid4().hex + "\nsecond-line-" + uuid.uuid4().hex + "\n"
    args_log = tmp_path / "tesseract.args"
    fake = f'''#!/bin/sh
printf '%s\\n' "$@" > "{args_log}"
printf '%s' "{token}"
'''
    try:
        with open(real_tesseract, "w") as f:
            f.write(fake)
        os.chmod(real_tesseract, 0o755)
        try:
            os.remove("/app/recovered_text.txt")
        except FileNotFoundError:
            pass
        res = subprocess.run(["go", "run", "filter.go", "--extract-image"], cwd=APP, capture_output=True)
        assert res.returncode == 0, f"Extraction with instrumented tesseract failed: {res.stderr!r}"
        assert args_log.is_file(), "The extraction branch did not execute tesseract"
        args = args_log.read_text().splitlines()
        assert "/app/sample.png" in args, f"tesseract was not invoked on /app/sample.png: {args!r}"
        assert os.path.isfile("/app/recovered_text.txt"), "Extraction output file was not created"
        assert open("/app/recovered_text.txt", "r").read() == token, (
            "recovered_text.txt must contain the raw output captured from tesseract"
        )
    finally:
        shutil.copy2(backup, real_tesseract)
        os.chmod(real_tesseract, 0o755)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
