Earth Search: Missing ProductPath in some downloaded product
Bug linked to #423.
Sorry to reopen again this issue, but I have encountered new products where it fails 😅
I am recreating a new issue to be more precise.

**Describe the bug**

Some products are missing a ProductPath in their properties, leading to failure to find the manifest file
`FileNotFoundError: No manifest.safe could be found in D:\_EODOWNLOAD\OUTPUT\GRAND_EST\L2A\S2B_MSIL2A_20211229T130249_N0301_R095_T24MUV_20211229T151639`
![2022-03-16_09h17_21](https://user-images.githubusercontent.com/67311115/158546345-4ce55c5e-d57d-4c8e-afff-25029c837625.png)

This comes from the fact that the ProductPath is missing and its url is replaced by the product location in `get_bucket_name_and_prefix` (in `aws.py`). This leads to a wrong name and bucket:

```python
print(
    self.get_bucket_name_and_prefix(
        product, product.properties["productPath"]
    )
)

('v0', '/collections/sentinel-s2-l2a/items/S2A_32TLT_20211016_0_L2A')
```

**Code To Reproduce**
```py
import os
import tempfile

from eodag import EODataAccessGateway, setup_logging
from eodag.config import override_config_from_file

from eodownload import dir_utils
from eodownload.dir_utils import get_data_directory

OUTPUT = r"D:\"

os.environ["EODAG__EARTH_SEARCH__DOWNLOAD__EXTRACT"] = "false"
os.environ["EODAG__EARTH_SEARCH__DOWNLOAD__OUTPUTS_PREFIX"] = OUTPUT
os.environ["EODAG__EARTH_SEARCH__AUTH__CREDENTIALS__AWS_ACCESS_KEY_ID"] = "*****"
os.environ["EODAG__EARTH_SEARCH__AUTH__CREDENTIALS__AWS_SECRET_ACCESS_KEY"] = "*****"
os.environ["EODAG__EARTH_SEARCH__AUTH__CREDENTIALS__AWS_PROFILE"] = "*****"

if __name__ == "__main__":
    setup_logging(2)  # DEBUG level

    with tempfile.TemporaryDirectory() as tmp:
        # Create gateway
        dag = EODataAccessGateway()
        dag.set_preferred_provider("earth_search")

        # Query all
        products = dag.search_all(
            start="2021-12-28",
            end="2021-12-30",
            **{
                "productType": "S2_MSI_L2A",
                "geom": "POINT (-40.30881686219417 -5.018666560087038)"
            }
        )

        # Download all
        dag.download_all(products)
```

```
2022-06-30 15:46:48,821 eodag.config                     [INFO    ] Loading user configuration from: C:\Users\rbraun\.config\eodag\eodag.yml
2022-06-30 15:46:48,830 eodag.config                     [INFO    ] aws_s3_sentinel2_l1c: unknown provider found in user conf, trying to use provided configuration
2022-06-30 15:46:48,830 eodag.config                     [WARNING ] aws_s3_sentinel2_l1c skipped: could not be loaded from user configuration
2022-06-30 15:46:48,965 eodag.core                       [INFO    ] usgs: provider needing auth for search has been pruned because no crendentials could be found
2022-06-30 15:46:48,965 eodag.core                       [INFO    ] aws_eos: provider needing auth for search has been pruned because no crendentials could be found
2022-06-30 15:46:49,114 eodag.core                       [INFO    ] Locations configuration loaded from C:\Users\rbraun\.config\eodag\locations.yml
2022-06-30 15:46:49,763 eodag.core                       [INFO    ] Searching product type 'S2_MSI_L2A' on provider: earth_search
2022-06-30 15:46:49,763 eodag.core                       [INFO    ] Iterate search over multiple pages: page #1
2022-06-30 15:46:49,856 eodag.plugins.search.qssearch    [INFO    ] Sending search request: https://earth-search.aws.element84.com/v0/search
2022-06-30 15:46:50,392 eodag.core                       [INFO    ] Found 1 result(s) on provider 'earth_search'
2022-06-30 15:46:50,392 eodag.core                       [INFO    ] Downloading 1 products
Downloaded products:   0%|          | 0/1 [00:00<?, ?product/s]
0.00B [00:00, ?B/s]
S2B_24MUV_20211229_1_L2A: 0.00B [00:00, ?B/s]2022-06-30 15:46:50,394 eodag.plugins.download.base      [INFO    ] Download url: https://earth-search.aws.element84.com/v0/collections/sentinel-s2-l2a/items/S2B_24MUV_20211229_1_L2A
2022-06-30 15:46:50,394 eodag.plugins.download.aws       [ERROR   ] complementary_url_key productPath is missing in S2B_24MUV_20211229_1_L2A properties
S2B_24MUV_20211229_1_L2A: 100%|██████████| 407M/407M [00:27<00:00, 8.57MB/s]2022-06-30 15:47:22,499 eodag.plugins.download.aws
[ERROR   ] Could not finalize SAFE product from downloaded data
Traceback (most recent call last):
  File "C:\Users\rbraun\Anaconda3\envs\eodownload\lib\site-packages\eodag\plugins\download\aws.py", line 657, in finalize_s2_safe_product
    f"No manifest.safe could be found in {product_path}"
FileNotFoundError: No manifest.safe could be found in D:\_EODOWNLOAD\OUTPUT\GRAND_EST\L2A\S2B_MSIL2A_20211229T130249_N0301_R095_T24MUV_20211229T151639
2022-06-30 15:47:22,500 eodag.plugins.download.base      [WARNING ] A problem occurred during download of product: EOProduct(id=S2B_24MUV_20211229_1_L2A, provider=earth_search). Skipping it
S2B_24MUV_20211229_1_L2A: 100%|██████████| 407M/407M [00:27<00:00, 14.6MB/s]
2022-06-30 15:47:22,503 eodag.plugins.download.base      [INFO    ] [Retry #1, 0/1 D/L] Waiting 87s until next download try (retry every 2' for 20')
```

**Output**
Compete output obtained with maximal verbosity.

**Environment:**
 - Python version: Python 3.7.12
 - EODAG version: eodag (Earth Observation Data Access Gateway): version 2.5.1
