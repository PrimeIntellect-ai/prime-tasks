Unsynchronized WriteAPIBlocking.Write* functions
`WriteAPIBlocking.WritePoint` and `WriteAPIBlocking.WriteRecord` must ensure synchronized calling of  `write.Service.HandleWrite`
