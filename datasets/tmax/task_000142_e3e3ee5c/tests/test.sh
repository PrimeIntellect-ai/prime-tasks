#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import io
import json
import os
import shutil
import stat
import subprocess
import tarfile
import tempfile
import uuid
import zipfile
from pathlib import Path

import pytest


def zip_bytes(entries):
    """Build a zip from {path: bytes|str}, with ordinary non-executable files."""
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", compression=zipfile.ZIP_DEFLATED) as zf:
        for name, data in entries.items():
            if isinstance(data, str):
                data = data.encode()
            info = zipfile.ZipInfo(name)
            info.create_system = 3
            info.external_attr = 0o100644 << 16
            zf.writestr(info, data)
    return buf.getvalue()


def make_tar(path, entries):
    """Build a tar.gz. Entry values are (kind, payload, mode)."""
    with tarfile.open(path, "w:gz") as tf:
        for name, (kind, payload, mode) in entries.items():
            info = tarfile.TarInfo(name)
            info.mode = mode
            if kind == "file":
                if isinstance(payload, str):
                    payload = payload.encode()
                info.size = len(payload)
                tf.addfile(info, io.BytesIO(payload))
            elif kind == "symlink":
                info.type = tarfile.SYMTYPE
                info.linkname = payload
                tf.addfile(info)
            else:
                raise ValueError(kind)


def run_filter(script_path, input_dir, output_dir):
    return subprocess.run(
        ["bash", script_path, str(input_dir), str(output_dir)],
        capture_output=True,
        text=True,
        timeout=30,
    )


def matching_files(root, filename):
    return [p for p in Path(root).rglob(filename) if p.is_file()]


def test_doc_unpack_fixed_and_installed():
    """Phase 1 must provide an executable that really handles nested archives."""
    bin_path = "/usr/local/bin/doc-unpack"
    assert os.path.isfile(bin_path), f"The doc-unpack binary is missing at {bin_path}. Did you run 'make install'?"
    assert os.access(bin_path, os.X_OK), f"The doc-unpack binary at {bin_path} is not executable."

    token = uuid.uuid4().hex
    marker_a = f"phase1-a-{token}.txt"
    marker_b = f"phase1-b-{token}.txt"
    inner = zip_bytes({f"deep/{marker_a}": f"nested-{token}"})
    outer = zip_bytes({
        f"inner-{token}.zip": inner,
        f"docs/{marker_b}": f"second-{token}",
    })

    with tempfile.TemporaryDirectory() as td:
        archive = Path(td) / f"probe-{token}.tar.gz"
        output = Path(td) / "out"
        make_tar(archive, {f"payload-{token}.zip": ("file", outer, 0o644)})
        result = subprocess.run(
            [bin_path, str(archive), str(output)],
            capture_output=True,
            text=True,
            timeout=30,
        )
        assert result.returncode == 0, (
            f"doc-unpack failed on a valid nested archive.\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
        )
        found_a = matching_files(output, marker_a)
        found_b = matching_files(output, marker_b)
        assert found_a and found_a[0].read_text() == f"nested-{token}", "doc-unpack did not recursively extract the nested zip"
        assert found_b and found_b[0].read_text() == f"second-{token}", "doc-unpack did not extract all members"


def test_adversarial_corpus_filtering():
    """Retain the original checks against the shipped validation corpora."""
    script_path = "/home/user/filter_docs.sh"
    assert os.path.isfile(script_path), f"Script {script_path} is missing."

    clean_dir = "/app/corpora/clean"
    evil_dir = "/app/corpora/evil"
    assert os.path.isdir(clean_dir), f"Clean corpus directory {clean_dir} missing."
    assert os.path.isdir(evil_dir), f"Evil corpus directory {evil_dir} missing."

    with tempfile.TemporaryDirectory() as mixed_dir, tempfile.TemporaryDirectory() as output_dir:
        clean_files = [f for f in os.listdir(clean_dir) if f.endswith(".tar.gz")]
        evil_files = [f for f in os.listdir(evil_dir) if f.endswith(".tar.gz")]
        for f in clean_files:
            shutil.copy(os.path.join(clean_dir, f), os.path.join(mixed_dir, f))
        for f in evil_files:
            shutil.copy(os.path.join(evil_dir, f), os.path.join(mixed_dir, f))

        result = run_filter(script_path, mixed_dir, output_dir)
        output_subdirs = [d for d in os.listdir(output_dir) if os.path.isdir(os.path.join(output_dir, d))]

        bypassed_evil = []
        for f in evil_files:
            base_name = f.replace(".tar.gz", "")
            if any(d == base_name or d == f for d in output_subdirs):
                bypassed_evil.append(f)

        modified_clean = []
        for f in clean_files:
            base_name = f.replace(".tar.gz", "")
            if not any(d == base_name or d == f for d in output_subdirs):
                modified_clean.append(f)

        errors = []
        if bypassed_evil:
            errors.append(f"{len(bypassed_evil)} of {len(evil_files)} evil bypassed: {', '.join(bypassed_evil)}")
        if modified_clean:
            errors.append(f"{len(modified_clean)} of {len(clean_files)} clean modified: {', '.join(modified_clean)}")
        if errors:
            pytest.fail(" | ".join(errors) + f"\n\nScript STDOUT:\n{result.stdout}\n\nScript STDERR:\n{result.stderr}")


