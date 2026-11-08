Trigger referring to repeat question has relative ref attribute
#### Software and hardware versions
Last commit in master of Oct 29th, 2020

#### Problem description
If a trigger refers to a question inside a repeat, the `ref` attribute value is relative. Though this is strictly speaking correct in XForms, in pyxform we've so far always used absolute references and could do so in this case too. This would be more consistent. The real problem is that a relative reference doesn't work in Enketo is not so easy to add support for.

#### Steps to reproduce the problem

type | name | label | trigger | calculation
-- | -- | -- | -- | --
begin repeat | rep |   |   |
text | one | Enter text |   |
text | three | Enter text (triggered) | ${one} | concat('d', 'e')
end repeat |   |   |   |

This form doesn't pass ODK Validate (different issue) so run with `--skip_validate`.

The output contains ```<setvalue event="xforms-value-changed" ref=" ../three " value="concat('d', 'e')" />```

Note the inconsistency with the other ref attributes in the same body that are all absolute including the `three` question itself.

#### Desired behavior

The desired output would contain ```<setvalue event="xforms-value-changed" ref=" /data/rep/three " value="concat('d', 'e')" />``` instead.

#### Additional information

Both `ref="/data/rep/three"` attributes in the (desired) output refer to the same node (in the current repeat instance). They are binding expressions. As far as I can tell they have the exact same meaning in XForms.

### Additional contract requirements

- Generated `<setvalue>` elements must not have padding spaces around the XPath in the `ref` attribute.
