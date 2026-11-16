Bug - get_repository returns boolean when repo not found
I am writing code that is checking if a repository exists. I use curator.utils.repository_exists which calls get_repository and expects a dict in return. However, if the repository I am searching for does not exist, get_repository returns a bool (False) instead of a dict, so curator.utils.repository_exists fails with the following error:

  File "/var/task/curator/utils.py", line 925, in repository_exists
    if repository in test_result:
TypeError: argument of type 'bool' is not iterable

curator version:
**version** = '4.1.0'
