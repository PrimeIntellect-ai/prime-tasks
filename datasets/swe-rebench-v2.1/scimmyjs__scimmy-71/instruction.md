No way to modify `totalResults` and `itemsPerPage` in the `ListResponse` result
I am using the `ListResponse` class to return a paginated response for `User` resources, which are retrieved from my application's database.
Is there a way to modify the `itemsPerPage` and `totalResults` properties of the `ListResponse`?
I am passing the `itemsPerPage` value from the `params` to the `ListResponse` to my SQL query which should correctly return the specified number of records from the database but the `totalResults` is meant to be a number showing count of the total records which satisfy the given conditions.

In my case the `ListResponse` returns the records which my database query returns.

```javascript

new ListResponse(
  resultRows,
  {
    sortBy: sortBy,
    sortOrder: sortOrder,
    startIndex: pgStart,
    itemsPerPage: limit,
  }
)

// response
{
  schemas: [ 'urn:ietf:params:scim:api:messages:2.0:ListResponse' ],
  totalResults: 1,
  Resources: [
    {
      id: 1,
      email: 'some@user.com',
    }
  ],
  startIndex: 1,
  itemsPerPage: 20
}

```

here the `totalResults` is showing the length of the `Resources` property of the `ListResponse`, but I am not able to find a way to change it to the calculated value of 8.
And the `itemsPerPage` value in the result is always 20, I provided the `itemsPerPage` param value as `1`.

### Additional contract requirements

When constructing an outbound ListResponse, the optional `params.totalResults` value supplies the total count independently of the resources returned in `Resources`. If this value is omitted, the total defaults to the resources array length. The supplied `params.itemsPerPage` value is reflected in the response.
