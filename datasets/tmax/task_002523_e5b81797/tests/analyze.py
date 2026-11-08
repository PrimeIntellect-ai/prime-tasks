import sys
import networkx as nx
from scipy.stats import wasserstein_distance

def main():
    if len(sys.argv) != 2:
        sys.exit(1)
    seq = sys.argv[1]

    G = nx.MultiDiGraph()
    for i in range(len(seq) - 2):
        kmer = seq[i:i+3]
        G.add_edge(kmer[:2], kmer[1:])

    counts = {0:0, 1:0, 2:0, 3:0, 4:0}
    for node in G.nodes():
        deg = G.out_degree(node)
        if deg <= 4:
            counts[deg] += 1

    total_nodes = G.number_of_nodes()
    if total_nodes == 0:
        P = [1.0, 0.0, 0.0, 0.0, 0.0]
    else:
        P = [counts[i]/total_nodes for i in range(5)]

    Q = [0.05, 0.25, 0.40, 0.25, 0.05]

    dist = wasserstein_distance(
        u_values=[0, 1, 2, 3, 4],
        v_values=[0, 1, 2, 3, 4],
        u_weights=P,
        v_weights=Q
    )

    print(f"{dist:.6f}")

if __name__ == "__main__":
    main()
