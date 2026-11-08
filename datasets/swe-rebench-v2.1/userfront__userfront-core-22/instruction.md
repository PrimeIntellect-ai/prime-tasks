Pass tenantId to iframe
Need to pass the tenantId to the iframe so that it can construct the URL on requests.  Propose doing this as a property of the `message` sent by the parent:

```js
{
  type: "refresh",
  tenantId: "abcd1234"
}
```
