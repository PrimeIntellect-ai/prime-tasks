#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PYTEST_EOF' > /tmp/test_final_state.py
import ast
import importlib.util
import os
import random
import subprocess
import sys
import tempfile

PROJECT = "/home/user/project"
ORGANIZER_PATH = os.path.join(PROJECT, "organizer.py")
TEST_PATH = os.path.join(PROJECT, "test_organizer.py")
INDEX_PATH = os.path.join(PROJECT, "index.bin")
OUTPUT_PATH = "/home/user/organized_files.txt"
MEM_PATH = "/home/user/mem_peak.txt"


def load_organizer():
    spec = importlib.util.spec_from_file_location("organizer_under_test", ORGANIZER_PATH)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def encode_independently(s, enc):
    codec = "utf-8" if enc == 1 else "utf-16le"
    payload = s.encode(codec)
    return bytes([enc]) + len(payload).to_bytes(2, "little") + payload


def test_decode_entry_fixed_and_randomized():
    organizer = load_organizer()

    # Preserve the original fixed assertions.
    for text, enc in [("hello_utf8", 1), ("hello_utf16", 2)]:
        entry = encode_independently(text, enc)
        value, offset = organizer.decode_entry(entry, 0)
        assert value == text
        assert offset == len(entry)

    rng = random.Random(int.from_bytes(os.urandom(16), "big"))
    alphabet = list("abcXYZ019 /._-") + ["é", "Ω", "中", "🙂", "𐐷", "\n", "\x00"]
    cases = ["", "é漢🙂", "a\x00b", "line1\nline2"]
    cases.extend(
        "".join(rng.choice(alphabet) for _ in range(rng.randrange(0, 90)))
        for _ in range(180)
    )

    for text in cases:
        for enc in (1, 2):
            prefix = os.urandom(rng.randrange(0, 17))
            entry = encode_independently(text, enc)
            data = prefix + entry + os.urandom(rng.randrange(0, 10))
            value, offset = organizer.decode_entry(data, len(prefix))
            assert value == text
            assert offset == len(prefix) + len(entry)

    entries = [(s, rng.choice((1, 2))) for s in cases[:60]]
    blob = b"".join(encode_independently(s, enc) for s, enc in entries)
    offset = 0
    decoded = []
    for expected, _ in entries:
        value, offset = organizer.decode_entry(blob, offset)
        decoded.append(value)
        assert value == expected
    assert offset == len(blob)


def test_property_test_exists_is_real_and_passes():
    assert os.path.isfile(TEST_PATH), f"{TEST_PATH} does not exist"
    content = open(TEST_PATH, encoding="utf-8").read()

    # Preserve the original source assertions.
    assert "test_decode_encode" in content
    assert "hypothesis" in content
    assert "strategies.text" in content or "st.text" in content
    assert "sampled_from" in content

    tree = ast.parse(content, TEST_PATH)
    funcs = [n for n in tree.body if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef)) and n.name == "test_decode_encode"]
    assert funcs, "test_decode_encode function not found"
    fn = funcs[0]
    fn_source = ast.get_source_segment(content, fn) or ""
    decorator_source = "\n".join(ast.get_source_segment(content, d) or "" for d in fn.decorator_list)
    compact_decorators = "".join(decorator_source.split())
    compact_fn = "".join(fn_source.split())
    assert "given" in decorator_source, "test_decode_encode must be decorated with Hypothesis given"
    assert ".text(" in compact_decorators, "the Hypothesis decorator must generate text() values"
    assert ".sampled_from([1,2])" in compact_decorators, "the Hypothesis decorator must sample encodings from [1, 2]"
    assert "encode_entry(" in compact_fn, "the property test must call encode_entry"
    assert "decode_entry(" in compact_fn, "the property test must call decode_entry"
    assert any(isinstance(n, ast.Assert) for n in ast.walk(fn)), "the property test must assert the round trip"

    result = subprocess.run(
        [sys.executable, "-m", "pytest", TEST_PATH, "-x", "--tb=short", "--hypothesis-show-statistics"],
        cwd=PROJECT, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=90
    )
    assert result.returncode == 0, result.stdout


def test_read_index_refactored_and_behavioral():
    source = open(ORGANIZER_PATH, encoding="utf-8").read()
    tree = ast.parse(source, ORGANIZER_PATH)
    funcs = [n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name == "read_index"]
    assert funcs, "read_index is missing"
    read_fn = funcs[0]

    # A no-argument read/read_bytes recreates the original whole-index memory spike.
    for node in ast.walk(read_fn):
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute):
            if node.func.attr == "read" and not node.args and not node.keywords:
                raise AssertionError("read_index still reads the entire index into memory at once")
            if node.func.attr == "read_bytes":
                raise AssertionError("read_index still reads the entire index into memory at once")

    rng = random.Random(int.from_bytes(os.urandom(16), "big"))
    alphabet = "abcXYZ0123456789/_-." + "éΩ中🙂"
    expected = [
        "p/" + "".join(rng.choice(alphabet) for _ in range(rng.randrange(0, 80)))
        for _ in range(250)
    ]
    blob = b"".join(encode_independently(s, rng.choice((1, 2))) for s in expected)
    with tempfile.NamedTemporaryFile(delete=False) as f:
        f.write(blob)
        path = f.name
    try:
        organizer = load_organizer()
        result = organizer.read_index(path)
        assert list(result) == expected
    finally:
        os.unlink(path)


