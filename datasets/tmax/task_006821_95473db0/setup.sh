#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas scikit-learn pyarrow

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/setup.py
import pandas as pd
import numpy as np
import os

os.makedirs('/home/user', exist_ok=True)

data = {
    'id': range(1, 31),
    'title': [
        'Algebraic Geometry and Scheme Theory', 'Combinatorial Graphs on Vertices', 
        'Probability Models in Random Walks', 'Cohomology of Sheaves in Geometry',
        'Bipartite Graph Matching Algorithms', 'Stochastic Processes and Martingales',
        'Projective Varieties and Morphisms', 'Eulerian Paths in Dense Graphs',
        'Brownian Motion in Continuous Time', 'Derived Categories in Algebra',
        'Planar Graphs and Four Color Theorem', 'Markov Chains and Applications',
        'Intersection Theory on Surfaces', 'Chromatic Polynomials of Graphs',
        'Large Deviations in Probability', 'Birational Geometry of Varieties',
        'Network Flows and Graph Theory', 'Poisson Point Processes',
        'Moduli Spaces of Curves', 'Random Graph Theory Methods',
        'Limit Theorems for Random Variables', 'Abelian Varieties and Jacobians',
        'Spectral Graph Theory Applications', 'Measure Theory and Probability',
        'Hodge Theory and Complex Geometry', 'Topological Graph Theory',
        'Queueing Theory and Stochastic Models', 'Fano Varieties and Classification',
        'Ramsey Theory for Graphs', 'Ergodic Theory and Dynamical Systems'
    ],
    'year': [
        2008, 2015, 2012, 2018, 2009, 2014, 2011, 2016, 2007, 2019,
        2020, 2010, 2013, 2005, 2021, 2017, 2006, 2014, 2019, 2012,
        2009, 2015, 2018, 2004, 2022, 2011, 2016, 2013, 2020, 2017
    ],
    'category': [
        'math.AG', 'math.CO', 'math.PR', 'math.AG', 'math.CO', 'math.PR',
        'math.AG', 'math.CO', 'math.PR', 'math.AG', 'math.CO', 'math.PR',
        'math.AG', 'math.CO', 'math.PR', 'math.AG', 'math.CO', 'math.PR',
        'math.AG', 'math.CO', 'math.PR', 'math.AG', 'math.CO', 'math.PR',
        'math.AG', 'math.CO', 'math.PR', 'math.AG', 'math.CO', 'math.PR'
    ]
}

df = pd.DataFrame(data)
df.to_csv('/home/user/papers.csv', index=False)
EOF

    python3 /home/user/setup.py
    rm /home/user/setup.py

    chmod -R 777 /home/user
