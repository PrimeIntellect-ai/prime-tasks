[BUG] No way to provide empty response body as return example
**Describe the bug**
When describing an endpoint, there is no way to define an empty response body

**To Reproduce**
```js
Add a docblock with the following content
/**
 * DELETE /api/v1/products/{id}
 * @summary Delete product with specific ID
 * @tags Products
 * @param {number} id.path.required
 * @return 201 - Success Response
 */
```

**Expected behavior**
Produces a swagger response example with an empty body

**Actual behavior**
Produces example response with a `"string"` body. In the case of an empty response body, this section should be empty.
<details>
<summary>Screenshots</summary>
<img width="765" alt="Screen Shot 2021-06-14 at 5 59 45 PM" src="https://user-images.githubusercontent.com/1687902/121965460-0ecccf00-cd3b-11eb-8fb4-220fa44172c6.png">

The following is an example from another Swagger API doc with an empty response:
<img width="799" alt="Screen Shot 2021-06-14 at 6 08 37 PM" src="https://user-images.githubusercontent.com/1687902/121965818-a0d4d780-cd3b-11eb-9ba8-88c47cd1d962.png">
</details>

It's worth noting that if you attempt any of the following comments, the Swagger docs fail to render and display an error:

```js
/**
 * fails to build docs:
 * @return {undefined} 201 - Success Response
 * @return {null} 201 - Success Response
 *
 * displays "string" as body type:
 * @return {void} 201 - Success Response
 * @return 201 - Success Response
 */
```

### Additional contract requirements

- For `@return 200 - success response - application/json`, the response description must be `success response`, and the response must not include a `content` field.
