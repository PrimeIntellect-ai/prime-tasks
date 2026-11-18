#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import datetime
import glob
import gzip
import json
import os
import re
import secrets
import shutil
import subprocess


def test_go_script_exists():
    assert os.path.isfile("/home/user/vm_monitor.go"), "The Go script /home/user/vm_monitor.go does not exist."


def test_logrotate_conf_exists_and_configured():
    conf_path = "/home/user/logrotate.conf"
    assert os.path.isfile(conf_path), f"The logrotate config {conf_path} does not exist."

    with open(conf_path, "r") as f:
        content = f.read()

    assert "daily" in content, "logrotate.conf must specify 'daily' rotation."
    assert "rotate 3" in content, "logrotate.conf must specify 'rotate 3'."
    assert "compress" in content, "logrotate.conf must specify 'compress'."
    assert "create" in content, "logrotate.conf must specify 'create'."


def test_active_log_file_contents():
    log_path = "/home/user/migration_storage.log"
    assert os.path.isfile(log_path), f"The active log file {log_path} does not exist."

    with open(log_path, "r") as f:
        lines = f.read().strip().splitlines()

    assert len(lines) == 1, f"Expected exactly 1 line in active log, found {len(lines)}."

    pattern = r"^\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\] TOTAL_VIRTUAL_BYTES=59055800320 EXCEEDS_QUOTA=true$"
    assert re.match(pattern, lines[0]), f"Active log line does not match expected format: {lines[0]}"


def test_rotated_log_file_contents():
    rotated_log_path = "/home/user/migration_storage.log.1.gz"
    assert os.path.isfile(rotated_log_path), f"The rotated log file {rotated_log_path} does not exist."

    with gzip.open(rotated_log_path, "rt") as f:
        lines = f.read().strip().splitlines()

    assert len(lines) == 1, f"Expected exactly 1 line in rotated log, found {len(lines)}."

    pattern = r"^\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\] TOTAL_VIRTUAL_BYTES=59055800320 EXCEEDS_QUOTA=true$"
    assert re.match(pattern, lines[0]), f"Rotated log line does not match expected format: {lines[0]}"


def parse_log_line(line):
    match = re.fullmatch(
        r"\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\] TOTAL_VIRTUAL_BYTES=(\d+) EXCEEDS_QUOTA=(true|false)",
        line,
    )
    assert match, f"Log line has an invalid format: {line!r}"
    stamp = datetime.datetime.strptime(match.group(1), "%Y-%m-%d %H:%M:%S")
    return stamp, int(match.group(2)), match.group(3) == "true"


