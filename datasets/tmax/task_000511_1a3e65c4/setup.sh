#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg gcc
    pip3 install pytest

    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    python3 -c '
import os

def write_pdb(filename, coords):
    with open(filename, "w") as f:
        for i, (x, y, z) in enumerate(coords):
            f.write(f"ATOM  {i+1:5d}  CA  ALA A {i+1:3d}    {x:8.3f}{y:8.3f}{z:8.3f}\n")

# Clean PDBs (distance between 2.5 and 4.5)
write_pdb("/app/corpus/clean/clean1.pdb", [(0,0,0), (3.0,0,0), (6.0,0,0)])
write_pdb("/app/corpus/clean/clean2.pdb", [(0,0,0), (0,4.0,0), (0,8.0,0)])

# Evil PDBs (distance < 2.5 or > 4.5, or no CA)
write_pdb("/app/corpus/evil/evil1.pdb", [(0,0,0), (2.0,0,0), (4.0,0,0)])
write_pdb("/app/corpus/evil/evil2.pdb", [(0,0,0), (5.0,0,0), (10.0,0,0)])
with open("/app/corpus/evil/evil3.pdb", "w") as f:
    f.write("ATOM      1  N   ALA A   1       0.000   0.000   0.000\n")

# Video generation (4 white frames, 56 black frames)
os.makedirs("/tmp/frames", exist_ok=True)
for i in range(60):
    color = "255 255 255" if i < 4 else "0 0 0"
    with open(f"/tmp/frames/frame_{i:03d}.ppm", "w") as f:
        f.write(f"P3\n10 10\n255\n" + (f"{color}\n" * 100))
os.system("ffmpeg -y -framerate 10 -i /tmp/frames/frame_%03d.ppm /app/sim_video.mp4 > /dev/null 2>&1")
'

    rm -rf /tmp/frames

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
