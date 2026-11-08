#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import tarfile
import pytest


def test_etl_output_file():
    """Check that the output summary file exists and contains the correct aggregated data."""
    output_path = '/home/user/etl_output/category_summary.tsv'
    assert os.path.isfile(output_path), f"Output file {output_path} does not exist."

    expected_lines = [
        "Apparel\t232.50\t15.00",
        "Electronics\t1394.03\t104.95",
        "Groceries\t65.00\t0.00",
        "Home_Goods\t120.00\t30.00"
    ]

    with open(output_path, 'r') as f:
        actual_lines = [line.strip() for line in f.readlines() if line.strip()]

    assert actual_lines == expected_lines, (
        f"Content of {output_path} is incorrect.\n"
        f"Expected:\n{chr(10).join(expected_lines)}\n"
        f"Got:\n{chr(10).join(actual_lines)}"
    )


def test_archive_exists():
    """Check that the archive contains the complete original raw_data tree and contents."""
    archive_path = '/home/user/archive/raw_data_backup.tar.gz'
    assert os.path.isfile(archive_path), f"Archive file {archive_path} does not exist."
    assert tarfile.is_tarfile(archive_path), f"File {archive_path} is not a valid tar archive."

    expected_files = {
        'raw_data/region_north/store_12/sales_20231001.csv': (
            b'transaction_id,item_category,quantity,unit_price,discount_percentage\n'
            b'TXN001,Electronics,2,299.99,10\n'
            b'TXN002,Apparel,5,19.50,0\n'
            b'TXN003,Home_Goods,1,150.00,20\n'
        ),
        'raw_data/region_south/store_05/sales_20231001.csv': (
            b'transaction_id,item_category,quantity,unit_price,discount_percentage\n'
            b'TXN004,Electronics,1,899.00,5\n'
            b'TXN005,Apparel,10,15.00,10\n'
            b'TXN006,Groceries,20,3.25,0\n'
        ),
    }
    allowed_dirs = {
        'raw_data',
        'raw_data/region_north',
        'raw_data/region_north/store_12',
        'raw_data/region_south',
        'raw_data/region_south/store_05',
    }

    with open(archive_path, 'rb') as f:
        assert f.read(2) == b'\x1f\x8b', f"File {archive_path} is not gzip-compressed."

    with tarfile.open(archive_path, 'r:gz') as tar:
        names = tar.getnames()
        assert any('sales_20231001.csv' in name for name in names), \
            "Archive does not contain the expected sales CSV files."

        archived_files = {}
        for member in tar.getmembers():
            name = member.name
            while name.startswith('./'):
                name = name[2:]
            name = name.rstrip('/')

            assert name and not name.startswith('/') and '..' not in name.split('/'), \
                f"Archive contains an unsafe path: {member.name}"

            if member.isdir():
                assert name in allowed_dirs, f"Archive contains unexpected directory: {member.name}"
                continue

            assert member.isfile(), f"Archive contains a non-regular member: {member.name}"
            assert name in expected_files, f"Archive contains unexpected file: {member.name}"
            assert name not in archived_files, f"Archive contains duplicate file: {member.name}"
            extracted = tar.extractfile(member)
            assert extracted is not None
            archived_files[name] = extracted.read()

        assert set(archived_files) == set(expected_files), (
            f"Archive file set is incorrect. Expected {sorted(expected_files)}, "
            f"got {sorted(archived_files)}"
        )
        for name, expected_content in expected_files.items():
            assert archived_files[name] == expected_content, \
                f"Archived content is incorrect for {name}"


def test_raw_data_deleted():
    """Check that the original raw_data directory was deleted."""
    raw_data_path = '/home/user/raw_data/'
    assert not os.path.exists(raw_data_path), f"Directory {raw_data_path} still exists. It should have been deleted."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
