[New Rule] Use keyword-arguments instead of positional arguments for boolean values
## Explanation

Positional boolean arguments are typically hard to understand, because they can represent so many things. Having a keyword-argument gives the reader the keyword name as context.

## Example

```python
import zipfile

# Bad
fp = zipfile.ZipFile("filename", "w", zipfile.ZIP_DEFLATED, False)

# Good
fp = zipfile.ZipFile("filename", "w", zipfile.ZIP_DEFLATED, allowZip64=False)
```

### Additional contract requirements

- The rule for positional boolean arguments is reported with the code `SIM902`.
- `SIM902` does not report calls to `min`, `max`, or `partial`, calls to a `get` method, or calls to setter functions or methods.
