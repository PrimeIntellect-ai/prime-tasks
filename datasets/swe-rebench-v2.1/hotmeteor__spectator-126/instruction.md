application/problem+json giving strange expected/actual comparison
The recent @ethanbray PR #104 made some improvements to `application/problem+json` handling but I still have other probems using it.

```
^ {#5230
  +"exception": "Spectator\Exceptions\ResponseValidationException"
  +"message": """
    Response did not match any specified content type.\n
    \n
      Expected: application/json\n
      Actual: DNE\n
    \n
      ---
    """
  +"specErrors": []
}
```

Test:

```php
it('returns a 404 for invalid record', function () {
    $non_existent_uuid = '53d4faeb-e046-4ab1-91ff-6b6e35c4c052';
    $this
        ->withHeaders(['Authorization' => 'Bearer '.$this->api_key])
        ->getJson(sprintf('/orders/%s', $non_existent_uuid))
        ->dump()
        ->assertValidResponse(404);
});
```

OpenAPI:

```yaml

  '/orders/{order}':
    parameters:
      - in: path
        name: order
        required: true
        schema:
          type: string
          format: uuid
          example: 53f7bd7b-2ee2-4be4-a15b-e09c76a150f9
    get:
      operationId: get-orders-uuid
      summary: Get Order
      description: 'Orders are made by organizations to fund tree planting, and when trees are planted those orders will be marked as fullfilled. Orders may be partially fulfilled, and it is up to you if you wish to import those. Make sure to deduplicate the trees if you do.'
      tags:
        - Order
      responses:
        '200':
          description: OK
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/Order'
        '401':
          description: Unauthorized
          content:
            application/problem+json:
              schema:
                $ref: '#/components/schemas/Generic_Problem'
        '404':
          description: Organization not found.
          content:
            application/problem+json:
              schema:
                $ref: '#/components/schemas/Generic_Problem'
```

I tried switching the $ref to just a `type: object` but thats not making any difference.

_Originally posted by @philsturgeon in https://github.com/hotmeteor/spectator/issues/103#issuecomment-1196498686_
