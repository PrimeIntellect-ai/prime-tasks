#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-venv
    pip3 install pytest

    mkdir -p /home/user/data /home/user/scripts /home/user/results

    cat << 'EOF' > /home/user/data/protein.pdb
ATOM      1  N   ALA A   1      11.104   6.134  -6.504  1.00  0.00           N  
ATOM      2  CA  ALA A   1      11.639   6.071  -5.147  1.00  0.00           C  
ATOM      3  C   ALA A   1      10.859   6.987  -4.225  1.00  0.00           C  
ATOM      4  O   ALA A   1       9.813   7.489  -4.636  1.00  0.00           O  
ATOM      5  CB  ALA A   1      13.115   6.460  -5.195  1.00  0.00           C  
ATOM      6  N   CYS A   2      11.371   7.202  -3.007  1.00  0.00           N  
ATOM      7  CA  CYS A   2      10.743   8.053  -1.996  1.00  0.00           C  
ATOM      8  C   CYS A   2      10.985   9.531  -2.304  1.00  0.00           C  
ATOM      9  O   CYS A   2      12.112   9.932  -2.585  1.00  0.00           O  
ATOM     10  CB  CYS A   2      11.266   7.669  -0.609  1.00  0.00           C  
ATOM     11  N   ASP A   3       9.919  10.334  -2.247  1.00  0.00           N  
ATOM     12  CA  ASP A   3      10.021  11.770  -2.497  1.00  0.00           C  
ATOM     13  C   ASP A   3       9.610  12.593  -1.282  1.00  0.00           C  
ATOM     14  O   ASP A   3       8.418  12.723  -1.025  1.00  0.00           O  
ATOM     15  CB  ASP A   3       9.141  12.146  -3.693  1.00  0.00           C  
ATOM     16  N   GLU A   4      10.608  13.149  -0.551  1.00  0.00           N  
ATOM     17  CA  GLU A   4      10.354  13.966   0.618  1.00  0.00           C  
ATOM     18  C   GLU A   4       9.757  15.318   0.245  1.00  0.00           C  
ATOM     19  O   GLU A   4       8.932  15.845   0.989  1.00  0.00           O  
ATOM     20  CB  GLU A   4      11.649  14.167   1.411  1.00  0.00           C  
EOF

    cat << 'EOF' > /home/user/scripts/analyze.py
import numpy as np
from Bio.PDB import PDBParser
import networkx as nx

def get_calpha_coords(pdb_file):
    parser = PDBParser(QUIET=True)
    structure = parser.get_structure("protein", pdb_file)
    coords = []
    for model in structure:
        for chain in model:
            for residue in chain:
                if "CA" in residue:
                    coords.append(residue["CA"].coord)
    return np.array(coords)

def main():
    coords = get_calpha_coords("/home/user/data/protein.pdb")
    n = len(coords)

    # Create contact graph
    G = nx.Graph()
    G.add_nodes_from(range(n))
    for i in range(n):
        for j in range(i+1, n):
            if np.linalg.norm(coords[i] - coords[j]) < 7.0:
                G.add_edge(i, j)

    centrality = np.array(list(nx.degree_centrality(G).values()))

    # Features: [Bias, distance_from_centroid, redundant_feature]
    centroid = np.mean(coords, axis=0)
    dist = np.linalg.norm(coords - centroid, axis=1)

    X = np.column_stack([
        np.ones(n),
        dist,
        dist * 2.0  # Deliberately collinear to make X.T @ X singular
    ])

    # BUG: OLS fails or gives unstable results due to singular matrix
    beta = np.linalg.inv(X.T @ X) @ X.T @ centrality

    # Save results
    with open("/home/user/results/coefficients.txt", "w") as f:
        for b in beta:
            f.write(f"{b:.4f}\n")

if __name__ == "__main__":
    main()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
