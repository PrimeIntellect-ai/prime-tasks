Subject used as benchmark class in "default" report
Fixing would produce the following test failure:

```
 '+------+--------------+--------------+-----+------+----------+----------+--------------+----------------+\n
 | iter | benchmark    | subject      | set | revs | mem_peak | time_avg | comp_z_value | comp_deviation |\n
 +------+--------------+--------------+-----+------+----------+----------+--------------+----------------+\n
-| 0    | benchNothing | benchNothing | 0   | 1    | 100b     | 10.000μs | +0.00σ       | +0.00%         |\n
+| 0    | NothingBench | benchNothing | 0   | 1    | 100b     | 10.000μs | +0.00σ       | +0.00%         |\n
 +------+--------------+--------------+-----+------+----------+----------+--------------+----------------+
```
