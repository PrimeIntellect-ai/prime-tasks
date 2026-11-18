import sys
import json
import math
from collections import defaultdict, deque

WINDOW_SIZE = 10
VARIANCE_THRESHOLD_MAX = 3.5
BASE_MULTIPLIER = 1.05

history = defaultdict(lambda: deque(maxlen=WINDOW_SIZE))

def parse_number(val, locale):
    val = val.replace(' ', '').replace('\u00A0', '').replace('\u202F', '')
    if locale in ['fr_FR', 'de_DE', 'es_ES', 'it_IT', 'pt_BR', 'ru_RU']:
        val = val.replace('.', '').replace(',', '.')
    else:
        val = val.replace(',', '')
    return float(val)

for line in sys.stdin:
    if not line.strip(): continue
    record = json.loads(line)
    metric = record['metric']
    raw_val = record['raw_value']
    locale = record['locale']

    val = parse_number(raw_val, locale)
    q = history[metric]

    if len(q) > 0:
        avg = sum(q) / len(q)
        variance = sum((x - avg) ** 2 for x in q) / len(q)
        std_dev = math.sqrt(variance)

        threshold = VARIANCE_THRESHOLD_MAX * std_dev
        is_outlier = False
        if abs(val - avg) > threshold and threshold > 0:
            is_outlier = True
            if val > avg + threshold:
                val = avg + threshold
            else:
                val = avg - threshold
    else:
        avg = val
        is_outlier = False

    q.append(val)
    final_val = val * BASE_MULTIPLIER

    print(f"{record['timestamp']},{metric},{final_val:.4f},{avg:.4f},{str(is_outlier).lower()}")