def test_program_execution_and_real_logrotate_behavior():
    source = "/home/user/vm_monitor.go"
    conf_path = "/home/user/logrotate.conf"
    log_path = "/home/user/migration_storage.log"

    # Verify that the directives are real directives in the block managing the
    # required log, rather than keywords placed in comments or another block.
    with open(conf_path, "r") as f:
        conf = re.sub(r"#.*", "", f.read())
    blocks = re.findall(r"([^{}]+)\{([^{}]*)\}", conf, flags=re.S)
    matching = [(header, body) for header, body in blocks if log_path in header.split()]
    assert matching, "No logrotate block manages /home/user/migration_storage.log."
    body = matching[0][1]
    assert re.search(r"(?m)^\s*daily\s*$", body), "The managed log must have a daily directive."
    assert re.search(r"(?m)^\s*rotate\s+3\s*$", body), "The managed log must keep exactly 3 backups."
    assert re.search(r"(?m)^\s*compress\s*$", body), "The managed log must enable compression."
    assert re.search(r"(?m)^\s*create(?:\s+.*)?$", body), "The managed log must use create."

    # Parse the Go source to require an actual os/exec Command call.
    ast_source = r'''
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
    if err != nil { panic(err) }
    aliases := map[string]bool{}
    dot := false
    for _, imp := range f.Imports {
        p, _ := strconv.Unquote(imp.Path.Value)
        if p != "os/exec" { continue }
        if imp.Name == nil { aliases["exec"] = true
        } else if imp.Name.Name == "." { dot = true
        } else if imp.Name.Name != "_" { aliases[imp.Name.Name] = true }
    }
    found := false
    ast.Inspect(f, func(n ast.Node) bool {
        call, ok := n.(*ast.CallExpr)
        if !ok { return true }
        if dot {
            if id, ok := call.Fun.(*ast.Ident); ok && (id.Name == "Command" || id.Name == "CommandContext") { found = true }
        }
        if sel, ok := call.Fun.(*ast.SelectorExpr); ok && (sel.Sel.Name == "Command" || sel.Sel.Name == "CommandContext") {
            if id, ok := sel.X.(*ast.Ident); ok && aliases[id.Name] { found = true }
        }
        return true
    })
    if !found { fmt.Fprintln(os.Stderr, "no os/exec Command call found"); os.Exit(1) }
}
'''
    helper_src = f"/tmp/check_vm_ast_{secrets.token_hex(6)}.go"
    helper_bin = f"/tmp/check_vm_ast_{secrets.token_hex(6)}"
    with open(helper_src, "w") as f:
        f.write(ast_source)
    subprocess.run(["go", "build", "-o", helper_bin, helper_src], check=True, timeout=60)
    subprocess.run([helper_bin, source], check=True, timeout=10)

    program_bin = f"/tmp/vm_monitor_{secrets.token_hex(8)}"
    subprocess.run(["go", "build", "-o", program_bin, source], check=True, timeout=60)
    os.chmod(program_bin, 0o755)

    # Add an unpredictable qcow2 image, then derive the expected total directly
    # from qemu-img rather than trusting a fixed answer.
    image_name = f"audit_{secrets.token_hex(8)}.qcow2"
    image_path = os.path.join("/home/user/legacy_vms", image_name)
    image_size = 100_000_000 + secrets.randbelow(800_000_000)
    subprocess.run(["/usr/bin/qemu-img", "create", "-f", "qcow2", image_path, str(image_size)], check=True)
    os.chown(image_path, 1000, 1000)

    qcow_paths = sorted(glob.glob("/home/user/legacy_vms/*.qcow2"))
    expected_total = 0
    for path in qcow_paths:
        result = subprocess.run(
            ["/usr/bin/qemu-img", "info", "--output=json", path],
            check=True, capture_output=True, text=True,
        )
        expected_total += int(json.loads(result.stdout)["virtual-size"])

    with open(log_path, "r") as f:
        old_lines = f.read().strip().splitlines()

    # Interpose qemu-img while executing the submission. This proves the built
    # program invokes qemu-img info for every qcow2 file, including the random one.
    qemu_path = "/usr/bin/qemu-img"
    real_qemu = f"/tmp/real_qemu_img_{secrets.token_hex(8)}"
    call_log = f"/tmp/qemu_calls_{secrets.token_hex(8)}"
    open(call_log, "w").close()
    os.chmod(call_log, 0o666)
    os.rename(qemu_path, real_qemu)
    try:
        with open(qemu_path, "w") as f:
            f.write(f'#!/bin/sh\nprintf "%s\\n" "$*" >> "{call_log}"\nexec "{real_qemu}" "$@"\n')
        os.chmod(qemu_path, 0o755)
        before = datetime.datetime.now()
        subprocess.run(["runuser", "-u", "user", "--", program_bin], check=True, timeout=60)
        after = datetime.datetime.now()
    finally:
        if os.path.exists(qemu_path):
            os.unlink(qemu_path)
        os.rename(real_qemu, qemu_path)

    with open(call_log, "r") as f:
        calls = [line.strip() for line in f if line.strip()]
    for path in qcow_paths:
        basename = os.path.basename(path)
        relevant = [c for c in calls if basename in c]
        assert relevant, f"The program did not invoke qemu-img for {basename}."
        assert any(re.search(r"(^|\s)info(\s|$)", c) and "--output=json" in c for c in relevant), \
            f"qemu-img was not called as 'info --output=json' for {basename}."

    with open(log_path, "r") as f:
        new_lines = f.read().strip().splitlines()
    assert len(new_lines) == len(old_lines) + 1, "One execution must append exactly one log line."
    stamp, total, exceeds = parse_log_line(new_lines[-1])
    assert before - datetime.timedelta(seconds=2) <= stamp <= after + datetime.timedelta(seconds=2), \
        "The program did not use the current local time."
    assert total == expected_total, f"Expected dynamic total {expected_total}, got {total}."
    assert exceeds == (expected_total > 53687091200), "The quota comparison is incorrect."

    # Exercise the submitted logrotate configuration repeatedly. Four forced
    # rotations must leave exactly three compressed backups and a newly created log.
    for path in glob.glob(log_path + ".*"):
        os.remove(path)
    state_path = f"/tmp/lr_state_{secrets.token_hex(8)}"
    for i in range(4):
        with open(log_path, "w") as f:
            f.write(f"rotation-{i}\n")
        os.chown(log_path, 1000, 1000)
        subprocess.run(
            ["runuser", "-u", "user", "--", "logrotate", "-f", "-s", state_path, conf_path],
            check=True, timeout=30,
        )

    assert os.path.isfile(log_path), "logrotate did not create a new active log file."
    assert os.path.getsize(log_path) == 0, "The newly created active log must be empty."
    for n in (1, 2, 3):
        path = f"{log_path}.{n}.gz"
        assert os.path.isfile(path), f"Missing compressed rotated backup {path}."
        with gzip.open(path, "rt") as f:
            assert f.read().strip() == f"rotation-{4-n}", f"Unexpected contents in {path}."
    assert not glob.glob(log_path + ".4*"), "The configuration retained more than 3 backups."
    assert not any(os.path.isfile(f"{log_path}.{n}") for n in (1, 2, 3)), "Rotated backups were not compressed."

    # Re-run after rotation, as required, and verify the new active log receives
    # exactly one correctly calculated line.
    before = datetime.datetime.now()
    subprocess.run(["runuser", "-u", "user", "--", program_bin], check=True, timeout=60)
    after = datetime.datetime.now()
    with open(log_path, "r") as f:
        final_lines = f.read().strip().splitlines()
    assert len(final_lines) == 1, "The second program run must write one line to the new active log."
    stamp, total, exceeds = parse_log_line(final_lines[0])
    assert before - datetime.timedelta(seconds=2) <= stamp <= after + datetime.timedelta(seconds=2)
    assert total == expected_total
    assert exceeds == (expected_total > 53687091200)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
