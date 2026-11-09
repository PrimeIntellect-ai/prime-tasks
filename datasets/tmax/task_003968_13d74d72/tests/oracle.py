import sys, math

y = float(sys.argv[1])
t_end = float(sys.argv[2])
h = float(sys.argv[3])
t = 0.0
steps = 0
TOL = 0.00042

def f(y, t):
    return -y*y + t

while t < t_end:
    # floating point precision guard
    if t + h > t_end or abs(t + h - t_end) < 1e-9:
        h = t_end - t
        if h <= 0:
            break

    y_full = y + h * f(y, t)
    h_half = h / 2.0
    y_half1 = y + h_half * f(y, t)
    y_half = y_half1 + h_half * f(y_half1, t + h_half)

    err = abs(y_full - y_half)

    # Avoid division by zero
    if err == 0:
        err = 1e-12

    h_new = h * 0.9 * math.sqrt(TOL / err)

    if h_new > 0.5: h_new = 0.5
    if h_new < 1e-5: h_new = 1e-5

    if err <= TOL:
        y = y_half
        t = t + h
        steps += 1

    h = h_new

print(f"{y:.5f} {steps}")
