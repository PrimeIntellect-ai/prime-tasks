tidy-imports adds newlines endlessly (PyInf#11818)
For Python scripts with a shebang and multiple non-stl imports, tidy-imports 1.8.8 always suggests an additional newline above the import list. tidy-imports 1.8.6 doesn't exhibit this issue.


```
> cat /var/tmp/b.py
#!/usr/local/bin/python3

from   deshaw.abc.def            import DAYS
from   deshaw.py                    import tuple

print(DAYS.days(20240101, 20241231))
print(tuple("hello"))

```

Runs:
```
:> tidy-imports /var/tmp/b.py --no-remove-unused
--- /var/tmp/b.py	2024-01-30 06:45:26.339223699 -0500
+++ /tmp/tmprbe0_36t	2024-01-30 06:45:35.797249821 -0500
@@ -1,5 +1,6 @@
 #!/usr/local/bin/python3

+
from   deshaw.abc.def            import DAYS
from   deshaw.py                    import tuple


Replace /var/tmp/b.py? [y/N] y
[PYFLYBY] /var/tmp/b.py: *** modified ***
dhamodha@vm1.henry45.toa(nyc|interactive):~(master):> tidy-imports /var/tmp/b.py --no-remove-unused
--- /var/tmp/b.py	2024-01-30 06:45:41.820266451 -0500
+++ /tmp/tmp1g_5_ksg	2024-01-30 06:45:43.613271400 -0500
@@ -1,6 +1,7 @@
 #!/usr/local/bin/python3


+
from   deshaw.abc.def            import DAYS
from   deshaw.py                    import tuple


Replace /var/tmp/b.py? [y/N] y
[PYFLYBY] /var/tmp/b.py: *** modified ***

```

I believe this is an easy and quick to fix issue.
