#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import struct
import subprocess
import tarfile
import tempfile

SOURCE = "/home/user/extractor.c"
BINARY = "/home/user/extractor"
DATASET = "/home/user/dataset_archive"
SUMMARY = "/home/user/summary.csv"
ARCHIVE = "/home/user/final_archive.tar.gz"


def read_elf_exp_data(path):
    with open(path, "rb") as f:
        data = f.read()

    if len(data) < 64 or data[:4] != b"\x7fELF":
        return None
    assert data[4] == 2, f"{path} is not a 64-bit ELF file"
    assert data[5] == 1, f"{path} is not a little-endian ELF file"

    e_shoff = struct.unpack_from("<Q", data, 40)[0]
    e_shentsize = struct.unpack_from("<H", data, 58)[0]
    e_shnum = struct.unpack_from("<H", data, 60)[0]
    e_shstrndx = struct.unpack_from("<H", data, 62)[0]
    assert e_shentsize >= 64 and e_shnum > 0
    assert e_shoff + e_shentsize * e_shnum <= len(data)
    assert e_shstrndx < e_shnum

    def section(index):
        off = e_shoff + index * e_shentsize
        name = struct.unpack_from("<I", data, off)[0]
        file_off = struct.unpack_from("<Q", data, off + 24)[0]
        size = struct.unpack_from("<Q", data, off + 32)[0]
        assert file_off + size <= len(data)
        return name, file_off, size

    _, names_off, names_size = section(e_shstrndx)
    names = data[names_off:names_off + names_size]

    for i in range(e_shnum):
        name_off, file_off, size = section(i)
        assert name_off < len(names)
        end = names.find(b"\0", name_off)
        assert end != -1
        if names[name_off:end] == b".exp_data":
            raw = data[file_off:file_off + size]
            if raw.endswith(b"\0"):
                raw = raw[:-1]
            return raw
    return None


def elf_files(root):
    result = []
    for base, _, files in os.walk(root):
        for name in files:
            path = os.path.join(base, name)
            if not os.path.isfile(path) or not os.access(path, os.X_OK):
                continue
            with open(path, "rb") as f:
                if f.read(4) == b"\x7fELF":
                    result.append(path)
    return sorted(result)


def accepted_output(payload):
    return {payload, payload + b"\n", payload + b"\0", payload + b"\0\n"}


def run_extractor(binary, path, expected):
    proc = subprocess.run([binary, path], stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, timeout=10)
    if expected is None:
        assert proc.stdout == b"", (
            f"{binary} printed data for an ELF with no .exp_data section: {proc.stdout!r}"
        )
    else:
        assert proc.returncode == 0, (
            f"{binary} failed on {path}: {proc.stderr.decode(errors='replace')}"
        )
        assert proc.stdout in accepted_output(expected), (
            f"Incorrect .exp_data output for {path}. Expected {expected!r}, got {proc.stdout!r}"
        )


def expected_csv_from_dataset():
    rows = set()
    pattern = re.compile(rb"^\[TRIAL:([^;\]\r\n]+);OUTCOME:([^;\]\r\n]+);TIME:([^;\]\r\n]+)\]$")
    for path in elf_files(DATASET):
        raw = read_elf_exp_data(path)
        if raw is None:
            continue
        match = pattern.fullmatch(raw)
        assert match, f"Malformed .exp_data in fixture {path}: {raw!r}"
        fields = [part.decode("utf-8") for part in match.groups()]
        rows.add(tuple(fields))
    ordered = sorted(rows, key=lambda row: row[0])
    return "trial,outcome,time\n" + "".join(
        f"{trial},{outcome},{time}\n" for trial, outcome, time in ordered
    )


