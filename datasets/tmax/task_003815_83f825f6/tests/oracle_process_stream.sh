#!/usr/bin/awk -f
BEGIN {
    hist[0] = 0; hist[1] = 0; hist[2] = 0;
    count = 0;
}
{
    val = $1;
    if (val == "NaN") {
        if (count == 0) {
            imp = 0;
        } else {
            n = (count < 3) ? count : 3;
            sum = 0;
            for (i=0; i<n; i++) { sum += hist[i]; }
            imp = int(sum / n);
        }
    } else {
        imp = int(val);
    }

    # shift history
    hist[2] = hist[1];
    hist[1] = hist[0];
    hist[0] = imp;
    count++;

    if (count >= 3) {
        filter = (1 * hist[0]) + (-2 * hist[1]) + (1 * hist[2]);
    } else {
        filter = 0;
    }

    print imp "," filter;
}