def test_main_executes_output_and_real_tracemalloc():
    source = open(ORGANIZER_PATH, encoding="utf-8").read()
    tree = ast.parse(source, ORGANIZER_PATH)
    assert any(isinstance(n, ast.Import) and any(a.name == "tracemalloc" for a in n.names) for n in tree.body), "organizer.py must import tracemalloc"
    main = next((n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name == "main"), None)
    assert main is not None
    body = list(main.body)
    if body and isinstance(body[0], ast.Expr) and isinstance(body[0].value, ast.Constant) and isinstance(body[0].value.value, str):
        body = body[1:]
    assert body, "main is empty"
    first = body[0]
    assert isinstance(first, ast.Expr) and isinstance(first.value, ast.Call), "tracemalloc.start() must be the first operation in main"
    call = first.value
    assert isinstance(call.func, ast.Attribute) and isinstance(call.func.value, ast.Name)
    assert call.func.value.id == "tracemalloc" and call.func.attr == "start", "tracemalloc.start() must be the first operation in main"
    assert any(
        isinstance(n, ast.Call) and isinstance(n.func, ast.Attribute)
        and isinstance(n.func.value, ast.Name) and n.func.value.id == "tracemalloc"
        and n.func.attr == "get_traced_memory"
        for n in ast.walk(main)
    ), "main must obtain the measured peak using tracemalloc.get_traced_memory()"

    # Execute on the supplied index and preserve the original output assertions.
    for path in (OUTPUT_PATH, MEM_PATH):
        if os.path.exists(path):
            os.unlink(path)
    result = subprocess.run([sys.executable, ORGANIZER_PATH, INDEX_PATH], text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=30)
    assert result.returncode == 0, result.stdout
    assert os.path.isfile(OUTPUT_PATH)
    expected_original = [
        "CMakeLists.txt", "build/config.h", "include/utils.hpp",
        "lib/libUTF16_test.so", "lib/libmath.so", "src/main.cpp"
    ]
    with open(OUTPUT_PATH, encoding="utf-8") as f:
        lines = [line.strip() for line in f if line.strip()]
    assert lines == expected_original
    assert os.path.isfile(MEM_PATH)
    measured = open(MEM_PATH, encoding="utf-8").read().strip()
    assert measured.isdigit()
    assert int(measured) > 0

    # Use unpredictable input so the required output cannot be a fixed file.
    rng = random.Random(int.from_bytes(os.urandom(16), "big"))
    alphabet = "abcXYZ0123456789/_-." + "éΩ中🙂"
    paths = [
        "dynamic/" + "".join(rng.choice(alphabet) for _ in range(rng.randrange(3, 45)))
        for _ in range(70)
    ]
    blob = b"".join(encode_independently(p, rng.choice((1, 2))) for p in paths)
    with tempfile.NamedTemporaryFile(delete=False) as f:
        f.write(blob)
        custom_index = f.name
    try:
        result = subprocess.run([sys.executable, ORGANIZER_PATH, custom_index], text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=30)
        assert result.returncode == 0, result.stdout
        with open(OUTPUT_PATH, encoding="utf-8") as f:
            assert f.read().splitlines() == sorted(paths)
    finally:
        os.unlink(custom_index)

    # Instrument tracemalloc to prove that main writes the returned peak, not a hardcoded integer.
    organizer = load_organizer()
    events = []
    class FakeTraceMalloc:
        def start(self):
            events.append("start")
        def get_traced_memory(self):
            events.append("get")
            return (12345, 987654321)
    organizer.tracemalloc = FakeTraceMalloc()
    old_argv = sys.argv
    try:
        sys.argv = [ORGANIZER_PATH, INDEX_PATH]
        organizer.main()
    finally:
        sys.argv = old_argv
    assert events == ["start", "get"]
    assert open(MEM_PATH, encoding="utf-8").read().strip() == "987654321"

    # Leave a genuine measurement and the requested supplied-index output behind.
    result = subprocess.run([sys.executable, ORGANIZER_PATH, INDEX_PATH], text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=30)
    assert result.returncode == 0, result.stdout
    genuine = open(MEM_PATH, encoding="utf-8").read().strip()
    assert genuine.isdigit() and int(genuine) > 0
PYTEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
