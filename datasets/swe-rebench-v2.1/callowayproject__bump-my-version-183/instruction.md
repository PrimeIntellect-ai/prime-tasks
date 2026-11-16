Glob pattern with dry-run on permitted mismatch causes indented output
* bump-my-version version: 0.20.2
* Python version: 3.10.13
* Operating System: Ubuntu 20.04 LTS

### Description

When a glob pattern is used to match multiple files, and that files without any matched version search pattern are permitted, the dry run output becomes more deeply nested on each new unmatched case.

Sample config:
```

❯ bump-my-version bump major --dry-run --verbose

Starting BumpVersion 0.20.2

Reading configuration

  Reading config file: /home/francis/dev/stac/mlm-extension/pyproject.toml

  Specified version (0.0.0) does not match last tagged version (1.0.0-beta.3)

  Parsing current version '0.0.0'

  Attempting to increment part 'major'

    Values are now: major=1, minor=0, patch=0

  New version will be '1.0.0'

Dry run active, won't touch any files.

[.... skipping a few entries that are rendered correctly ...]

  File CONTRIBUTING.md: replace `https://crim-ca.github.io/mlm-extension/v{current_version}/schema.json` with `https://crim-ca.github.io/mlm-extension/v{new_version}/schema.json`

    File README_DLM_LEGACY.md: replace `https://crim-ca.github.io/mlm-extension/v{current_version}/schema.json` with `https://crim-ca.github.io/mlm-extension/v{new_version}/schema.json`

      File CHANGELOG.md: replace `https://crim-ca.github.io/mlm-extension/v{current_version}/schema.json` with `https://crim-ca.github.io/mlm-extension/v{new_version}/schema.json`

        File README.md: replace `https://crim-ca.github.io/mlm-extension/v{current_version}/schema.json` with `https://crim-ca.github.io/mlm-extension/v{new_version}/schema.json`

          Found 'https://crim\-ca\.github\.io/mlm\-extension/v0\.0\.0/schema\.json' at line 6: https://crim-ca.github.io/mlm-extension/v0.0.0/schema.json

          Would change file README.md:

            *** before README.md

            --- after README.md

            ***************

            *** 3,9 ****

              [![hackmd-github-sync-badge](https://hackmd.io/lekSD_RVRiquNHRloXRzeg/badge)](https://hackmd.io/lekSD_RVRiquNHRloXRzeg?both)

              - **Title:** Machine Learning Model Extension

            ! - **Identifier:** [https://crim-ca.github.io/mlm-extension/v0.0.0/schema.json](https://crim-ca.github.io/mlm-extension/v0.0.0/schema.json)

              - **Field Name Prefix:** mlm

              - **Scope:** Collection, Item, Asset, Links

              - **Extension Maturity Classification:** Proposal

            --- 3,9 ----

              [![hackmd-github-sync-badge](https://hackmd.io/lekSD_RVRiquNHRloXRzeg/badge)](https://hackmd.io/lekSD_RVRiquNHRloXRzeg?both)

              - **Title:** Machine Learning Model Extension

            ! - **Identifier:** [https://crim-ca.github.io/mlm-extension/v1.0.0/schema.json](https://crim-ca.github.io/mlm-extension/v1.0.0/schema.json)

              - **Field Name Prefix:** mlm

              - **Scope:** Collection, Item, Asset, Links

              - **Extension Maturity Classification:** Proposal

        File README_STAC_MODEL.md: replace `https://crim-ca.github.io/mlm-extension/v{current_version}/schema.json` with `https://crim-ca.github.io/mlm-extension/v{new_version}/schema.json`

          File best-practices.md: replace `https://crim-ca.github.io/mlm-extension/v{current_version}/schema.json` with `https://crim-ca.github.io/mlm-extension/v{new_version}/schema.json`

            Found 'https://crim\-ca\.github\.io/mlm\-extension/v0\.0\.0/schema\.json' at line 148: https://crim-ca.github.io/mlm-extension/v0.0.0/schema.json

            Would change file best-practices.md:

              *** before best-practices.md

              --- after best-practices.md

              ***************

              *** 145,151 ****

                {

                  "id": "stac-item-model",

                  "stac_extensions": [

              !     "https://crim-ca.github.io/mlm-extension/v0.0.0/schema.json",

                    "https://stac-extensions.github.io/ml-aoi/v0.2.0/schema.json"

                  ],

                  "assets": {

              --- 145,151 ----

                {

                  "id": "stac-item-model",

                  "stac_extensions": [

              !     "https://crim-ca.github.io/mlm-extension/v1.0.0/schema.json",

                    "https://stac-extensions.github.io/ml-aoi/v0.2.0/schema.json"

                  ],

                  "assets": {

              ***************

              *** 216,222 ****

                ```json

                {

                  "stac_extensions": [

              !     "https://crim-ca.github.io/mlm-extension/v0.0.0/schema.json",

                    "https://stac-extensions.github.io/file/v2.1.0/schema.json"

                  ],

                  "assets": {

              --- 216,222 ----

                ```json

                {

                  "stac_extensions": [

              !     "https://crim-ca.github.io/mlm-extension/v1.0.0/schema.json",

                    "https://stac-extensions.github.io/file/v2.1.0/schema.json"

                  ],

                  "assets": {

          File docker/README.md: replace `https://crim-ca.github.io/mlm-extension/v{current_version}/schema.json` with `https://crim-ca.github.io/mlm-extension/v{new_version}/schema.json`

            File tests/test_schema.py: replace `https://crim-ca.github.io/mlm-extension/v{current_version}/schema.json` with `https://crim-ca.github.io/mlm-extension/v{new_version}/schema.json`

              File tests/conftest.py: replace `https://crim-ca.github.io/mlm-extension/v{current_version}/schema.json` with `https://crim-ca.github.io/mlm-extension/v{new_version}/schema.json`

                File stac_model/__init__.py: replace `https://crim-ca.github.io/mlm-extension/v{current_version}/schema.json` with `https://crim-ca.github.io/mlm-extension/v{new_version}/schema.json`

                  File stac_model/schema.py: replace `https://crim-ca.github.io/mlm-extension/v{current_version}/schema.json` with `https://crim-ca.github.io/mlm-extension/v{new_version}/schema.json`

                    Found 'https://crim\-ca\.github\.io/mlm\-extension/v0\.0\.0/schema\.json' at line 40: https://crim-ca.github.io/mlm-extension/v0.0.0/schema.json

                    Would change file stac_model/schema.py:

                      *** before stac_model/schema.py

                      --- after stac_model/schema.py

                      ***************

                      *** 37,43 ****

                        )

                        SchemaName = Literal["mlm"]

                      ! SCHEMA_URI: str = "https://crim-ca.github.io/mlm-extension/v0.0.0/schema.json"

                        PREFIX = f"{get_args(SchemaName)[0]}:"

                      --- 37,43 ----

                        )

                        SchemaName = Literal["mlm"]

                      ! SCHEMA_URI: str = "https://crim-ca.github.io/mlm-extension/v1.0.0/schema.json"

                        PREFIX = f"{get_args(SchemaName)[0]}:"

                  File stac_model/runtime.py: replace `https://crim-ca.github.io/mlm-extension/v{current_version}/schema.json` with `https://crim-ca.github.io/mlm-extension/v{new_version}/schema.json`

                    File stac_model/__main__.py: replace `https://crim-ca.github.io/mlm-extension/v{current_version}/schema.json` with `https://crim-ca.github.io/mlm-extension/v{new_version}/schema.json`

                      File stac_model/input.py: replace `https://crim-ca.github.io/mlm-extension/v{current_version}/schema.json` with `https://crim-ca.github.io/mlm-extension/v{new_version}/schema.json`

                        File stac_model/base.py: replace `https://crim-ca.github.io/mlm-extension/v{current_version}/schema.json` with `https://crim-ca.github.io/mlm-extension/v{new_version}/schema.json`

                          File stac_model/examples.py: replace `https://crim-ca.github.io/mlm-extension/v{current_version}/schema.json` with `https://crim-ca.github.io/mlm-extension/v{new_version}/schema.json`

                            File stac_model/output.py: replace `https://crim-ca.github.io/mlm-extension/v{current_version}/schema.json` with `https://crim-ca.github.io/mlm-extension/v{new_version}/schema.json`

                              Processing config file: /home/francis/dev/stac/mlm-extension/pyproject.toml

                                Found '0\.0\.0' at line 1: 0.0.0

                                Would change file /home/francis/dev/stac/mlm-extension/pyproject.toml:tool.bumpversion.current_version:

                                  *** before /home/francis/dev/stac/mlm-extension/pyproject.toml:tool.bumpversion.current_version

                                  --- after /home/francis/dev/stac/mlm-extension/pyproject.toml:tool.bumpversion.current_version

                                  ***************

                                  *** 1 ****

                                  ! 0.0.0

                                  --- 1 ----

                                  ! 1.0.0

                              Would prepare Git commit

                                Would add changes in file 'README_STAC_MODEL.md' to Git

                                Would add changes in file 'stac_model/base.py' to Git

                                Would add changes in file 'examples/item_raster_bands.json' to Git

                                Would add changes in file 'best-practices.md' to Git

                                Would add changes in file 'examples/collection.json' to Git

                                Would add changes in file 'tests/test_schema.py' to Git

                                Would add changes in file 'json-schema/schema.json' to Git

                                Would add changes in file 'docker/README.md' to Git

                                Would add changes in file 'CHANGELOG.md' to Git

                                Would add changes in file 'tests/conftest.py' to Git

                                Would add changes in file 'README_DLM_LEGACY.md' to Git

                                Would add changes in file 'examples/item_multi_io.json' to Git

                                Would add changes in file 'package.json' to Git

                                Would add changes in file 'stac_model/schema.py' to Git

                                Would add changes in file 'CONTRIBUTING.md' to Git

                                Would add changes in file 'stac_model/output.py' to Git

                                Would add changes in file 'stac_model/__init__.py' to Git

                                Would add changes in file 'examples/item_eo_bands.json' to Git

                                Would add changes in file 'stac_model/input.py' to Git

                                Would add changes in file '/home/francis/dev/stac/mlm-extension/pyproject.toml' to Git

                                Would add changes in file 'stac_model/runtime.py' to Git

                                Would add changes in file 'stac_model/__main__.py' to Git

                                Would add changes in file 'README.md' to Git

                                Would add changes in file 'stac_model/examples.py' to Git

                                Would add changes in file 'examples/item_basic.json' to Git

                                Would commit to Git with message 'Bump version: 0.0.0 → 1.0.0'

                              Would tag 'v1.0.0' with message 'Bump version: 0.0.0 → 1.0.0' in Git and not signing

                              Done.
```