def read_archived_summary():
    assert os.path.isfile(ARCHIVE), f"Archive {ARCHIVE} does not exist"
    try:
        with tarfile.open(ARCHIVE, "r:gz") as tar:
            members = [m for m in tar.getmembers()
                       if m.isfile() and os.path.basename(m.name) == "summary.csv"]
            assert members, "summary.csv was not found inside final_archive.tar.gz"
            extracted = tar.extractfile(members[0])
            assert extracted is not None
            return extracted.read().decode("utf-8")
    except tarfile.TarError as exc:
        raise AssertionError(f"Failed to read tarball {ARCHIVE}: {exc}")


def test_extractor_source_exists():
    assert os.path.isfile(SOURCE), f"Source file {SOURCE} does not exist"
    with open(SOURCE, "r") as f:
        content = f.read()
    assert "<elf.h>" in content, (
        "The C program must use the ELF format specification and include <elf.h>"
    )


def test_extractor_binary_exists():
    assert os.path.isfile(BINARY), f"Compiled binary {BINARY} does not exist"
    assert os.access(BINARY, os.X_OK), f"File {BINARY} is not executable"


def test_extractor_behavior():
    with tempfile.TemporaryDirectory() as tmp:
        rebuilt = os.path.join(tmp, "extractor_from_source")
        compile_proc = subprocess.run(
            ["gcc", SOURCE, "-o", rebuilt], stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, timeout=20
        )
        assert compile_proc.returncode == 0, (
            "extractor.c does not compile:\n" + compile_proc.stderr.decode(errors="replace")
        )

        token = secrets.token_hex(12)
        trial = str(100000 + secrets.randbelow(900000))
        outcome = "result_" + token
        timestamp = str(100000000 + secrets.randbelow(900000000))
        payload = f"[TRIAL:{trial};OUTCOME:{outcome};TIME:{timestamp}]".encode()

        valid_c = os.path.join(tmp, "random_valid.c")
        valid_elf = os.path.join(tmp, "random_valid")
        with open(valid_c, "w") as f:
            f.write('__attribute__((section(".exp_data"))) '
                    f'const char metadata[] = "{payload.decode()}";\n'
                    'const char decoy[] = "[TRIAL:999;OUTCOME:decoy;TIME:0]";\n'
                    'int main(void) { return decoy[0] == 0; }\n')
        subprocess.run(["gcc", valid_c, "-o", valid_elf], check=True, timeout=20)

        decoy_c = os.path.join(tmp, "decoy_only.c")
        decoy_elf = os.path.join(tmp, "decoy_only")
        decoy = f"[TRIAL:{trial};OUTCOME:grep_decoy_{token};TIME:{timestamp}]"
        with open(decoy_c, "w") as f:
            f.write(f'const char text[] = "{decoy}";\n'
                    'int main(void) { return text[0] == 0; }\n')
        subprocess.run(["gcc", decoy_c, "-o", decoy_elf], check=True, timeout=20)

        for executable in (BINARY, rebuilt):
            run_extractor(executable, valid_elf, payload)
            run_extractor(executable, decoy_elf, None)
            for fixture in elf_files(DATASET):
                run_extractor(executable, fixture, read_elf_exp_data(fixture))


def test_final_archive_exists_and_correct():
    fixed_expected = (
        "trial,outcome,time\n"
        "012,partial,162310\n"
        "042,failure,162345\n"
        "089,success,162399\n"
    )
    derived_expected = expected_csv_from_dataset()
    assert derived_expected == fixed_expected

    archived = read_archived_summary()
    assert archived.strip() == fixed_expected.strip(), (
        f"Contents of archived summary.csv do not match the expected output.\n"
        f"Expected:\n{fixed_expected.strip()}\n\nActual:\n{archived.strip()}"
    )

    assert os.path.isfile(SUMMARY), f"CSV file {SUMMARY} does not exist"
    with open(SUMMARY, "r") as f:
        on_disk = f.read()
    assert on_disk.strip() == derived_expected.strip(), (
        f"{SUMMARY} does not match data independently parsed from the archive fixtures"
    )
PY_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
