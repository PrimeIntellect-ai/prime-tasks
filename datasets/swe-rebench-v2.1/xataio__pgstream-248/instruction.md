[Batch processor] Graceful shutdown
The batch sender should stop gracefully when the `Close` method is called. It currently hangs if the close is called without cancelling the context.
