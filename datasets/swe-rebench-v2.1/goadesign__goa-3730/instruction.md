Regression: User-Defined Example for Custom URI Type Is Ignored in v1.20

## Description

We define a custom type `utils.URL`, which is a string with `FormatURI`, as follows:

```go
var URL = dsl.Type("URL", dsl.String, func() {
    dsl.Format(dsl.FormatURI)
})
```

When using this type for an attribute and specifying an explicit example, the example is ignored in Goa v1.20 and replaced by the default example (`https://example.com/foo`). This worked as expected in v1.19.

---

## Steps to Reproduce

1. Define the custom type as above.
2. Use it for an attribute with an explicit example:

   ```go
   Attribute("seller_offer_redirect_url", utils.URL, func() {
       Description("URL to redirect to view the offer in the topi tool")
       Example("http://www.seller.topi.eu/offer/739b63c2-9e58-4964-b38d-4ebb424de242%2Fv1")
   })
   ```
3. Generate the OpenAPI/Swagger spec.

---

## Expected Behavior

The provided example URL should appear in the generated OpenAPI spec.

---

## Actual Behavior

The example in the spec is always `https://example.com/foo`, regardless of the explicit example provided in the design.

---

## Regression

* **v1.19:** The explicit example was correctly shown in the generated spec.
* **v1.20:** The explicit example is ignored and replaced by the default.

---

## Screenshot

![Diff Screenshot](https://github.com/user-attachments/assets/4273ea93-f611-415a-8234-ba8b4f6c4636)

---

## Goa Version

* v1.19 (works)
* v1.20 (broken)

---

## Sample Code

```go
var URL = dsl.Type("URL", dsl.String, func() {
    dsl.Format(dsl.FormatURI)
})

Attribute("seller_offer_redirect_url", utils.URL, func() {
    Description("URL to redirect to view the offer in the topi tool")
    Example("http://www.seller.topi.eu/offer/739b63c2-9e58-4964-b38d-4ebb424de242%2Fv1")
})
```

### Additional contract requirements

The following requirements are part of the public contract and are exercised by the graded tests:

- When an example is generated for a user type (a type defined with `dsl.Type`), the user type's own example must be used if one is defined on the type. In terms of the public API, `(*expr.UserTypeExpr).Example` must return the example defined on the user type's attribute.
- When an example is generated for a user type that carries format validation (for example `dsl.Format(dsl.FormatURI)`), the generated example must satisfy that format instead of being a generic string. In particular, when examples are generated with the deterministic randomizer (`expr.NewDeterministicRandomizer`), a user type with `FormatURI` validation generates the example `https://example.com/foo`.
- When an attribute uses such a user type and specifies an explicit example, that example must be used when generating the attribute's example and must appear in the generated OpenAPI specification.
