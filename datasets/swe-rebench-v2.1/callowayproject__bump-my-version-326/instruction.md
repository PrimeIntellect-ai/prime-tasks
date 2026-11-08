Custom searches do not fail if the file also contains the version number
- bump-my-version version: `1.0.2`
- python version: `3.11.1`
- OS: `Windows 11, 23H2, 22631.4890`

**Expectation:**
When doing a custom search if the search pattern is not found, a `VersionNotFoundError` should be raised. I ran into this issue when migrating from bump2version to bump-my-version.

**My setup:**

pyproject.toml:
```
[tool.bumpversion]
current_version = "2.0.1"
parse = """(?x)
    (?P<major>0|[1-9]\\d*)\\.
    (?P<minor>0|[1-9]\\d*)\\.
    (?P<patch>0|[1-9]\\d*)
    (?:
        -                             # dash separator for pre-release section
        (?P<pre_l>[a-zA-Z-]+)         # pre-release label
        (?:0|[1-9]\\d*)               # pre-release version number
    )?                                # pre-release section is optional
"""

serialize = [
  "{major}.{minor}.{patch}-{pre_l}{distance_to_latest_tag}",
  "{major}.{minor}.{patch}",
]

[tool.bumpversion.parts.pre_l]
values = ["rc", "final"]
optional_value = "final"

# this is the first of many searches
[[tool.bumpversion.files]]
filename = "CHANGELOG.adoc"
search = ":approved-for-release: yes"
replace = ":approved-for-release: no"
```

CHANGELOG.adoc:
```
// Metadata
:doctitle: Changelog - bump_test
:orgname:
:version-label:
:revnumber: 2.0.1
:revdate: Mar 14, 2025, 14:18 PM

// IMPORTANT!  DO NOT CHANGE UNTIL YOU ARE READY TO BUMP VERSION
// AND UNRELEASED SECTION HAS BEEN REVIEWED!
// Once changged, please preview before bump to make sure no formatting mistakes were made
:approved-for-release: no
```

When calling bump to update minor I get the following output and no failures even though the line being searched for does not exist in CHANGELOG.adoc:
```
File CHANGELOG.adoc: replace ':approved-for-release: yes' with ':approved-for-release: no' D:\Projects\frf-bump_test\.venv\Lib\site-packages\bumpversion\files.py:174
  Serializing the current version D:\Projects\frf-bump_test\.venv\Lib\site-packages\bumpversion\files.py:219
    Serializing version '<bumpversion.Version:major=2, minor=0, patch=1, pre_l=final>' D:\Projects\frf-bump_test\.venv\Lib\site-packages\bumpversion\versioning\serialization.py:102
      Using serialization format '{major}.{minor}.{patch}' D:\Projects\frf-bump_test\.venv\Lib\site-packages\bumpversion\versioning\serialization.py:133
      Serialized to '2.0.1' D:\Projects\frf-bump_test\.venv\Lib\site-packages\bumpversion\versioning\serialization.py:135
  Serializing the new version D:\Projects\frf-bump_test\.venv\Lib\site-packages\bumpversion\files.py:219
    Serializing version '<bumpversion.Version:major=2, minor=1, patch=0, pre_l=rc>' D:\Projects\frf-bump_test\.venv\Lib\site-packages\bumpversion\versioning\serialization.py:102
      Using serialization format '{major}.{minor}.{patch}-{pre_l}{distance_to_latest_tag}' D:\Projects\frf-bump_test\.venv\Lib\site-packages\bumpversion\versioning\serialization.py:133
      Serialized to '2.1.0-rc4' D:\Projects\frf-bump_test\.venv\Lib\site-packages\bumpversion\versioning\serialization.py:135
  Rendering search pattern with context D:\Projects\frf-bump_test\.venv\Lib\site-packages\bumpversion\config\models.py:56
    No RegEx flag detected. Searching for the default pattern: ':approved\-for\-release:\ yes' D:\Projects\frf-bump_test\.venv\Lib\site-packages\bumpversion\config\models.py:62
  Found '2\.0\.1' at line 5: 2.0.1 D:\Projects\frf-bump_test\.venv\Lib\site-packages\bumpversion\files.py:27
  Rendering search pattern with context D:\Projects\frf-bump_test\.venv\Lib\site-packages\bumpversion\config\models.py:56
    No RegEx flag detected. Searching for the default pattern: ':approved\-for\-release:\ yes' D:\Projects\frf-bump_test\.venv\Lib\site-packages\bumpversion\config\models.py:62
  Not changing file CHANGELOG.adoc D:\Projects\frf-bump_test\.venv\Lib\site-packages\bumpversion\files.py:67

```
As mentioned above, I would expect to be informed of the failure to find the search string in the document, instead it reports:
```
 Found '2\.0\.1' at line 5: 2.0.1 D:\Projects\frf-bump_test\.venv\Lib\site-packages\bumpversion\files.py:27
```

When digging into this I found the following difference between bump2version and bump-my-version:

[HIDDEN]
If I remove the rev number from line 5 of the `CHANGELOG.adoc` then when it doesn't find my custom search or the version I get the expected error:
```
Did not find ':approved-for-release: yes' in file: 'CHANGELOG.adoc'
```
