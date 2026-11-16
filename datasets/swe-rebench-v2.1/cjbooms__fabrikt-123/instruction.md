Use operationId in clients as well
Follow-up for #111: for the sake of consistency, it seems sensible to use the `operationId` in clients as well, not just controllers. It looks like right now, the name is generated based on the path (`/example-path-1` -> `getExamplePath1`).
