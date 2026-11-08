#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import os
import re
import secrets
import shutil
import subprocess
import tempfile


def test_fix_rust_py_exists_and_is_python_with_custom_structure():
    path = "/home/user/fix_rust.py"
    assert os.path.isfile(path), f"Expected Python script {path} does not exist."

    with open(path, "r", encoding="utf-8") as f:
        source = f.read()
    try:
        tree = ast.parse(source, filename=path)
    except SyntaxError as exc:
        raise AssertionError(f"{path} is not valid Python: {exc}")

    class_names = {node.name for node in ast.walk(tree) if isinstance(node, ast.ClassDef)}
    assert class_names, "fix_rust.py does not define the required custom diff data structure."

    instantiated = False
    for node in ast.walk(tree):
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Name) and node.func.id in class_names:
            instantiated = True
            break
    assert instantiated, "The custom diff data structure is defined but never instantiated."


def test_status_txt_secured():
    path = "/home/user/status.txt"
    assert os.path.isfile(path), f"Expected status file {path} does not exist."
    with open(path, "r", encoding="utf-8") as f:
        content = f.read().strip()
    assert content == "SECURED", f"Expected {path} to contain 'SECURED', but found '{content}'."


def test_cargo_check_success():
    rust_dir = "/home/user/rust_server"
    assert os.path.isdir(rust_dir), f"Rust project directory {rust_dir} does not exist."

    result = subprocess.run(
        ["cargo", "check"],
        cwd=rust_dir,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=120,
    )
    assert result.returncode == 0, f"`cargo check` failed with errors:\n{result.stderr.decode()}"


def test_rust_main_rs_modified():
    path = "/home/user/rust_server/src/main.rs"
    assert os.path.isfile(path), f"Rust file {path} does not exist."
    with open(path, "r", encoding="utf-8") as f:
        content = f.read()

    # Preserve the original assertions.
    assert "Mutex" in content, "The file main.rs does not contain 'Mutex', indicating the fix was not applied."
    assert "lock().unwrap()" in content or "lock().expect(" in content, "The file main.rs does not seem to acquire the mutex lock."


def strip_rust_comments_and_strings(source):
    out = []
    i = 0
    block_depth = 0
    while i < len(source):
        if block_depth:
            if source.startswith("/*", i):
                block_depth += 1
                i += 2
            elif source.startswith("*/", i):
                block_depth -= 1
                i += 2
            else:
                out.append("\n" if source[i] == "\n" else " ")
                i += 1
            continue
        if source.startswith("//", i):
            end = source.find("\n", i)
            if end == -1:
                break
            out.append("\n")
            i = end + 1
            continue
        if source.startswith("/*", i):
            block_depth = 1
            i += 2
            continue
        if source[i] == '"':
            out.append('""')
            i += 1
            while i < len(source):
                if source[i] == "\\":
                    i += 2
                elif source[i] == '"':
                    i += 1
                    break
                else:
                    i += 1
            continue
        out.append(source[i])
        i += 1
    return "".join(out)


