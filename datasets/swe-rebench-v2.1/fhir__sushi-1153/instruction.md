SUSHI does not properly encode menu item names
Including something like this in `sushi-config.yaml`'s `menu` causes problems:
```yaml
Specification:
    Measures: measures.html
    Plans & Interventions: interventions.html
    Conformance & Workflow: workflow.html
```
The problem is that `&` needs to be encoded to `&amp;` in the XML menu.

If we fix SUSHI to do this encoding, we need to be careful not to double-encode items that were already encoded by the user.

See: https://chat.fhir.org/#narrow/stream/215610-shorthand/topic/Menu.20issue/near/285404188

### Additional contract requirements

- When a menu item name already contains one or more of `&quot;`, `&apos;`, `&lt;`, `&gt;`, or `&amp;`, log one warning for that item. Do not log this warning for names containing only unescaped special characters.
- In menu item names, also encode `<` as `&lt;`, `>` as `&gt;`, `"` as `&quot;`, and `'` as `&apos;` in the XML.
