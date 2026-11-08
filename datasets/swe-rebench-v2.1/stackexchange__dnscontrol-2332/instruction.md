get-zones from BIND produces invalid DS records
I have a zone file containing a DS record for a subdomain, like

```
geo		IN DS	14480 13 2 BB1C4B615CDED2B34347CF23710471934D972F1E34F53B54ED8D5F786202C73B
```

When I use `dnscontrol get-zones --format=js bind BIND domain.com` to convert this to js format, I get a DS record of the form:

```
DS('geo', '14480 13 2 BB1C4B615CDED2B34347CF23710471934D972F1E34F53B54ED8D5F786202C73B'),
 ```

but this is invalid syntax - should be separate parameters, not one string.

Despite this, preview works OK after fixing the js by hand.
