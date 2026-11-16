Always include `downloadCount30Days` key in api/packages/<pkg>/score .
If there is no download count yet we can give it value `null`.

### Additional contract requirements

When a 30-day download count is available for a package, the score response includes that count.
