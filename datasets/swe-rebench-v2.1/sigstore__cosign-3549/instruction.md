OCI manifest created timestamp wrong with v2.2.0
**Description**

We are using a cosign container inside our pipeline to sign newly build images.
Up until v2.1.1 (public.ecr.aws/bitnami/cosign:2.1.1) this works without problems:
`cosign sign --yes --key cosign.key {{image}}@sha256:{{digest}}`
That creates a new OCI entry inside our IBM Container Registry:
```json
{
  "Id": "sha256:[...]",
  "Parent": "",
  "Comment": "",
  "Created": "2023-10-12T14:52:17.989015938Z",
[...]
  "Size": 251,
  "VirtualSize": 251,
  "RootFS": {
    "Type": "layers",
    "Layers": [
      "sha256:[...]"
    ]
  },
  "ManifestType": "application/vnd.oci.image.manifest.v1+json"
}
```
After updating to v2.2.0 (public.ecr.aws/bitnami/cosign:2.2.0) the **Created** timestamp is totally wrong and leads to this:
```json
{
  "Id": "sha256:[...]",
  "Parent": "",
  "Comment": "",
  "Created": "0001-01-01T00:00:00Z",
 [...]
  "Size": 251,
  "VirtualSize": 251,
  "RootFS": {
    "Type": "layers",
    "Layers": [
      "sha256:[...]"
    ]
  },
  "ManifestType": "application/vnd.oci.image.manifest.v1+json"
}
```

As we have some rules to delete older entries inside our registry these signatures are deleted soon after creation.
Image can be verified with `cosign verify` in both cases. The output does not differ.
This can be reproduced with different images.

**Version**

`public.ecr.aws/bitnami/cosign:2.2.0`

### Additional contract requirements

- In package `pkg/oci/mutate`, provide `AppendSignatures(base oci.Signatures, recordCreationTimestamp bool, sigs ...oci.Signature) (oci.Signatures, error)`. It returns a signatures collection containing the signatures of `base` plus the appended `sigs`. When `recordCreationTimestamp` is true, the resulting collection records the current time as its creation timestamp; when false, the creation timestamp remains the zero value.
- In package `pkg/oci/static`, provide `WithRecordCreationTimestamp(rct bool) Option`. It returns an option for `NewFile` that, when `rct` is true, populates the created timestamp of the resulting file with the current time; when false, the created timestamp remains the zero value.
