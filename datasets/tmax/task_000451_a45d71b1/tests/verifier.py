import csv
import sys

REFERENCE_TOP_50 = {'System_095', 'System_002', 'System_005', 'System_092', 'System_045', 'System_053', 'System_037', 'System_001', 'System_007', 'System_081', 'System_032', 'System_006', 'System_085', 'System_050', 'System_047', 'System_009', 'System_004', 'System_091', 'System_018', 'System_097', 'System_057', 'System_000', 'System_028', 'System_046', 'System_072', 'System_026', 'System_048', 'System_027', 'System_003', 'System_058', 'System_098', 'System_010', 'System_063', 'System_067', 'System_044', 'System_008', 'System_075', 'System_096', 'System_094', 'System_086', 'System_074', 'System_088', 'System_070', 'System_084', 'System_036', 'System_064', 'System_034', 'System_024', 'System_080', 'System_069'}

try:
    agent_systems = set()
    with open('/home/user/vulnerable_systems.csv', 'r') as f:
        reader = csv.reader(f)
        next(reader)
        for row in reader:
            if row[0].startswith("System_"):
                agent_systems.add(row[0])
            if len(agent_systems) == 50:
                break

    intersection = len(REFERENCE_TOP_50.intersection(agent_systems))
    union = len(REFERENCE_TOP_50.union(agent_systems))

    iou = intersection / union if union > 0 else 0.0
    print(iou)
except Exception as e:
    print(0.0)
