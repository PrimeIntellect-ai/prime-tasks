How to remove unused keys from the JSON?
When I change code
``` <Trans>Profile</Trans>```
to
``` <Trans>Profil</Trans>```
I will receive two keys in translation.json
```
{
  "Profile": "",
  "Profil": ""
}
```

I want to have only fresh list of keys in translation file.
Can you please tell is there any way to update config to handle that?

### Additional contract requirements

The `discardOldKeys` plugin option removes translation keys that are not extracted when set to `true`. Values for extracted keys that already have translations are retained. When this option is not enabled, existing unextracted keys and their translations remain in the output while newly extracted keys are added.
