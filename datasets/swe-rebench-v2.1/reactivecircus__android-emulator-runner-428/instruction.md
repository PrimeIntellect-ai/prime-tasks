API-LEVEL does not work with latest version within the latest sdk like (35-ext15)
Google started to release images like `system-images;android-35-ext15;android-wear;arm64-v8a`. Right now in the current version of this Action we can't use it.

We should either add a `suffix` option to keep api-level a number or parse the number in api-level.

Something like
```
 - uses: reactivecircus/android-emulator-runner@v2
        with:
          api-level: "35-ext15"
```
OR
```
 - uses: reactivecircus/android-emulator-runner@v2
        with:
          api-level: "35"
          api-level-sufix: "-ext15"
```

### Additional contract requirements

- The action must accept an `api-level` input value that includes an SDK extension suffix, such as `35-ext15`, without rejecting it as an invalid API level.
- The action must support installing a system image whose API-level token includes an SDK extension suffix, such as `35-ext15`; the system-image API level may be supplied separately from `api-level` through the `system-image-api-level` input.
- If `system-image-api-level` is not supplied, the action must use the `api-level` value for the system image, preserving any SDK extension suffix.
