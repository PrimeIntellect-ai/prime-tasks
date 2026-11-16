refreshInterval is being swallowed by clearTimeout
refreshInterval seems to be cancelled immediately by https://github.com/Kong/swrv/blob/415f8eb0d6a4dd85cf34c76997308448669c9514/src/use-swrv.ts#L380

Investigate and write tests for refreshInterval working as expected.
