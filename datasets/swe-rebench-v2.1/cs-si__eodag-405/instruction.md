finalize_s2_safe_product: Fails when missing manifest.safe
When downloading some products on `earth_search`, I have a problem when converting the product format to `.SAFE`:
![2022-02-22_14h47_27](https://user-images.githubusercontent.com/67311115/155145249-38c42542-b9bd-4888-9573-2f7d1cc24c6d.png)
![2022-02-22_14h48_44](https://user-images.githubusercontent.com/67311115/155145285-a0e12781-4c2d-442b-8910-48ddae12dd7a.png)

It seems some L2A products are arriving without the `manifest.safe` file 😓


Environment:

    Python version: Python 3.7.12
    EODAG version: eodag (Earth Observation Data Access Gateway): version 2.3.4

### Additional contract requirements

- When a product being built into `.SAFE` format does not contain a `manifest.safe` file, the SAFE build must report the missing manifest as a `FileNotFoundError`. In particular, `AwsDownload.check_manifest_file_list` must raise `FileNotFoundError`, and `AwsDownload.finalize_s2_safe_product` must raise a `DownloadError` whose message names the missing `manifest.safe`.
