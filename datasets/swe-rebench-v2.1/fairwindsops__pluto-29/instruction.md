Error message shows wrong flag
```
└─ ./pluto detect-helm --helm-version 2
APIVersions were found, but none were deprecated. Try --show-non-deprecated.
```

### Additional contract requirements

- The corrected message must be exactly: `APIVersions were found, but none were deprecated. Try --show-all.`