def test_script_parses_and_applies_a_fresh_diff_then_runs_cargo_check():
    rust_dir = "/home/user/rust_server"
    main_path = os.path.join(rust_dir, "src", "main.rs")
    patch_path = "/home/user/go_fix.patch"
    status_path = "/home/user/status.txt"
    script_path = "/home/user/fix_rust.py"

    # A fresh identifier prevents a solution hard-coded to the shipped word "sessions".
    field = "session_map_" + secrets.token_hex(4)

    pristine_main = f'''use std::sync::Arc;
use std::collections::HashMap;
use std::thread;

struct AppState {{
    {field}: HashMap<String, String>,
}}

fn main() {{
    let state = Arc::new(AppState {{
        {field}: HashMap::new(),
    }});

    let mut handles = vec![];

    for i in 0..5 {{
        let state_clone = Arc::clone(&state);
        handles.push(thread::spawn(move || {{
            let session_id = format!("session_{{}}", i);
            let token = format!("token_{{}}", i);
            state_clone.{field}.insert(session_id, token);
        }}));
    }}

    for h in handles {{
        h.join().unwrap();
    }}
}}
'''

    fresh_patch = f'''--- server.go
+++ server.go
@@ -10,7 +10,8 @@
 }}

 type AppState struct {{
-\t{field} map[string]string
+\tmu       sync.Mutex
+\t{field} map[string]string
 }}

 func (s *AppState) SetSession(id, token string) {{
-\ts.{field}[id] = token
+\ts.mu.Lock()
+\tdefer s.mu.Unlock()
+\ts.{field}[id] = token
 }}
'''

    with open(main_path, "w", encoding="utf-8") as f:
        f.write(pristine_main)
    with open(patch_path, "w", encoding="utf-8") as f:
        f.write(fresh_patch)
    try:
        os.remove(status_path)
    except FileNotFoundError:
        pass

    real_cargo = shutil.which("cargo")
    assert real_cargo, "cargo is not available"
    wrapper_dir = tempfile.mkdtemp(prefix="cargo-wrapper-")
    marker = os.path.join(wrapper_dir, "calls.txt")
    wrapper = os.path.join(wrapper_dir, "cargo")
    with open(wrapper, "w", encoding="utf-8") as f:
        f.write("#!/bin/sh\n")
        f.write(f"printf '%s\\n' \"$*\" >> {marker!r}\n")
        f.write(f"exec {real_cargo!r} \"$@\"\n")
    os.chmod(wrapper, 0o755)

    env = os.environ.copy()
    env["PATH"] = wrapper_dir + os.pathsep + env.get("PATH", "")
    result = subprocess.run(
        ["python3", script_path],
        cwd="/home/user",
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=120,
    )
    assert result.returncode == 0, (
        "Executing fix_rust.py failed:\nSTDOUT:\n"
        + result.stdout.decode(errors="replace")
        + "\nSTDERR:\n"
        + result.stderr.decode(errors="replace")
    )

    assert os.path.isfile(marker), "fix_rust.py did not invoke cargo."
    with open(marker, "r", encoding="utf-8") as f:
        cargo_calls = [line.strip() for line in f if line.strip()]
    assert any(call == "check" or call.startswith("check ") for call in cargo_calls), (
        f"fix_rust.py did not run `cargo check`; observed cargo calls: {cargo_calls}"
    )

    assert os.path.isfile(status_path), "fix_rust.py did not create /home/user/status.txt."
    with open(status_path, "r", encoding="utf-8") as f:
        assert f.read().strip() == "SECURED", "fix_rust.py did not write the exact SECURED status."

    with open(main_path, "r", encoding="utf-8") as f:
        code = strip_rust_comments_and_strings(f.read())

    qmutex = r"(?:std\s*::\s*sync\s*::\s*)?Mutex"
    field_re = re.escape(field)
    assert re.search(
        rf"{field_re}\s*:\s*{qmutex}\s*<\s*HashMap\s*<\s*String\s*,\s*String\s*>\s*>",
        code,
    ), "The field selected by the Go diff was not wrapped in a Mutex."
    assert re.search(
        rf"{field_re}\s*:\s*{qmutex}\s*::\s*new\s*\(\s*HashMap\s*::\s*new\s*\(\s*\)\s*\)",
        code,
    ), "The selected field was not initialized with Mutex::new(HashMap::new())."

    direct_insert = re.search(
        rf"state_clone\s*\.\s*{field_re}\s*\.\s*lock\s*\(\s*\)\s*\.\s*unwrap\s*\(\s*\)\s*\.\s*insert\s*\(",
        code,
    )
    guard_match = re.search(
        rf"let\s+mut\s+(\w+)\s*=\s*state_clone\s*\.\s*{field_re}\s*\.\s*lock\s*\(\s*\)\s*\.\s*unwrap\s*\(\s*\)\s*;",
        code,
    )
    guarded_insert = False
    if guard_match:
        guarded_insert = re.search(
            rf"\b{re.escape(guard_match.group(1))}\s*\.\s*insert\s*\(",
            code[guard_match.end():],
        ) is not None
    assert direct_insert or guarded_insert, "Session insertion is not performed through the acquired mutex guard."

    check = subprocess.run(
        [real_cargo, "check"],
        cwd=rust_dir,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=120,
    )
    assert check.returncode == 0, f"Patched fresh project does not compile:\n{check.stderr.decode(errors='replace')}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
