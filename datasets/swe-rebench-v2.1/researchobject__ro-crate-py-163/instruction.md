hasPart property on root dataset is assumed to be an array
Loading this dataset causes an error as the hasPart value is not an array but the code assumes it will be :

```json
{
    "@id": "./",
    "@type": "Dataset",
    "hasPart":  {"@id": "spam/foo.txt"}
},
{
    "@id": "spam/foo.txt",
    "@type": "File"
}
```

This line is the culprit: https://github.com/ResearchObject/ro-crate-py/blob/dc3f75b0d0390dedbf9a830b6325b76dba468f1f/rocrate/rocrate.py#L145C1-L146C1

 [HIDDEN]

I added this to my copy  make it work but not sure if you have a general purpose way of doing this in this library:

        [HIDDEN]

### Additional contract requirements

- When loading a crate, accept a root dataset whose `hasPart` value is a single entity object and handle that object as one part.
