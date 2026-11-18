import sys
import json
import csv

video_seq = ['R', 'G', 'B', 'R', 'R', 'G', 'B', 'B', 'G', 'R', 'R', 'B', 'G', 'G', 'R', 'B', 'B', 'R', 'G', 'G', 'R', 'R', 'R', 'B', 'B', 'B', 'G', 'G', 'G', 'R', 'B', 'G', 'R', 'B', 'G', 'R', 'B', 'G', 'R', 'B', 'G', 'G', 'R', 'R', 'B', 'B', 'R', 'G', 'B', 'R', 'G', 'B', 'R', 'G', 'B', 'R', 'G', 'B', 'R', 'G']

def get_emp(csv_path, target_id):
    tree = {}
    emps = {}
    with open(csv_path, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            d = row['dept_id']
            p = row['parent_id']
            e = int(row['employees'])
            emps[d] = e
            if p not in tree:
                tree[p] = []
            tree[p].append(d)

    def dfs(node):
        total = emps.get(node, 0)
        for child in tree.get(node, []):
            total += dfs(child)
        return total

    return dfs(target_id)

start_sec = int(sys.argv[1])
end_sec = int(sys.argv[2])
dept_id = sys.argv[3]

sub = video_seq[start_sec:end_sec+1]
r_c = sub.count('R')
g_c = sub.count('G')
b_c = sub.count('B')

total_emp = get_emp('/home/user/org_chart.csv', dept_id)

print(json.dumps({
    "R_score": r_c * total_emp,
    "G_score": g_c * total_emp,
    "B_score": b_c * total_emp
}))