def test_generated_unlabeled_corpus_and_preserved_contents():
    """Use unpredictable names and verify extraction contents, not merely directory names."""
    script_path = "/home/user/filter_docs.sh"
    assert os.path.isfile(script_path), f"Script {script_path} is missing."

    token = uuid.uuid4().hex
    names = [f"bundle-{uuid.uuid4().hex}" for _ in range(6)]
    clean_names = names[:2]
    evil_names = names[2:]
    markers = {
        clean_names[0]: (f"marker-{uuid.uuid4().hex}.txt", f"payload-{uuid.uuid4().hex}"),
        clean_names[1]: (f"marker-{uuid.uuid4().hex}.txt", f"payload-{uuid.uuid4().hex}"),
    }

    with tempfile.TemporaryDirectory() as input_dir, tempfile.TemporaryDirectory() as output_dir:
        input_path = Path(input_dir)

        # Two clean, differently structured, recursively nested bundles.
        for index, base in enumerate(clean_names):
            marker_name, marker_value = markers[base]
            deepest = zip_bytes({
                f"documents/level-{index}/{marker_name}": marker_value,
                f"documents/level-{index}/guide.txt": "ordinary documentation\n",
            })
            outer = zip_bytes({
                "metadata.json": json.dumps({"valid": True, "token": token, "index": index}),
                "changelog.log": "Record: 1\nAuthor: Writer123\nSummary: Normal text\n",
                "docs/readme.md": "# Documentation\n",
                f"nested-{uuid.uuid4().hex}.zip": deepest,
            })
            make_tar(input_path / f"{base}.tar.gz", {
                f"submission-{uuid.uuid4().hex}.zip": ("file", outer, 0o644)
            })

        # Absolute external symlink.
        support = zip_bytes({"metadata.json": "{\"valid\": true}", "changelog.log": "Author: Safe User\n"})
        make_tar(input_path / f"{evil_names[0]}.tar.gz", {
            "support.zip": ("file", support, 0o644),
            "docs/external-reference": ("symlink", "/etc/passwd", 0o777),
        })

        # Executable markdown file.
        make_tar(input_path / f"{evil_names[1]}.tar.gz", {
            "metadata.json": ("file", "{\"valid\": true}", 0o644),
            "changelog.log": ("file", "Author: Safe User\n", 0o644),
            "docs/manual.md": ("file", "# Must not execute\n", 0o755),
        })

        # Invalid JSON hidden inside a zip.
        bad_json_zip = zip_bytes({
            "deep/config/metadata.json": "{\"trailing\": true,}",
            "deep/changelog.log": "Author: Safe User\n",
            "deep/readme.md": "# Fine permissions\n",
        })
        make_tar(input_path / f"{evil_names[2]}.tar.gz", {"packed.zip": ("file", bad_json_zip, 0o644)})

        # Subshell syntax in a multiline Author record, also hidden in a zip.
        bad_log_zip = zip_bytes({
            "metadata.json": "{\"valid\": true}",
            "logs/changelog.log": "Record: release\nNotes: ordinary text\nAuthor: `id`\nEnd: yes\n",
            "docs/readme.txt": "safe text\n",
        })
        make_tar(input_path / f"{evil_names[3]}.tar.gz", {"records.zip": ("file", bad_log_zip, 0o644)})

        result = run_filter(script_path, input_dir, output_dir)
        out = Path(output_dir)

        for base in clean_names:
            accepted = out / base
            assert accepted.is_dir(), (
                f"Clean generated bundle {base} was not preserved.\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
            )
            marker_name, marker_value = markers[base]
            found = matching_files(accepted, marker_name)
            assert found, f"{base} was represented by a directory but its nested extracted payload is missing"
            assert found[0].read_text() == marker_value, f"Extracted content for {base} was not preserved"

            metadata_files = matching_files(accepted, "metadata.json")
            assert metadata_files, f"metadata.json from {base} was not copied"
            for metadata in metadata_files:
                json.loads(metadata.read_text())

            docs = list(accepted.rglob("*.md")) + list(accepted.rglob("*.txt"))
            assert docs, f"Documentation files from {base} were not copied"
            assert all((p.stat().st_mode & 0o111) == 0 for p in docs), f"Clean file permissions were not preserved for {base}"

        for base in evil_names:
            assert not (out / base).exists() and not (out / f"{base}.tar.gz").exists(), (
                f"Evil generated bundle {base} was accepted.\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
