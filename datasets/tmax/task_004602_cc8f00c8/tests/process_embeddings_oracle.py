#!/usr/bin/env python3
import sys
import numpy as np

def main():
    dataset = np.loadtxt(sys.argv[1], delimiter=',')
    matrix = np.loadtxt(sys.argv[2], delimiter=',')
    query = np.array([float(x) for x in sys.argv[3].split(',')])

    # Projection
    proj_dataset = dataset @ matrix
    proj_query = query @ matrix

    # L1 distances
    distances = np.sum(np.abs(proj_dataset - proj_query), axis=1)

    # Argmin
    print(np.argmin(distances))

if __name__ == "__main__":
    main()
