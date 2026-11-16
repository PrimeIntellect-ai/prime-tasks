Include path in error message when get_metadata() raises e.g. UnicodeDecodeError
This issue is another manifestation of issue #1664 ("Include location of bad METADATA files in errors"), but [HIDDEN]: https://github.com/pypa/setuptools/blob/8aeff6b2c9a64e47ad2a22533d7e65c08cd4103f/pkg_resources/__init__.py#L1416-L1420

This came up recently in this pip issue (and probably other pip issues -- this is just one example): https://github.com/pypa/pip/issues/6566

Rather than re-opening #1664, it probably makes sense to have a new issue. It's unknown to me how many code paths in `pkg_resources` affect the larger issue. PR #1706 addressed the version-is-missing case.

### Additional contract requirements

- When `get_metadata()` raises `UnicodeDecodeError` while decoding a metadata file as UTF-8, include the path to that metadata file in the error message.
