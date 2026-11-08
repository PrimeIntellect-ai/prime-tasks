Python requirements file without pinned version crashes cdxgen
Created an empty project `abcd`
```
ubuntu@MACHINE:~$ tree abcd
abcd
└── requirements.txt
```

Requirements contain multiple unpinned dependencies
```
ubuntu@ip-172-24-11-180:~$ cat abcd/requirements.txt
ipython
apache-airflow-providers-pagerduty
matplotlib
seaborn
retrying
dataframe-image
lxml
openpyxl
xlrd
apache-airflow-providers-apache-livy
apache-airflow-providers-http
markupsafe
gspread
oauth2client
duckdb
facebook-business
facebookads
apache-airflow-providers-slack
apache-airflow-providers-ssh
pyzipper
apache-airflow-providers-mysql
jira
cron-descriptor
```

Then run `cdxgen`
```
ubuntu@MACHINE:~$ ~/path/to/dir/node_modules/.bin/cdxgen abcd
 Traceback (most recent call last):
  File "/tmp/cdxgen-piptree-y9GpJ5/piptree.py", line 87, in <module>
    main(sys.argv)
  File "/tmp/cdxgen-piptree-y9GpJ5/piptree.py", line 72, in main
    "dependencies": find_deps(idx, p.requires()),
  File "/tmp/cdxgen-piptree-y9GpJ5/piptree.py", line 48, in find_deps
    "dependencies": find_deps(idx, d.requires()),
  File "/tmp/cdxgen-piptree-y9GpJ5/piptree.py", line 48, in find_deps
    "dependencies": find_deps(idx, d.requires()),
  File "/tmp/cdxgen-piptree-y9GpJ5/piptree.py", line 48, in find_deps
    "dependencies": find_deps(idx, d.requires()),
  [Previous line repeated 981 more times]
  File "/tmp/cdxgen-piptree-y9GpJ5/piptree.py", line 46, in find_deps
    "version": importlib_metadata.version(r.key),
  File "/usr/lib/python3.10/importlib/metadata/__init__.py", line 984, in version
    return distribution(distribution_name).version
  File "/usr/lib/python3.10/importlib/metadata/__init__.py", line 957, in distribution
    return Distribution.from_name(distribution_name)
  File "/usr/lib/python3.10/importlib/metadata/__init__.py", line 543, in from_name
    dists = resolver(DistributionFinder.Context(name=name))
  File "<frozen importlib._bootstrap_external>", line 1482, in find_distributions
  File "/usr/lib/python3.10/importlib/metadata/__init__.py", line 896, in find_distributions
    found = cls._search_paths(context.name, context.path)
  File "/usr/lib/python3.10/importlib/metadata/__init__.py", line 902, in _search_paths
    prepared = Prepared(name)
  File "/usr/lib/python3.10/importlib/metadata/__init__.py", line 863, in __init__
    self.normalized = self.normalize(name)
  File "/usr/lib/python3.10/importlib/metadata/__init__.py", line 871, in normalize
    return re.sub(r"[-_.]+", "-", name).lower().replace('-', '_')
  File "/usr/lib/python3.10/re.py", line 209, in sub
    return _compile(pattern, flags).sub(repl, string, count)
  File "/usr/lib/python3.10/re.py", line 290, in _compile
    if isinstance(flags, RegexFlag):
RecursionError: maximum recursion depth exceeded while calling a Python object

file:///path/to/dir/node_modules/@cyclonedx/cdxgen/utils.js:5559
    for (const t of tree) {
                    ^

TypeError: tree is not iterable
    at getPipFrozenTree (file:///path/to/dir/node_modules/@cyclonedx/cdxgen/utils.js:5559:21)
    at createPythonBom (file:///path/to/dir/node_modules/@cyclonedx/cdxgen/index.js:2125:28)
    at createMultiXBom (file:///path/to/dir/node_modules/@cyclonedx/cdxgen/index.js:3840:21)
    at async createBom (file:///path/to/dir/node_modules/@cyclonedx/cdxgen/index.js:4695:16)
    at async file:///path/to/dir/node_modules/@cyclonedx/cdxgen/bin/cdxgen.js:229:22

Node.js v18.16.1
```

It's a wild guess but it appears unpinned dependencies are causing a problem here.

### Additional contract requirements

- Running cdxgen against the described Python project with unpinned requirements should complete without crashing.
- When `getPipFrozenTree` processes a Python environment with a circular dependency, its returned `pkgList` must contain an entry whose `name` is exactly `pkgc`.
