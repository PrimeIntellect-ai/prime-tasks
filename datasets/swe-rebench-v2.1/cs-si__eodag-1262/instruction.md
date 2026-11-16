USGS Search by ID lists many products instead of just the matching one
When I try to use `eodag.search` method with setting the `id` parameter, it lists many (millions) of products instead of just the product matching the ID, and the only work around I found is to iterate through all the pages and look for the matching product manually, but it takes a lot of time to load all these results.

**Code To Reproduce**
```py
from eodag import EODataAccessGateway
from eodag.utils.logging import setup_logging
setup_logging(verbose=3)
dag = EODataAccessGateway()
dag.search(id="LC09_L2SP_016035_20240605_20240611_02_T1", provider="usgs", productType="LANDSAT_C2L2")
```

**Output**
```
2024-07-08 22:46:20,166 eodag.config                     [DEBUG   ] (tid=140046769037376) Loading configuration from /home/hamed/Desktop/playground/env/lib/python3.11/site-packages/eodag/resources/providers.yml
2024-07-08 22:46:21,432 eodag.config                     [INFO    ] (tid=140046769037376) Loading user configuration from: /home/hamed/.config/eodag/eodag.yml
2024-07-08 22:46:21,452 eodag.core                       [INFO    ] (tid=140046769037376) aws_eos: provider needing auth for search has been pruned because no crendentials could be found
2024-07-08 22:46:21,452 eodag.core                       [INFO    ] (tid=140046769037376) meteoblue: provider needing auth for search has been pruned because no crendentials could be found
2024-07-08 22:46:21,452 eodag.core                       [INFO    ] (tid=140046769037376) hydroweb_next: provider needing auth for search has been pruned because no crendentials could be found
2024-07-08 22:46:21,452 eodag.core                       [INFO    ] (tid=140046769037376) wekeo: provider needing auth for search has been pruned because no crendentials could be found
2024-07-08 22:46:21,452 eodag.core                       [INFO    ] (tid=140046769037376) creodias_s3: provider needing auth for search has been pruned because no crendentials could be found
2024-07-08 22:46:21,460 eodag.core                       [DEBUG   ] (tid=140046769037376) Opening product types index in /home/hamed/.config/eodag/.index
2024-07-08 22:46:21,473 eodag.core                       [INFO    ] (tid=140046769037376) Locations configuration loaded from /home/hamed/.config/eodag/locations.yml
2024-07-08 22:46:21,474 eodag.core                       [INFO    ] (tid=140046769037376) Searching product type 'LANDSAT_C2L2' on provider: usgs
2024-07-08 22:46:21,474 eodag.core                       [INFO    ] (tid=140046769037376) Searching product with id 'LC09_L2SP_016035_20240605_20240611_02_T1' on provider: usgs
2024-07-08 22:46:21,474 eodag.core                       [DEBUG   ] (tid=140046769037376) Using plugin class for search: UsgsApi
2024-07-08 22:46:22,680 eodag.apis.usgs                  [INFO    ] (tid=140046769037376) Sending search request for landsat_ot_c2_l2 with {'start_date': None, 'end_date': None, 'll': None, 'ur': None, 'max_results': 2, 'starting_number': 1}
2024-07-08 22:46:24,927 eodag.apis.usgs                  [DEBUG   ] (tid=140046769037376) Adapting 2 plugin results to eodag product representation
2024-07-08 22:46:27,095 eodag.core                       [INFO    ] (tid=140046769037376) Found 3127730 result(s) on provider 'usgs'
2024-07-08 22:46:27,095 eodag.core                       [INFO    ] (tid=140046769037376) Several products found for this id ([EOProduct(id=LC09_L2SP_016001_20240707_20240708_02_T1, provider=usgs), EOProduct(id=LC09_L2SP_016002_20240707_20240708_02_T1, provider=usgs)]). You may try searching using more selective criteria.
```

**Environment:**
 - Python version: `3.11.2`
 - EODAG version: `2.12.1`

**Additional context**
Here is the actual product that corresponds to the "ID" in the search:
https://earthexplorer.usgs.gov/scene/metadata/full/5e83d14f2fc39685/LC90160352024157LGN00/
