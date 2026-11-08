flatten_top_directories on single file
The following error is raised when trying to use `flatten_top_directories()` on a directory containing a single file or when downloading a product having a single asset and the download plugin configured with `flatten_top_dirs: true`:
```
Traceback (most recent call last):
  File "/home/sylvain/workspace/eodag-debug/20230207_download_issue.py", line 78, in <module>
    downloaded_path = dag.download(search_results[0])
  File "/home/sylvain/workspace/eodag/eodag/api/core.py", line 1753, in download
    path = product.download(
  File "/home/sylvain/workspace/eodag/eodag/api/product/_product.py", line 313, in download
    fs_path = self.downloader.download(
  File "/home/sylvain/workspace/eodag/eodag/plugins/download/http.py", line 260, in download
    fs_path = self._download_assets(
  File "/home/sylvain/workspace/eodag/eodag/plugins/download/http.py", line 607, in _download_assets
    flatten_top_directories(fs_dir_path)
  File "/home/sylvain/workspace/eodag/eodag/utils/__init__.py", line 1159, in flatten_top_directories
    shutil.copytree(common_subdirs_path, tmp_path)
  File "/usr/lib/python3.8/shutil.py", line 555, in copytree
    with os.scandir(src) as itr:
NotADirectoryError: [Errno 20] Not a directory: '/tmp/foo_path'
```
