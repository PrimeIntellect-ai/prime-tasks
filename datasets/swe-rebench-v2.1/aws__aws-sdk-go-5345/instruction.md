S3 `Downloader` potentially downloads corrupted object when the it is split into multiple parts
### Describe the bug

* We have a system that's constantly updating an object stored in an S3 bucket
* The object is downloaded by multiple clients concurrently
* In our particular case, the stored object is gzipped but the issue applies to all sorts of files
* When the object grows to over 5MB (which causes the downloader to download the object in multiple parts), we encountered an issue where the second part is downloaded from a different version of the object, therefore corrupting the download


### Expected Behavior

The latest version of the object is downloaded

### Current Behavior

An error is encountered from time to time, e.g.,

```
2023/09/12 14:54:39
panic: flate: corrupt input before offset 1089400

goroutine 1 [running]:
main.fetch(0x14000146640)
        /Users/kevinqiu/src/tmp/s3bugrepro/main.go:36 +0x2a0
main.main()
        /Users/kevinqiu/src/tmp/s3bugrepro/main.go:57 +0xd0
exit status 2
```

or
```
panic: gzip: invalid checksum
```

With logging turned on, it's observed that when a later part is being downloaded and when the object is updated before that, the later chunk from a different version is downloaded and therefore corrupting the output.



### Reproduction Steps

Minimally reproducible example:
### Producer
The producer is simply a script that uploads a gzipped file (greater than 5MB) to a bucket constantly
```bash
#! /bin/bash
while true; do
    files="0 1 2 3"
    for i in $files; do
        aws s3 cp $i s3://$BUCKET/TEST
        sleep 1
    done
done
```

### Consumer
```go
package main

import (
	"bytes"
	"compress/gzip"
	"fmt"
	"io"
	"time"

	"github.com/aws/aws-sdk-go/aws"
	"github.com/aws/aws-sdk-go/aws/session"
	"github.com/aws/aws-sdk-go/service/s3"
	"github.com/aws/aws-sdk-go/service/s3/s3manager"
)

func fetch(downloader *s3manager.Downloader) {
	buff := &aws.WriteAtBuffer{}
	goi := &s3.GetObjectInput{
		Bucket: aws.String("BUCKET"),  // replace with the real bucket name
		Key:    aws.String("TEST"),
	}
	_, err := downloader.Download(buff, goi)
	if err != nil {
		panic(err)
	}

	b := buff.Bytes()
	br := bytes.NewReader(b)
	gzr, err := gzip.NewReader(br)
	if err != nil {
		panic(err)
	}

	uzb, err := io.ReadAll(gzr)
	if err != nil && err != io.EOF {
		panic(err)
	}

	fmt.Printf("Size=%v\n", len(uzb))
}

func main() {
	s, err := session.NewSession(&aws.Config{
		Region:   aws.String("us-east-1"),
		LogLevel: aws.LogLevel(aws.LogDebugWithHTTPBody),
	})

	if err != nil {
		panic(err)
	}

	downloader := s3manager.NewDownloader(s, func(downloader *s3manager.Downloader) {
		downloader.PartSize = 1024 * 512  // set to a small chunk size so the problem can be reproduced sooner
	})

	for {
		fetch(downloader)
		time.Sleep(2 * time.Second)
	}
}
```

### Possible Solution

[HIDDEN]


### Additional Information/Context

_No response_

### SDK version used

1.44

### Environment details (Version of Go (`go version`)? OS name and version, etc.)

1.20

### Additional contract requirements

- A multipart download must return bytes from one consistent object version, or return an error rather than returning a mixture of versions.
- If a ranged request receives a precondition failure because the object changed during a multipart download, the download must return an error whose message contains `PreconditionFailed`.
- When the caller supplies a VersionId, requests that retrieve object data must target that version.
