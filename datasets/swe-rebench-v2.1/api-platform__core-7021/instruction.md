APIP4, Hydra prefix , error response
**API Platform version(s) affected**: 4.1

**Description**

API4 remove the hydra prefix, and we really need to be BC complient.
So I added
```yaml
api_platform:
    serializer:
        hydra_prefix: true
```

In my symfony application configuration

The GET endpoints looks fine, but when something goes wrong, the response has duplicated content. For exemple, when I faces a 422:
```json
{
  "@context": "\/app_dev.php\/api\/contexts\/ConstraintViolation",
  "@id": "\/app_dev.php\/api\/validation_errors\/c1051bb4-d103-4f74-8988-acbcafc7fdc3",
  "@type": "ConstraintViolation",
  "status": 422,
  "violations": [
    {
      "propertyPath": "project",
      "message": "This value should not be blank.",
      "code": "c1051bb4-d103-4f74-8988-acbcafc7fdc3"
    }
  ],
  "detail": "project: This value should not be blank.",
  "description": "project: This value should not be blank.",
  "type": "\/validation_errors\/c1051bb4-d103-4f74-8988-acbcafc7fdc3",
  "title": "An error occurred",
  "hydra:description": "project: This value should not be blank.",
  "hydra:title": "An error occurred"
}
```

See
* `detail` vs `description` vs `hydra:description`
* `title` vs `hydra:title`
