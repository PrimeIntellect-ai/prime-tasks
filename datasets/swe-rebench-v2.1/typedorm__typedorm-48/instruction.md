Auto remove connection when failed to build metadatas for it
Creating connection with entities that are likely to fail to be build will put connection instance in an undesirable state, where connection exists in connection manger's context but but entities are not built.

If failed to build entity metadata for connection, connection should be removed from connection manger.
