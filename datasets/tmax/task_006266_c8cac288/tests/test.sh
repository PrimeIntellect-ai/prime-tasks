#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess
import tempfile
from pathlib import Path

PROJECT = Path("/home/user/project")
DEPS_FILE = PROJECT / "deps.txt"
ORDER_FILE = PROJECT / "build_order.txt"
RESOLVER_SOURCE = PROJECT / "resolver.cpp"
RUST_DIR = PROJECT / "rust_sanitizer"
RLIB_PATH = RUST_DIR / "target/release/librust_sanitizer.rlib"


def test_build_order_exists_and_valid():
    """Verify that build_order.txt exists and contains a valid topological sort."""
    assert ORDER_FILE.is_file(), f"Expected file {ORDER_FILE} does not exist."

    content = ORDER_FILE.read_text().strip()
    assert content, "build_order.txt is empty."
    order = content.split()

    deps = {
        "waf_core": ["http_parser", "rust_sanitizer"],
        "http_parser": ["utils", "logger"],
        "rust_sanitizer": ["utils"],
        "logger": ["utils"],
        "utils": [],
    }

    expected_nodes = set(deps.keys())
    actual_nodes = set(order)
    assert actual_nodes == expected_nodes, (
        f"Build order must contain exactly {expected_nodes}, but found {actual_nodes}"
    )

    order_indices = {node: idx for idx, node in enumerate(order)}
    for target, dependencies in deps.items():
        for dep in dependencies:
            assert order_indices[dep] < order_indices[target], (
                f"Topological sort failed: dependency '{dep}' must appear before target '{target}'."
            )


def test_resolver_source_compiles_and_handles_unseen_graphs():
    """Compile resolver.cpp and exercise it on verifier-generated DAGs."""
    assert RESOLVER_SOURCE.is_file(), f"Expected source file {RESOLVER_SOURCE} does not exist."

    executable = Path(tempfile.gettempdir()) / f"resolver_verified_{secrets.token_hex(8)}"
    compile_result = subprocess.run(
        ["g++", "-std=c++17", "-Wall", "-Wextra", "-pedantic", str(RESOLVER_SOURCE), "-o", str(executable)],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=60,
    )
    assert compile_result.returncode == 0, f"resolver.cpp failed to compile:\n{compile_result.stdout}"
    assert executable.is_file() and os.access(executable, os.X_OK)

    original_deps = DEPS_FILE.read_bytes()
    original_order = ORDER_FILE.read_bytes() if ORDER_FILE.exists() else None
    rng = secrets.SystemRandom()

    try:
        for case in range(5):
            count = 7 + secrets.randbelow(5)
            tag = secrets.token_hex(6)
            nodes = [f"node_{tag}_{i}" for i in range(count)]
            deps = {node: [] for node in nodes}

            # Edges always point to an earlier node, so the generated graph is a DAG.
            for i in range(1, count):
                deps[nodes[i]].append(nodes[secrets.randbelow(i)])
                for j in range(i):
                    if secrets.randbelow(4) == 0 and nodes[j] not in deps[nodes[i]]:
                        deps[nodes[i]].append(nodes[j])

            lines = [f"{node}: {' '.join(deps[node])}" for node in nodes]
            rng.shuffle(lines)
            DEPS_FILE.write_text("\n".join(lines) + "\n")
            if ORDER_FILE.exists():
                ORDER_FILE.unlink()

            run_result = subprocess.run(
                [str(executable)],
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                timeout=20,
            )
            assert run_result.returncode == 0, (
                f"resolver failed on generated graph {case}:\n{run_result.stdout}"
            )
            assert ORDER_FILE.is_file(), "resolver did not produce build_order.txt"

            order = ORDER_FILE.read_text().split()
            assert len(order) == len(nodes), "resolver output has missing or duplicate nodes"
            assert set(order) == set(nodes), "resolver output does not contain exactly the graph nodes"
            positions = {node: index for index, node in enumerate(order)}
            for target, dependencies in deps.items():
                for dependency in dependencies:
                    assert positions[dependency] < positions[target], (
                        f"Generated graph was not topologically sorted: {dependency} must precede {target}"
                    )
    finally:
        DEPS_FILE.write_bytes(original_deps)
        if original_order is None:
            if ORDER_FILE.exists():
                ORDER_FILE.unlink()
        else:
            ORDER_FILE.write_bytes(original_order)
        if executable.exists():
            executable.unlink()


def test_rust_sanitizer_compiled():
    """Clean-build the Rust library in release mode and execute its public function."""
    assert (RUST_DIR / "Cargo.toml").is_file(), "Rust crate Cargo.toml is missing"
    assert (RUST_DIR / "src/lib.rs").is_file(), "Rust library source is missing"

    clean_result = subprocess.run(
        ["cargo", "clean"],
        cwd=RUST_DIR,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=60,
    )
    assert clean_result.returncode == 0, f"cargo clean failed:\n{clean_result.stdout}"

    env = os.environ.copy()
    env["RUSTFLAGS"] = "-D warnings"
    build_result = subprocess.run(
        ["cargo", "build", "--release"],
        cwd=RUST_DIR,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=180,
    )
    assert build_result.returncode == 0, f"Rust release build failed:\n{build_result.stdout}"
    assert not re.search(r"(^|\n)\s*warning(?:\[|:)", build_result.stdout, re.IGNORECASE), (
        f"Rust release build emitted warnings:\n{build_result.stdout}"
    )

    assert RLIB_PATH.is_file(), (
        f"Expected compiled Rust library at {RLIB_PATH} does not exist. "
        "Ensure the borrow checker issue is fixed and the crate is built with --release."
    )
    assert RLIB_PATH.stat().st_size > 8, "Rust library artifact is empty or truncated"
    with RLIB_PATH.open("rb") as artifact:
        assert artifact.read(8) == b"!<arch>\n", "Rust artifact is not a valid rlib archive"

    with tempfile.TemporaryDirectory() as temp_dir:
        runner_source = Path(temp_dir) / "runner.rs"
        runner_binary = Path(temp_dir) / "runner"
        runner_source.write_text(
            "use rust_sanitizer::sanitize_html;\n"
            "fn main() {\n"
            "    for raw in std::env::args().skip(1) {\n"
            "        let original = raw.clone();\n"
            "        let got = sanitize_html(&original);\n"
            "        assert_eq!(got, format!(\"{} [sanitized]\", raw));\n"
            "        assert_eq!(original, raw);\n"
            "    }\n"
            "}\n"
        )
        compile_runner = subprocess.run(
            [
                "rustc", "--edition=2021", str(runner_source),
                "--extern", f"rust_sanitizer={RLIB_PATH}",
                "-L", f"dependency={RUST_DIR / 'target/release/deps'}",
                "-o", str(runner_binary),
            ],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=60,
        )
        assert compile_runner.returncode == 0, (
            f"Compiled artifact could not be linked as rust_sanitizer:\n{compile_runner.stdout}"
        )

        samples = [
            "",
            f"plain-{secrets.token_hex(8)}",
            f"<script>{secrets.token_hex(8)}</script>",
            f"quoted '& \\\" {secrets.token_hex(6)}",
        ]
        run_runner = subprocess.run(
            [str(runner_binary), *samples],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=30,
        )
        assert run_runner.returncode == 0, (
            f"sanitize_html did not preserve its required behavior:\n{run_runner.stdout}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
