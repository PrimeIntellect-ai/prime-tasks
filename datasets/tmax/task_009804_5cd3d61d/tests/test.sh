#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import tempfile
from pathlib import Path


def fletcher16(data):
    sum1 = 0
    sum2 = 0
    for byte in data:
        sum1 = (sum1 + byte) % 255
        sum2 = (sum2 + sum1) % 255
    return (sum2 << 8) | sum1


def run_verify(executable, path):
    result = subprocess.run(
        [str(executable), str(path)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
        check=False,
    )
    assert result.returncode == 0, (
        f"{executable} failed for {path}: {result.stderr.decode(errors='replace')}"
    )
    expected = f"{Path(path).name}: {fletcher16(Path(path).read_bytes()):04X}\n".encode()
    assert result.stdout == expected, (
        f"{executable} produced {result.stdout!r}; expected {expected!r}"
    )


def test_binaries_exist():
    """Check if the raw binaries were generated properly."""
    app_bin = "/home/user/firmware/app.bin"
    boot_bin = "/home/user/firmware/boot.bin"

    assert os.path.isfile(app_bin), f"{app_bin} is missing. Did you compile and run objcopy?"
    assert os.path.getsize(app_bin) > 0, f"{app_bin} is empty."

    assert os.path.isfile(boot_bin), f"{boot_bin} is missing. Did you compile and run objcopy?"
    assert os.path.getsize(boot_bin) > 0, f"{boot_bin} is empty."


def test_binaries_match_supplied_sources():
    """Rebuild the supplied sources with the required commands and compare raw bytes."""
    app_source = """int main() {
    int a = 5;
    int b = 10;
    return a + b;
}
"""
    boot_source = """.global _start
_start:
    mov $1, %eax
    xor %ebx, %ebx
    int $0x80
"""

    with tempfile.TemporaryDirectory() as td:
        td = Path(td)
        (td / "app.c").write_text(app_source)
        (td / "boot.S").write_text(boot_source)

        subprocess.run(["gcc", "-c", "app.c", "-o", "app.o"], cwd=td, check=True)
        subprocess.run(["gcc", "-c", "boot.S", "-o", "boot.o"], cwd=td, check=True)
        subprocess.run(["objcopy", "-O", "binary", "app.o", "app.bin"], cwd=td, check=True)
        subprocess.run(["objcopy", "-O", "binary", "boot.o", "boot.bin"], cwd=td, check=True)

        assert Path("/home/user/firmware/app.bin").read_bytes() == (td / "app.bin").read_bytes(), \
            "app.bin is not the raw binary produced from the supplied app.c using gcc -c and objcopy -O binary."
        assert Path("/home/user/firmware/boot.bin").read_bytes() == (td / "boot.bin").read_bytes(), \
            "boot.bin is not the raw binary produced from the supplied boot.S using gcc -c and objcopy -O binary."


def test_verify_program_exists():
    """Check if verify.c and the compiled verify executable exist."""
    verify_c = "/home/user/verify.c"
    verify_bin = "/home/user/verify"

    assert os.path.isfile(verify_c), f"{verify_c} is missing."
    assert os.path.isfile(verify_bin), f"{verify_bin} is missing."
    assert os.access(verify_bin, os.X_OK), f"{verify_bin} is not executable."
    assert Path(verify_bin).read_bytes()[:4] == b"\x7fELF", f"{verify_bin} is not a compiled ELF executable."


def test_verify_program_behavior():
    """Execute both the submitted binary and a fresh build of verify.c on derived inputs."""
    with tempfile.TemporaryDirectory() as td:
        td = Path(td)
        rebuilt = td / "verify-rebuilt"
        compile_result = subprocess.run(
            ["gcc", "/home/user/verify.c", "-o", str(rebuilt)],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=20,
            check=False,
        )
        assert compile_result.returncode == 0, (
            "verify.c does not compile: " + compile_result.stderr.decode(errors="replace")
        )

        test_file = td / "random_payload.bin"
        payloads = [b"", bytes(range(256)), os.urandom(1031)]
        for payload in payloads:
            test_file.write_bytes(payload)
            run_verify("/home/user/verify", test_file)
            run_verify(rebuilt, test_file)

        for firmware_file in [
            Path("/home/user/firmware/app.bin"),
            Path("/home/user/firmware/boot.bin"),
        ]:
            run_verify("/home/user/verify", firmware_file)
            run_verify(rebuilt, firmware_file)


def test_manifest_v2_contents():
    """Check if manifest_v2.txt contains the correct checksums."""
    manifest = "/home/user/manifest_v2.txt"
    assert os.path.isfile(manifest), f"{manifest} is missing."

    app_bin = "/home/user/firmware/app.bin"
    boot_bin = "/home/user/firmware/boot.bin"

    with open(app_bin, "rb") as f:
        app_data = f.read()
    with open(boot_bin, "rb") as f:
        boot_data = f.read()

    expected_app_csum = f"{fletcher16(app_data):04X}"
    expected_boot_csum = f"{fletcher16(boot_data):04X}"

    expected_lines = [
        f"app.bin: {expected_app_csum}",
        f"boot.bin: {expected_boot_csum}"
    ]

    with open(manifest, "r") as f:
        actual_lines = [line.strip() for line in f.read().strip().splitlines()]

    assert actual_lines == expected_lines, f"Contents of {manifest} do not match expected checksums."

    expected_bytes = ("\n".join(expected_lines) + "\n").encode()
    assert Path(manifest).read_bytes() == expected_bytes, \
        f"{manifest} is not formatted exactly as the verify utility output."

    app_result = subprocess.run(
        ["/home/user/verify", app_bin], stdout=subprocess.PIPE, timeout=10, check=True
    ).stdout
    boot_result = subprocess.run(
        ["/home/user/verify", boot_bin], stdout=subprocess.PIPE, timeout=10, check=True
    ).stdout
    assert Path(manifest).read_bytes() == app_result + boot_result, \
        "manifest_v2.txt does not equal verify output for app.bin followed by boot.bin."


def test_release_diff_patch():
    """Check if the release diff patch is the actual unified diff of the manifests."""
    patch_file = "/home/user/release_diff.patch"
    assert os.path.isfile(patch_file), f"{patch_file} is missing."

    with open(patch_file, "r") as f:
        patch_content = f.read()

    assert "---" in patch_content and "+++" in patch_content, "Patch file does not look like a unified diff."
    assert "-app.bin: 0000" in patch_content, "Patch file does not contain the expected removal of the old app.bin checksum."
    assert "+app.bin:" in patch_content, "Patch file does not contain the addition of the new app.bin checksum."

    relative_diff = subprocess.run(
        ["diff", "-u", "manifest_v1.txt", "manifest_v2.txt"],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    absolute_diff = subprocess.run(
        ["diff", "-u", "/home/user/manifest_v1.txt", "/home/user/manifest_v2.txt"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    assert relative_diff.returncode == 1 and absolute_diff.returncode == 1, \
        "The manifests unexpectedly do not produce a diff."

    actual_patch = Path(patch_file).read_bytes()
    assert actual_patch in (relative_diff.stdout, absolute_diff.stdout), \
        "release_diff.patch is not the actual output of diff -u on the two manifests."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
