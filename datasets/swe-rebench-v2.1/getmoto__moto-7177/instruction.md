support list_group_memberships_for_member in identitystore
feature request for list_group_memberships_for_member

Ref: https://docs.getmoto.org/en/latest/docs/services/identitystore.html

### Additional contract requirements

Add a public operation `list_group_memberships_for_member` on the mocked IdentityStore client (the boto3 `identitystore` service). It accepts:

- `IdentityStoreId` (string, required): the identity store to query.
- `MemberId` (dict, required): identifies the member, for example `{"UserId": "<user-id>"}`. Only `UserId` is supported.
- `MaxResults` (integer, required): the maximum number of membership records to return in one call.
- `NextToken` (string, optional): a pagination token from a previous response, used to continue listing.

It returns a dict containing:

- `GroupMemberships`: the group-membership records that involve the specified member, and only that member. Each record contains at least `MembershipId`, `GroupId`, and `MemberId`.
- `NextToken`: present when more results remain, and omitted when the result set is complete.
