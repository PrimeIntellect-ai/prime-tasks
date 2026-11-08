Change Via field to pointer
note:
- `omitempty` doesn't emit empty `Via{}` object. [HIDDEN]
- It would cause problem only when request create/update Ticket or TicketComment

### Additional contract requirements

- `Ticket.Via` and `TicketComment.Via` must be pointer fields so callers can represent an absent Via.
- When a ticket or ticket comment without Via is sent in a create or update request, the JSON payload must omit the `via` property rather than include an empty object.
