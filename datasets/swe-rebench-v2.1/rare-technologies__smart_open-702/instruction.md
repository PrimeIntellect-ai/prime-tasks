Allow specifying metadata for azure uploads
#### Problem description

I would like to upload an Azure blob with metadata. This is currently possible with s3 and gcs:

```py
metadata = {"name": "bla"}
bucket = "test"
key = "test"
open(
    f"s3://{bucket}/{key}",
    "wb",
    transport_params={
        "client_kwargs": {"S3.Client.create_multipart_upload": {"Metadata": metadata},
    },
)
open(
    f"gs://{bucket}/{key}",
    "wb",
    transport_params={
        "blob_properties": {"metadata": metadata},
    },
)
```

For Azure, `smart_open` only has the possibility of passing a custom [`BlobClient`](https://docs.microsoft.com/en-us/python/api/azure-storage-blob/azure.storage.blob.blobclient?view=azure-python) but it looks like metadata needs to be [explicitly passed](https://github.com/Azure/azure-sdk-for-python/blob/azure-storage-blob_12.12.0/sdk/storage/azure-storage-blob/azure/storage/blob/_blob_client.py#L2631) to `BlobClient.commit_block_list`.

I suggest introducing `blob_kwargs`:
```py
open(
    f"azure://{container}/{path}",
    "wb",
    transport_params={
        "blob_kwargs": {"metadata": metadata},
    },
)
```

#### Steps/code to reproduce the problem

N/A

#### Versions

Please provide the output of:

```pycon
>>> import platform, sys, smart_open
>>> print(platform.platform())
>>> print("Python", sys.version)
>>> print("smart_open", smart_open.__version__)
macOS-10.15.7-x86_64-i386-64bit
Python 3.8.10 (default, Sep  1 2021, 10:14:33)
[Clang 12.0.0 (clang-1200.0.32.29)]
smart_open 6.0.0
```

#### Checklist

Before you create the issue, please make sure you have:

- [x] Described the problem clearly
- [x] Provided a minimal reproducible example, including any required data
- [x] Provided the version numbers of the relevant software
