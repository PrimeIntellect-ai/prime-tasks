The SCIMMY filter does not support special character in the attribute name
While integrate with the Entra provisioning service, we found that the remove group member with the Entra sample request would trigger invalid filter exception.

The request body is as shown in this link: https://learn.microsoft.com/en-us/entra/identity/app-provisioning/use-scim-to-provision-users-and-groups#update-group-remove-members

The exception is as:
```json
{
    "schemas": [
        "urn:ietf:params:scim:api:messages:2.0:Error"
    ],
    "status": "400",
    "scimType": "invalidFilter",
    "detail": "Unexpected token '$ref eq null and value eq f648f8d5ea4e4cd38e9c' in filter for 'remove' op of operation 1 in PatchOp request body"
}
```

The root cause seems to be the '$ref' as the attribute name of the filter.
