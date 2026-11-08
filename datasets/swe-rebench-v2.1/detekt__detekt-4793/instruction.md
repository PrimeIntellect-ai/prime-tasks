Show a warning message when ussing comma separate strings instead of lists
If someone has an old configuration can still be using things like this:

```yaml
    methodNames: 'toString,hashCode,equals,finalize'
```
instead of
```yaml
    methodNames: ['toString', 'hashCode', 'equals', 'finalize']
```

An example can be found here: https://github.com/mozilla-mobile/android-components/blob/6f60a8a44b9fa24b62c223130d39bc5ea8095ae6/config/detekt.yml#L129

The support for both types was introduced at 1.8.0. The reason to support both was purely retrocompatibility but keeping this retrocompatibility makes more difficult to maintain our code (Example: https://github.com/detekt/detekt/issues/3501#issuecomment-1015324916)

I think that we should add a warning for the users that still use the old comma separated format so in the future we can remove that retrocompatibility.

### Additional contract requirements

When a configuration property that expects a YAML list is supplied as a legacy comma-separated String, the validation reports a notification whose message is exactly:

    Property '<propertyPath>' should be a YAML array instead of a comma-separated String.

where `<propertyPath>` is the full path of the offending property (for example `style>MagicNumber>ignoreNumbers`).

The notification severity follows the `config.warningsAsErrors` setting: it is an error when `warningsAsErrors` is `true` and a warning when it is `false`.
