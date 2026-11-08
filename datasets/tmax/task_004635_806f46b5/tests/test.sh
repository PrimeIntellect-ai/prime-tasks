#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import io
import os
import re
import subprocess
import sys
import tarfile
import zipfile

import pytesseract
from PIL import Image, ImageOps


def extract_overrides():
    image_path = '/app/config_schematic.png'
    assert os.path.isfile(image_path), f"Configuration schematic not found at {image_path}"

    image = Image.open(image_path).convert('L')
    enlarged = ImageOps.autocontrast(image).resize(
        (image.width * 4, image.height * 4), Image.Resampling.LANCZOS
    )
    text = '\n'.join([
        pytesseract.image_to_string(image, config='--psm 6'),
        pytesseract.image_to_string(enlarged, config='--psm 6'),
    ])

    max_match = re.search(r'MAX[\s_]*CONNECTIONS\s*=\s*(\d+)', text, re.IGNORECASE)
    timeout_match = re.search(r'TIMEOUT\s*=\s*(\d+)', text, re.IGNORECASE)
    assert max_match is not None, f"Could not OCR MAX_CONNECTIONS from schematic: {text!r}"
    assert timeout_match is not None, f"Could not OCR TIMEOUT from schematic: {text!r}"

    values = (max_match.group(1), timeout_match.group(1))
    assert values == ('8192', '45'), f"Unexpected schematic values: {values!r}"
    return values


def test_updated_configs_archive():
    script = '/app/update_configs.py'
    target_file = '/app/updated_configs.tar.xz'

    assert os.path.isfile(script), f"Update script not found at {script}"
    assert not os.path.islink(script), f"Update script must be a regular file, not a symlink: {script}"

    max_connections, timeout = extract_overrides()

    # The submitted script itself must generate the deliverable during verification.
    if os.path.lexists(target_file):
        os.remove(target_file)
    result = subprocess.run(
        [sys.executable, script],
        cwd='/app',
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=120,
    )
    assert result.returncode == 0, (
        f"update_configs.py failed with exit code {result.returncode}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )

    assert os.path.exists(target_file), f"Output file not found at {target_file}"
    assert os.path.isfile(target_file), f"Output path is not a regular file: {target_file}"

    size = os.path.getsize(target_file)
    assert size <= 102400, f"File size {size} is strictly greater than threshold 102400 bytes"

    expected_tar_names = [f'cluster_{i}.zip' for i in range(10)]
    expected_conf_names = [f'config_{j}.conf' for j in range(50)]

    # Verify contents and ensure none of the original 10 zips or 500 configs were omitted.
    with tarfile.open(target_file, 'r:xz') as tar:
        members = tar.getmembers()
        assert len(members) > 0, "The tar.xz archive is empty"
        assert len(members) == len(expected_tar_names), (
            f"Expected 10 zip members, found {len(members)}"
        )
        assert [member.name for member in members] == expected_tar_names, (
            f"Unexpected tar members: {[member.name for member in members]!r}"
        )

        for i, member in enumerate(members):
            assert member.name.endswith('.zip'), f"Found non-zip member in tar: {member.name}"
            assert member.isfile(), f"Tar member is not a regular zip file: {member.name}"
            f = tar.extractfile(member)
            assert f is not None, f"Could not extract {member.name}"

            with zipfile.ZipFile(io.BytesIO(f.read())) as zf:
                infos = zf.infolist()
                namelist = zf.namelist()
                assert len(namelist) > 0, f"Zip file {member.name} is empty"
                assert len(namelist) == len(expected_conf_names), (
                    f"Expected 50 configurations in {member.name}, found {len(namelist)}"
                )
                assert namelist == expected_conf_names, (
                    f"Unexpected configuration members in {member.name}: {namelist!r}"
                )
                assert all(not info.is_dir() for info in infos), (
                    f"Found a directory entry in {member.name}"
                )

                for j, conf_name in enumerate(namelist):
                    assert conf_name.endswith('.conf'), f"Found non-conf file in zip: {conf_name}"
                    content = zf.read(conf_name).decode('utf-8')
                    assert "MAX_CONNECTIONS=8192" in content, (
                        f"MAX_CONNECTIONS not correctly updated in {conf_name} of {member.name}"
                    )
                    assert "TIMEOUT=45" in content, (
                        f"TIMEOUT not correctly updated in {conf_name} of {member.name}"
                    )

                    expected_content = (
                        f"SERVER_ID={i}_{j}\n"
                        f"LOG_LEVEL=DEBUG\n"
                        f"MAX_CONNECTIONS={max_connections}\n"
                        f"TIMEOUT={timeout}\n"
                        + ("PADDING=X" * 100)
                        + "\n"
                    )
                    assert content == expected_content, (
                        f"Configuration content was lost or altered in {conf_name} of {member.name}"
                    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
