#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import secrets
import shutil
import subprocess
import tempfile
from pathlib import Path

PROJECT = Path("/home/user/system_builder")
EXECUTABLE = PROJECT / "dep_resolver"


def run(cmd, **kwargs):
    return subprocess.run(cmd, text=True, capture_output=True, timeout=120, **kwargs)


def test_missing_edges_file():
    filepath = PROJECT / "missing_edges.txt"
    assert filepath.is_file(), f"{filepath} is missing"

    with filepath.open("r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_edges = ["core->network", "network->database", "database->render"]
    assert lines == expected_edges, f"Expected edges {expected_edges}, but got {lines}"


def test_dep_resolver_executable():
    assert EXECUTABLE.is_file(), f"Executable {EXECUTABLE} is missing"
    assert os.access(EXECUTABLE, os.X_OK), f"{EXECUTABLE} is not executable"


def test_rust_library_and_makefile_rebuild():
    manifest = PROJECT / "rust_backend" / "Cargo.toml"
    source = PROJECT / "rust_backend" / "src" / "lib.rs"
    makefile = PROJECT / "Makefile"
    assert manifest.is_file(), f"{manifest} is missing"
    assert source.is_file(), f"{source} is missing"
    assert makefile.is_file(), f"{makefile} is missing"

    cargo = run(["cargo", "build", "--manifest-path", str(manifest)], cwd=PROJECT)
    assert cargo.returncode == 0, f"Rust backend does not compile:\n{cargo.stdout}\n{cargo.stderr}"

    rust_so = PROJECT / "rust_backend" / "target" / "debug" / "librust_backend.so"
    assert rust_so.is_file(), f"Cargo did not produce {rust_so}"
    elf = run(["readelf", "-h", str(rust_so)])
    assert elf.returncode == 0 and "DYN" in elf.stdout, "librust_backend.so is not a dynamic ELF library"
    symbols = run(["nm", "-D", str(rust_so)])
    assert symbols.returncode == 0 and re.search(r"\bvalidate_encoding\b", symbols.stdout), \
        "librust_backend.so does not export validate_encoding"

    # Force make all to recreate both the object and executable, rather than trusting
    # an executable left behind independently of the submitted build system.
    for artifact in (PROJECT / "main.o", EXECUTABLE):
        if artifact.exists() or artifact.is_symlink():
            artifact.unlink()
    built = run(["make", "all"], cwd=PROJECT)
    assert built.returncode == 0, f"make all failed:\n{built.stdout}\n{built.stderr}"
    assert EXECUTABLE.is_file() and os.access(EXECUTABLE, os.X_OK), \
        "make all did not produce an executable dep_resolver"

    dry = run(["make", "-Bn", "all"], cwd=PROJECT)
    assert dry.returncode == 0, f"Could not inspect Makefile commands: {dry.stderr}"
    link_lines = [line for line in dry.stdout.splitlines()
                  if "dep_resolver" in line and " -o " in f" {line} "]
    assert link_lines, "Makefile has no link command producing dep_resolver"
    link = link_lines[-1]
    assert "-lrust_backend" in link, "Makefile does not link librust_backend"
    assert "-lgraph_utils" in link, "Makefile does not link libgraph_utils"
    obj_pos = max(link.find("main.o"), link.find("main.c"))
    assert obj_pos >= 0 and obj_pos < link.find("-lrust_backend") and obj_pos < link.find("-lgraph_utils"), \
        f"Link libraries are ordered before the C object/source: {link}"

    dyn = run(["readelf", "-d", str(EXECUTABLE)])
    assert dyn.returncode == 0, f"dep_resolver is not a readable ELF executable: {dyn.stderr}"
    assert "librust_backend" in dyn.stdout, "dep_resolver has no dynamic dependency on librust_backend"
    dyn_symbols = run(["nm", "-D", str(EXECUTABLE)])
    assert dyn_symbols.returncode == 0 and re.search(r"\bvalidate_encoding\b", dyn_symbols.stdout), \
        "dep_resolver is not linked to the Rust validate_encoding FFI symbol"

    # libgraph_utils may be linked dynamically or statically, as allowed by the task.
    graph_linked = "libgraph_utils" in dyn.stdout
    if not graph_linked:
        archives = list(PROJECT.rglob("libgraph_utils.a"))
        binary_nm = run(["nm", "-g", str(EXECUTABLE)])
        binary_symbols = set(re.findall(r"\b([A-Za-z_][A-Za-z0-9_]*)$", binary_nm.stdout, re.M))
        for archive in archives:
            archive_nm = run(["nm", "-g", "--defined-only", str(archive)])
            archive_symbols = set(re.findall(r"\b([A-Za-z_][A-Za-z0-9_]*)$", archive_nm.stdout, re.M))
            if archive_symbols & binary_symbols:
                graph_linked = True
                break
    assert graph_linked, "dep_resolver is not dynamically or statically linked with libgraph_utils"


def test_adversarial_corpus():
    clean_dir = "/app/corpus/clean"
    evil_dir = "/app/corpus/evil"

    assert os.path.isdir(clean_dir), f"{clean_dir} is missing"
    assert os.path.isdir(evil_dir), f"{evil_dir} is missing"

    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir)]
    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir)]

    failed_clean = []
    for f in clean_files:
        res = subprocess.run([str(EXECUTABLE), f], cwd=PROJECT, capture_output=True, timeout=10)
        if res.returncode != 0:
            failed_clean.append(os.path.basename(f))

    failed_evil = []
    for f in evil_files:
        res = subprocess.run([str(EXECUTABLE), f], cwd=PROJECT, capture_output=True, timeout=10)
        if res.returncode == 0:
            failed_evil.append(os.path.basename(f))

    error_msg = []
    if failed_clean:
        error_msg.append(f"{len(failed_clean)} of {len(clean_files)} clean modified/rejected (should be accepted with exit code 0): {failed_clean[:5]}")
    if failed_evil:
        error_msg.append(f"{len(failed_evil)} of {len(evil_files)} evil bypassed (should be rejected with non-zero exit code): {failed_evil[:5]}")

    assert not failed_clean and not failed_evil, " | ".join(error_msg)


