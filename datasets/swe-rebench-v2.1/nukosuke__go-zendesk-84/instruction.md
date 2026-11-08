Add support for group
https://developer.zendesk.com/rest_api/docs/support/groups

- [x] Create
- [x] Read
- [x] Update
- [x] Delete

### Additional contract requirements

- Expose `Client.UpdateGroup(groupID int64, group Group) (Group, error)` to update the specified group and return the updated group or an error.
- Expose `Client.DeleteGroup(groupID int64) error` to delete the specified group and report request failures.
