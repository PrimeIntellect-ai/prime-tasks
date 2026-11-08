S3 file transfer strategy upload/download file path bug
### Environment

- **Covalent version**: 0.198.0
- **Python version**: 3.8.13
- **Operating system**: MacOS


### What is happening?

The upload "to file path" and the download "from file path" in the file transfer with the S3 strategy is broken.

When it comes to downloading, the presence of a backslash because the "from file path" (/train.csv) is not decomposed properly from the `s3://covalent-batch-job-resources/train.csv`. this gives the following error:

```
botocore.exceptions.ClientError: An error occurred (404) when calling the HeadObject operation: Not Found
```

When it comes to uploading, the presence of a backslash, first creates a directory in the s3 before uploading the file.

### How can we reproduce the issue?

Start by uploading the test/train csv files in the s3 bucket and creating a csv file test_v2 locally in datasets folder.

```
import covalent as ct
import pandas as pd

remote_train_file = ct.fs.File('s3://covalent-batch-job-resources/train.csv')
remote_test_file = ct.fs.File('s3://covalent-batch-job-resources/test.csv')
local_train_file = ct.fs.File('/home/user/datasets/train.csv')
local_test_file = ct.fs.File('/home/user/datasets/test.csv')

local_test_file_v2 = ct.fs.File('/home/user/datasets/test_v2.csv')
remote_test_file_v2 = ct.fs.File('s3://covalent-batch-job-resources/test_v2.csv')

strategy = ct.fs_strategies.S3(
    credentials='/home/user/.aws/credentials',
    profile='default',
    region_name = 'us-east-1')

@ct.electron(
    files=[
        ct.fs.FileTransfer(remote_train_file, local_train_file, strategy=strategy, order=ct.fs.Order.BEFORE),
        ct.fs.FileTransfer(remote_test_file, local_test_file, strategy=strategy, order=ct.fs.Order.BEFORE),
        ct.fs.FileTransfer(local_test_file_v2, remote_test_file_v2, strategy=strategy, order=ct.fs.Order.AFTER)
    ]
)
def fetch_and_validate_data(files=[]):
    _, local_train = files[0]
    _, local_test = files[1]
    train = pd.read_csv(local_train, parse_dates=['date'])
    test = pd.read_csv(local_test, parse_dates=['date'])
    return train, test

@ct.lattice
def compare_models():
    # Fetch and validate source data
    train, test = fetch_and_validate_data()
    return train, test

dispatch_id = ct.dispatch(compare_models)()
```

Check the local file directory and the s3 buckets after running this code as well as the covalent logs to see all the relevant issues mentioned above.

### What should happen?

When the code is working properly, the test and train csv files will be downloaded without any errors and the test_v2 file will be uploaded in the appropriate directory.

### Any suggestions?

[HIDDEN]

### Additional contract requirements

- A remote S3 path with a leading slash in its object path must still identify and download the corresponding object within its bucket.
- Uploads must target the intended S3 object path without creating an unintended path with a leading separator.
