#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import os
import re
import shutil
import subprocess


def exported_symbols(path):
    result = subprocess.run(
        ["nm", "-D", "--defined-only", path],
        text=True,
        capture_output=True,
        check=True,
    )
    symbols = set()
    for line in result.stdout.splitlines():
        parts = line.split()
        if len(parts) >= 3 and parts[-2].upper() in {"T", "W"}:
            symbols.add(parts[-1].split("@@", 1)[0])
    return symbols


def called_foreign_names(path):
    tree = ast.parse(open(path, "r", encoding="utf-8").read(), filename=path)
    called = set()
    aliases = {}

    for node in ast.walk(tree):
        if isinstance(node, (ast.Assign, ast.AnnAssign)):
            value = node.value
            targets = node.targets if isinstance(node, ast.Assign) else [node.target]
            target_names = [t.id for t in targets if isinstance(t, ast.Name)]
            foreign_name = None
            if isinstance(value, ast.Attribute):
                foreign_name = value.attr
            elif (isinstance(value, ast.Call) and isinstance(value.func, ast.Name)
                  and value.func.id == "getattr" and len(value.args) >= 2
                  and isinstance(value.args[1], ast.Constant)
                  and isinstance(value.args[1].value, str)):
                foreign_name = value.args[1].value
            if foreign_name:
                for name in target_names:
                    aliases[name] = foreign_name

    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        if isinstance(node.func, ast.Attribute):
            called.add(node.func.attr)
        elif isinstance(node.func, ast.Name) and node.func.id in aliases:
            called.add(aliases[node.func.id])
    return called


def test_core_artifacts_and_orchestrator_execution(tmp_path):
    source = "/home/user/libgraph.c"
    library = "/home/user/libgraph.so"
    orchestrator = "/home/user/build_system.py"

    for path in (source, library, orchestrator):
        assert os.path.isfile(path) and not os.path.islink(path), f"Missing regular file: {path}"

    with open(library, "rb") as f:
        assert f.read(4) == b"\x7fELF", "libgraph.so is not an ELF shared library"

    c_text = open(source, "r", encoding="utf-8", errors="replace").read()
    c_code = re.sub(r"/\*.*?\*/|//[^\n]*", "", c_text, flags=re.S)
    assert re.search(r"\b(for|while)\s*\(", c_code), "libgraph.c contains no graph traversal loop"
    assert re.search(r"\bif\s*\(", c_code), "libgraph.c contains no traversal decision logic"

    rebuilt = tmp_path / "libgraph.so"
    compile_result = subprocess.run(
        ["gcc", "-shared", "-fPIC", "-O2", source, "-o", str(rebuilt)],
        text=True,
        capture_output=True,
    )
    assert compile_result.returncode == 0, "libgraph.c does not compile as a shared library:\n" + compile_result.stderr
    assert rebuilt.read_bytes()[:4] == b"\x7fELF"

    exports = exported_symbols(str(rebuilt))
    assert exports, "libgraph.so exports no callable C function"

    py_text = open(orchestrator, "r", encoding="utf-8", errors="replace").read()
    tree = ast.parse(py_text, filename=orchestrator)
    uses_ctypes = any(
        (isinstance(n, ast.Import) and any(a.name == "ctypes" for a in n.names)) or
        (isinstance(n, ast.ImportFrom) and n.module == "ctypes")
        for n in ast.walk(tree)
    )
    assert uses_ctypes, "build_system.py does not import ctypes"
    assert "libgraph.so" in py_text, "build_system.py does not reference libgraph.so"
    assert exports & called_foreign_names(orchestrator), "build_system.py does not call an exported libgraph function"

    audit_dir = tmp_path / "audit"
    audit_dir.mkdir()
    audit_log = tmp_path / "ctypes-audit.log"
    (audit_dir / "sitecustomize.py").write_text(
        "import os, sys\n"
        "p = os.environ.get('CTYPES_AUDIT_LOG')\n"
        "def hook(event, args):\n"
        "    if p and event.startswith('ctypes.'):\n"
        "        with open(p, 'a') as f: f.write(event + ' ' + repr(args) + '\\n')\n"
        "sys.addaudithook(hook)\n",
        encoding="utf-8",
    )

    backup = tmp_path / "original-libgraph.so"
    shutil.copy2(library, backup)
    shutil.copy2(rebuilt, library)
    order_path = "/home/user/build_order.txt"
    if os.path.exists(order_path):
        os.remove(order_path)

    env = os.environ.copy()
    env["PYTHONPATH"] = str(audit_dir) + (os.pathsep + env["PYTHONPATH"] if env.get("PYTHONPATH") else "")
    env["CTYPES_AUDIT_LOG"] = str(audit_log)
    try:
        result = subprocess.run(
            ["python3", orchestrator], cwd="/home/user", env=env,
            text=True, capture_output=True, timeout=30,
        )
    finally:
        shutil.copy2(backup, library)

    assert result.returncode == 0, "build_system.py failed with the library rebuilt from libgraph.c:\n" + result.stderr
    assert os.path.exists(order_path), "Executing build_system.py did not create build_order.txt"
    events = audit_log.read_text(encoding="utf-8") if audit_log.exists() else ""
    assert "ctypes.dlopen" in events and "libgraph.so" in events, "build_system.py did not load libgraph.so through ctypes"
    assert "ctypes.dlsym" in events, "build_system.py did not resolve a C function from libgraph.so"


