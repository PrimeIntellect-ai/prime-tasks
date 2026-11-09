#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy matplotlib

    mkdir -p /home/user

    cat << 'EOF' > /home/user/input.pdb
ATOM      1  N   ALA A   1      -1.424  -2.193   0.218  1.00 13.90           N  
ATOM      2  CA  ALA A   1       0.039  -2.221   0.245  1.00 13.11           C  
ATOM      3  C   ALA A   1       0.556  -0.814   0.509  1.00 13.56           C  
ATOM      4  O   ALA A   1       1.455  -0.612   1.328  1.00 14.12           O  
ATOM      5  CB  ALA A   1       0.592  -3.155   1.306  1.00 13.50           C  
ATOM      6  N   CYS A   2      -0.038   0.147  -0.198  1.00 12.39           N  
ATOM      7  CA  CYS A   2       0.360   1.543   0.007  1.00 12.63           C  
ATOM      8  C   CYS A   2       0.267   2.368  -1.272  1.00 11.87           C  
ATOM      9  O   CYS A   2      -0.569   2.115  -2.138  1.00 12.60           O  
ATOM     10  CB  CYS A   2      -0.457   2.164   1.143  1.00 12.98           C  
ATOM     11  SG  CYS A   2       0.063   3.856   1.503  1.00 14.71           S  
EOF

    cat << 'EOF' > /home/user/heat_sim.py
import numpy as np
import matplotlib.pyplot as plt

def parse_pdb(filepath):
    coords = []
    with open(filepath, 'r') as f:
        for line in f:
            if line.startswith("ATOM"):
                x = float(line[30:38])
                y = float(line[38:46])
                z = float(line[46:54])
                coords.append((x, y, z))
    return np.array(coords)

def main():
    coords = parse_pdb("/home/user/input.pdb")

    # Grid setup: 20 points from -10 to 10
    N = 20
    x_edges = np.linspace(-10, 10, N+1)
    y_edges = np.linspace(-10, 10, N+1)
    z_edges = np.linspace(-10, 10, N+1)
    dx = x_edges[1] - x_edges[0] # Should be 20.0 / 20 = 1.0

    T = np.zeros((N, N, N))

    # Map atoms to grid
    for coord in coords:
        ix = np.digitize(coord[0], x_edges) - 1
        iy = np.digitize(coord[1], y_edges) - 1
        iz = np.digitize(coord[2], z_edges) - 1

        # clamp to valid indices
        ix = max(0, min(N-1, ix))
        iy = max(0, min(N-1, iy))
        iz = max(0, min(N-1, iz))

        T[ix, iy, iz] = 100.0

    alpha = 0.1
    # BUG: dt is too large, leading to divergence
    dt = 0.5 

    steps = 500
    for step in range(steps):
        T_new = T.copy()
        for i in range(1, N-1):
            for j in range(1, N-1):
                for k in range(1, N-1):
                    laplacian = (
                        T[i+1, j, k] + T[i-1, j, k] +
                        T[i, j+1, k] + T[i, j-1, k] +
                        T[i, j, k+1] + T[i, j, k-1] -
                        6 * T[i, j, k]
                    ) / (dx**2)
                    T_new[i, j, k] = T[i, j, k] + alpha * dt * laplacian
        T = T_new

    # Plotting
    max_z = np.max(T, axis=(0, 1))
    plt.plot(range(N), max_z)
    plt.savefig("/home/user/z_profile.png")

    with open("/home/user/max_temp.txt", "w") as f:
        f.write(f"{np.max(T):.4f}\n")

if __name__ == "__main__":
    main()
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
