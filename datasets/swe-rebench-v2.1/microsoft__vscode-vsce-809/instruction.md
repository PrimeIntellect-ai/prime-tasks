Manifest still requires `activationEvents`, but shouldn't anymore
The VS Code 1.74 release added [Implicit Activation Events](https://code.visualstudio.com/updates/v1_74#_implicit-activation-events-for-declared-extension-contributions), but `vsce` doesn't seems to have been updated to support that yet.

I just tried to publish an update for one of my extensions, which now doesn't have any `activationEvents` anymore, and even `vsce ls` doesn't work

```shell
 ERROR  Manifest needs the 'activationEvents' property, given it has a 'main' property.
```

BTW, `vsce` is updated to `2.16`, as described https://code.visualstudio.com/updates/v1_74#_renaming-of-vsce-to-vscodevsce

Thank you

### Additional contract requirements

- A `contributes.commands` entry enables implicit activation events for VS Code versions 1.74 and later.
