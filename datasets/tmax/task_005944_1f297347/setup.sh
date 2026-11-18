#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Create directories and files using Python
    python3 -c '
import os

base_dir = "/home/user/dataset"
sub_dir = os.path.join(base_dir, "experiments", "run1")
output_dir = "/home/user/archive_output"

os.makedirs(sub_dir, exist_ok=True)
os.makedirs(output_dir, exist_ok=True)

config_path = os.path.join(base_dir, "config.ini")
with open(config_path, "w") as f:
    f.write("[Archive]\n")
    f.write("chunk_size_bytes = 1024\n")
    f.write("target_extension = .dat\n")
    f.write(f"output_dir = {output_dir}\n")

def create_file(path, size, seed_char):
    with open(path, "wb") as f:
        f.write((seed_char * size).encode("utf-8"))

file1_path = os.path.join(base_dir, "main_data.dat")
file2_path = os.path.join(sub_dir, "sensor_data.dat")
file3_path = os.path.join(base_dir, "ignore_me.txt")

create_file(file1_path, 2500, "A")
create_file(file2_path, 1500, "B")
create_file(file3_path, 5000, "C")

symlink_path = os.path.join(sub_dir, "loop_back")
if not os.path.exists(symlink_path):
    os.symlink(base_dir, symlink_path)
'

    chmod -R 777 /home/user
