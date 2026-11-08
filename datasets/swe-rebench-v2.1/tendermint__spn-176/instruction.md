account: allow to delete a coordinator
This message is to delete a coordinator account

```go
starport s message delete-coordinator address --module account
```

### Additional contract requirements

Expose the deletion transaction as `types.MsgDeleteCoordinator` with an `Address` field and a `ValidateBasic()` method. Expose its handler as `MsgServer.DeleteCoordinator(context.Context, *types.MsgDeleteCoordinator) (*types.MsgDeleteCoordinatorResponse, error)`. The request must reject malformed account addresses and accept valid account addresses. Deleting a coordinator must remove both its address association and coordinator record.
