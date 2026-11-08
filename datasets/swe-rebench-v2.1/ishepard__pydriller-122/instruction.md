commit.project_name broken when working on multiple repos
**Describe the bug**
commit.project_name broken when working on multiple repos

**To Reproduce**
```
from pydriller import RepositoryMining

repos = [
    "C:/jcb/code/montagel",
    "C:/jcb/code/Xrf",
]
print(repos)

starttag = "com.jcbachmann.xrf.suite/v11"
endtag = "com.jcbachmann.xrf.suite/v12"

for commit in RepositoryMining(path_to_repo=repos[0], from_tag=starttag, to_tag=endtag).traverse_commits():
    print(commit.project_name)
print("repo 0 OK")

for commit in RepositoryMining(path_to_repo=repos[1], from_tag=starttag, to_tag=endtag).traverse_commits():
    print(commit.project_name)
print("repo 1 OK")

for commit in RepositoryMining(path_to_repo=repos, from_tag=starttag, to_tag=endtag).traverse_commits():
    print(commit.project_name)
    pass
print("repos tagged OK")
```

gives

```
C:\jcb\venvs\Xrf\Scripts\python.exe C:/jcb/code/Xrf-Python/Documentation/chapters/software/bug.py
['C:/jcb/code/montagel', 'C:/jcb/code/Xrf']
montagel
[...]
repo 0 OK
Xrf
[...]
repo 1 OK
Traceback (most recent call last):
  File "C:/jcb/code/Xrf-Python/Documentation/chapters/software/bug.py", line 23, in <module>
    print(commit.project_name)
  File "C:\jcb\venvs\Xrf\lib\site-packages\pydriller\domain\commit.py", line 479, in project_name
    return Path(self._conf.get('path_to_repo')).name
  File "C:\Python37\lib\pathlib.py", line 1003, in __new__
    self = cls._from_parts(args, init=False)
  File "C:\Python37\lib\pathlib.py", line 658, in _from_parts
    drv, root, parts = self._parse_args(args)
  File "C:\Python37\lib\pathlib.py", line 642, in _parse_args
    a = os.fspath(a)
TypeError: expected str, bytes or os.PathLike object, not list

Process finished with exit code 1

```


**OS Version:**
pydriller 1.15 with C:\Python37\python.exe
