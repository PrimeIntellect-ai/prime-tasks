import re
with open('/app/headers_dataset.txt', 'r') as f:
    data = f.read().split('\n\n')
score = 0
for block in data:
    if not block.strip(): continue
    if 'Content-Security-Policy:' not in block:
        score += 5
    if 'Strict-Transport-Security:' not in block:
        score += 3
    for line in block.split('\n'):
        if line.startswith('Set-Cookie:'):
            if 'Secure' not in line or 'HttpOnly' not in line:
                score += 4
        if line.startswith('Server:'):
            if '/' in line:
                score -= 2
print(score)
