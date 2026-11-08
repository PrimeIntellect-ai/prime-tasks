#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess
import tempfile
from pathlib import Path


def adler32(data: bytes) -> int:
    a = 1
    b = 0
    for byte in data:
        a = (a + byte) % 65521
        b = (b + a) % 65521
    return (b << 16) | a


def test_build_pipeline_exists_and_runs():
    """Verify that build_pipeline.sh exists and successfully runs."""
    pipeline_path = "/home/user/build_pipeline.sh"
    assert os.path.isfile(pipeline_path), f"Build pipeline script not found at {pipeline_path}"

    result = subprocess.run(["bash", pipeline_path], capture_output=True, text=True)
    assert result.returncode == 0, f"build_pipeline.sh failed with return code {result.returncode}.\nStdout: {result.stdout}\nStderr: {result.stderr}"


def test_build_pipeline_invokes_release_binary():
    """Verify that orchestration actually invokes the release executable for migration."""
    pipeline_path = "/home/user/build_pipeline.sh"
    result = subprocess.run(["bash", "-x", pipeline_path], capture_output=True, text=True)
    assert result.returncode == 0, f"Traced build_pipeline.sh run failed.\nStdout: {result.stdout}\nStderr: {result.stderr}"

    trace = result.stderr
    invocation = re.compile(
        r"(?m)^\+ .*target/release/\S+\s+migrate\s+"
        r"/home/user/old_registry\.txt\s+"
        r"/home/user/artifacts/?\s+"
        r"/home/user/registry\.csv(?:\s|$)"
    )
    assert invocation.search(trace), (
        "build_pipeline.sh did not invoke the target/release executable with the required migrate arguments.\n"
        f"Trace:\n{trace}"
    )


def test_registry_csv_contents():
    """Verify the contents of the generated registry.csv file."""
    csv_path = "/home/user/registry.csv"
    assert os.path.isfile(csv_path), f"Output CSV not found at {csv_path}"

    expected_data = {
        "web_ui.tar": b"WEB_UI_MOCK_DATA",
        "api_server.bin": b"API_SERVER_MOCK_DATA",
        "legacy_db.so": b"LEGACY_DB_MOCK_DATA"
    }

    expected_lines = ["filename,checksum,security_status"]
    for filename, data in expected_data.items():
        checksum = adler32(data)
        expected_lines.append(f"{filename},{checksum},VERIFIED")

    with open(csv_path, "r") as f:
        actual_lines = [line.strip() for line in f.readlines() if line.strip()]

    assert actual_lines == expected_lines, f"CSV contents do not match expected.\nExpected: {expected_lines}\nActual: {actual_lines}"


def test_setup_outputs_are_exact():
    expected = {
        "/home/user/artifacts/web_ui.tar": b"WEB_UI_MOCK_DATA",
        "/home/user/artifacts/api_server.bin": b"API_SERVER_MOCK_DATA",
        "/home/user/artifacts/legacy_db.so": b"LEGACY_DB_MOCK_DATA",
        "/home/user/old_registry.txt": b"web_ui.tar\napi_server.bin\nlegacy_db.so\n",
    }
    for path, contents in expected.items():
        assert Path(path).is_file(), f"Expected setup output is missing: {path}"
        assert Path(path).read_bytes() == contents, f"Setup output has incorrect bytes: {path}"


def test_rust_project_exists():
    """Verify that the Rust project was created at the correct location."""
    cargo_toml_path = "/home/user/audit-hash/Cargo.toml"
    assert os.path.isfile(cargo_toml_path), f"Rust project Cargo.toml not found at {cargo_toml_path}"

    main_rs_path = "/home/user/audit-hash/src/main.rs"
    assert os.path.isfile(main_rs_path), f"Rust project main.rs not found at {main_rs_path}"


def test_release_binary_handles_unseen_artifacts():
    """Exercise the compiled tool on verifier-generated inputs and derived answers."""
    binary = Path("/home/user/audit-hash/target/release/audit-hash")
    assert binary.is_file(), f"Release binary not found at {binary}"
    assert os.access(binary, os.X_OK), f"Release binary is not executable: {binary}"
    assert binary.read_bytes()[:4] == b"\x7fELF", f"Release artifact is not a compiled ELF executable: {binary}"

    with tempfile.TemporaryDirectory(prefix="audit-hash-verifier-") as tmp:
        root = Path(tmp)
        artifacts = root / "artifacts"
        artifacts.mkdir()
        legacy = root / "legacy.txt"
        output = root / "result.csv"

        nonce = os.urandom(8).hex()
        records = [
            (f"empty_{nonce}.dat", b""),
            (f"small_{nonce}.bin", os.urandom(37)),
            (f"binary_{nonce}.blob", bytes(range(256)) + os.urandom(513)),
            (f"large_{nonce}.payload", os.urandom(70031)),
        ]
        for filename, contents in records:
            (artifacts / filename).write_bytes(contents)
        legacy.write_text("".join(filename + "\n" for filename, _ in records), encoding="utf-8")

        result = subprocess.run(
            [str(binary), "migrate", str(legacy), str(artifacts), str(output)],
            capture_output=True,
            text=True,
            timeout=30,
        )
        assert result.returncode == 0, (
            f"Release binary failed on unseen inputs.\nStdout: {result.stdout}\nStderr: {result.stderr}"
        )
        assert output.is_file(), "Release binary did not create the requested output CSV"

        expected_lines = ["filename,checksum,security_status"] + [
            f"{filename},{adler32(contents)},VERIFIED" for filename, contents in records
        ]
        actual_lines = output.read_text(encoding="utf-8").splitlines()
        assert actual_lines == expected_lines, (
            f"Dynamic migration output is incorrect.\nExpected: {expected_lines}\nActual: {actual_lines}"
        )


def test_artifact_record_is_defined_and_no_adler_crate_is_used():
    sources = "\n".join(
        path.read_text(encoding="utf-8", errors="replace")
        for path in Path("/home/user/audit-hash/src").rglob("*.rs")
    )
    assert re.search(r"\bstruct\s+ArtifactRecord\b", sources), "Rust sources do not define ArtifactRecord"
    assert re.search(r"\bfilename\s*:\s*String\b", sources), "ArtifactRecord filename: String field is missing"
    assert re.search(r"\bchecksum\s*:\s*u32\b", sources), "ArtifactRecord checksum: u32 field is missing"
    assert re.search(r"\bsecurity_status\s*:\s*String\b", sources), "ArtifactRecord security_status: String field is missing"
    assert "65521" in sources, "Rust sources do not contain the Adler-32 modulus"

    lock_path = Path("/home/user/audit-hash/Cargo.lock")
    if lock_path.exists():
        package_names = re.findall(r'(?m)^name\s*=\s*"([^"]+)"', lock_path.read_text(encoding="utf-8"))
        forbidden = [name for name in package_names if name.lower() in {"adler", "adler2", "adler32"}]
        assert not forbidden, f"External Adler checksum crate used instead of a manual implementation: {forbidden}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
