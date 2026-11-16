[HIDDEN]
The ValidationErrors type already implements Serialize, presumably to allow sending the error as json in an API. It would be helpful to allow implement Deserialize to read those errors back out on the client side in frontend frameworks like Leptos

### Additional contract requirements

- A `ValidationErrors` value must be deserializable from its existing serialized representation into an equivalent value, including when it contains nested error kinds.