def test_generated_inputs_outside_named_corpora():
    # Names are random and carry no clean/evil marker. Expected outcomes are derived
    # here from generated content, preventing dispatch based on corpus directory names.
    root = Path(tempfile.mkdtemp(prefix="resolver_cases_", dir="/tmp"))
    try:
        cases = []
        for _ in range(12):
            labels = random.sample(list("ABCDEFGHIJKLMNOPQRSTUVWXYZ"), 7)
            dag = "".join(f"{labels[i]}->{labels[i+1]}\n" for i in range(6)).encode()
            cases.append((secrets.token_hex(10), dag, True))

            cycle = dag + f"{labels[-1]}->{labels[0]}\n".encode()
            cases.append((secrets.token_hex(10), cycle, False))

            bad_encoding = dag + b"Q->R\n\xff\xfe\n"
            cases.append((secrets.token_hex(10), bad_encoding, False))

        # This is cyclic only after incorporating all three transcribed rules.
        cases.append((secrets.token_hex(10), b"render->core\n", False))
        # A graph using those nodes but not closing the rule chain remains acyclic.
        cases.append((secrets.token_hex(10), b"render->output\ninput->core\n", True))
        random.shuffle(cases)

        failures = []
        for opaque_name, content, should_accept in cases:
            path = root / opaque_name
            path.write_bytes(content)
            result = subprocess.run([str(EXECUTABLE), str(path)], cwd=PROJECT,
                                    capture_output=True, timeout=10)
            accepted = result.returncode == 0
            if accepted != should_accept:
                failures.append((opaque_name, should_accept, result.returncode))
        assert not failures, f"Generated neutral-path validation failures: {failures[:5]}"

        absent = root / secrets.token_hex(10)
        result = subprocess.run([str(EXECUTABLE), str(absent)], cwd=PROJECT,
                                capture_output=True, timeout=10)
        assert result.returncode != 0, "Resolver accepted a nonexistent input file"
    finally:
        shutil.rmtree(root, ignore_errors=True)


def test_validation_results_log():
    log = PROJECT / "validation_results.log"
    assert log.is_file(), f"{log} is missing"
    text = log.read_text(errors="replace").lower()
    clean_count = re.search(r"clean.{0,80}\b100\b|\b100\b.{0,80}clean", text, re.S)
    evil_count = re.search(r"evil.{0,80}\b100\b|\b100\b.{0,80}evil", text, re.S)
    assert clean_count, "validation_results.log does not report 100 clean files successfully handled"
    assert evil_count, "validation_results.log does not report 100 evil files successfully handled"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
