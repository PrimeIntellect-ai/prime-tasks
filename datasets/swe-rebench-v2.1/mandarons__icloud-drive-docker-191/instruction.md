[BUG] Folder mentioned in the "ignore" section of config.yaml gets downloaded
**Describe the bug**
Folder mentioned in the `ignore` section is still downloaded

**To Reproduce**
Added folder to the `ignore` section of `config.yaml`.

**Expected behavior**
Ignored folder should not be downloaded.

**Screenshots**
N/A

**Configuration**
N/A

**Additional context**
Here's the yaml in question. I am expecting "Music" to not be downloaded, yet it was.
```
drive:
  destination: "/media/icloud/drive"
  remove_obsolete: true
  sync_interval: 300
  filters: # Optional - use it only if you want to download specific folders.
    # File filters to be included in syncing iCloud drive content
    folders:
      - "Data\ Store"
    file_extensions:
      # File extensions to be included
      # - "pdf"
  ignore:
      - "Data Store/Music/*"
      # - "*.md"
```
I've tried variations like:
* `"Music"`
* `"Data Store/Music/"`
* `"Data\ Store/Music"`
They all result in the Music folder being downloaded.

### Additional contract requirements

- `src/sync_drive.py` provides a public function `wanted_parent_folder(filters, ignore, root, folder_path)`. It returns `True` when `filters` is empty or unset, and otherwise returns `True` only when `folder_path` is one of the configured filter folders or lies inside one of them (relative to `root`); it returns `False` otherwise.
