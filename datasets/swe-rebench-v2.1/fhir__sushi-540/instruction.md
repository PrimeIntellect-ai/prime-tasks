Extension names are conflicting
It seems like it can cause issues in SUSHI when two extensions start with the same string of characters. As an example, something like this:
```
Extension:      FastqPaired
Id:             FastqPaired
Title:          "Fastq Paired"
Description:    "Represents paired read data generated from sequencing performed on this specimen."

* extension contains
    forward 1..1 MS and
    forwardByteSize 0..1 and
    forwardChecksum 0..1 and
    reverse 1..1 MS and
    reverseByteSize 0..1 and
    reverseChecksum 0..1

* extension[forward] ^short = "Forward read file location"
* extension[forward].value[x] only string

* extension[forwardByteSize] ^short = "Forward file size in bytes"
* extension[forwardByteSize].value[x] only decimal

* extension[forwardChecksum] ^short = "Forward file MD5 checksum"
* extension[forwardChecksum].value[x] only string

* extension[reverse] ^short = "Reverse read file location"
* extension[reverse].value[x] only string

* extension[reverseByteSize] ^short = "Reverse file size in bytes"
* extension[reverseByteSize].value[x] only decimal

* extension[reverseChecksum] ^short = "Reverse file MD5 checksum"
* extension[reverseChecksum].value[x] only string
```
does not seem to work, because the `reverse` and `reverseByteSize` extensions conflict, and SUSHI gets them confused with each other. If you rename the byte size extensions as follows, things work:
```
Id:             FastqPaired
Title:          "Fastq Paired"
Description:    "Represents paired read data generated from sequencing performed on this specimen."

* extension contains
    forward 1..1 MS and
    byteSizeForward 0..1 and
    forwardChecksum 0..1 and
    reverse 1..1 MS and
    byteSizeReverse 0..1 and
    reverseChecksum 0..1

* extension[forward] ^short = "Forward read file location"
* extension[forward].value[x] only string

* extension[byteSizeForward] ^short = "Forward file size in bytes"
* extension[byteSizeForward].value[x] only decimal

* extension[forwardChecksum] ^short = "Forward file MD5 checksum"
* extension[forwardChecksum].value[x] only string

* extension[reverse] ^short = "Reverse read file location"
* extension[reverse].value[x] only string

* extension[byteSizeReverse] ^short = "Reverse file size in bytes"
* extension[byteSizeReverse].value[x] only decimal

* extension[reverseChecksum] ^short = "Reverse file MD5 checksum"
* extension[reverseChecksum].value[x] only string
```