def test_build_order_correct():
    build_order_path = "/home/user/build_order.txt"
    assert os.path.exists(build_order_path), f"Missing build order file at {build_order_path}"

    with open(build_order_path, "r") as f:
        content = f.read().strip()

    modules = [m.strip() for m in content.split(",") if m.strip()]
    expected_modules = {"gateway", "frontend", "auth", "backend", "database"}
    assert set(modules) == expected_modules, f"Build order contains incorrect modules. Expected {expected_modules}, got {set(modules)}"

    def index_of(module):
        return modules.index(module)

    assert index_of("database") < index_of("auth"), "'database' must be built before 'auth'"
    assert index_of("database") < index_of("backend"), "'database' must be built before 'backend'"
    assert index_of("backend") < index_of("frontend"), "'backend' must be built before 'frontend'"
    assert index_of("frontend") < index_of("gateway"), "'frontend' must be built before 'gateway'"
    assert index_of("auth") < index_of("gateway"), "'auth' must be built before 'gateway'"


def test_sanitizer_corpus():
    sanitizer_path = "/home/user/sanitizer.py"
    assert os.path.exists(sanitizer_path), f"Missing sanitizer script at {sanitizer_path}"

    evil_dir = "/app/corpus/evil/"
    clean_dir = "/app/corpus/clean/"
    evil_bypassed = []
    clean_modified = []

    if os.path.exists(evil_dir) and os.path.isdir(evil_dir):
        for filename in os.listdir(evil_dir):
            filepath = os.path.join(evil_dir, filename)
            if os.path.isfile(filepath):
                result = subprocess.run(["python3", sanitizer_path, filepath], capture_output=True)
                if result.returncode != 1:
                    evil_bypassed.append(filename)

    if os.path.exists(clean_dir) and os.path.isdir(clean_dir):
        for filename in os.listdir(clean_dir):
            filepath = os.path.join(clean_dir, filename)
            if os.path.isfile(filepath):
                result = subprocess.run(["python3", sanitizer_path, filepath], capture_output=True)
                if result.returncode != 0:
                    clean_modified.append(filename)

    error_msgs = []
    if evil_bypassed:
        error_msgs.append(f"{len(evil_bypassed)} evil scripts bypassed: {', '.join(evil_bypassed)}")
    if clean_modified:
        error_msgs.append(f"{len(clean_modified)} clean scripts flagged: {', '.join(clean_modified)}")
    assert not evil_bypassed and not clean_modified, "Sanitizer classification failed:\n" + "\n".join(error_msgs)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
