Append protocol to front of x-application-id
For the `x-application-id`, append the protocol along with the domain.

```js
// Old
{
  headers: {
    "x-application-id": "com.myapp.example"
  }
}

// New
{
  headers: {
    "x-application-id": "https://com.myapp.example"
  }
}
```
