getContractMetadata API vs SDK
### [REQUIRED] Environment

- Browser version: Chrome 106
- Alchemy SDK version: 2.2.0

### [REQUIRED] Describe the problem

The getContractMetadata API returns useful openSea data that the SDK does not currently include.

### Additional contract requirements

- `NftNamespace.getContractMetadata(address: string)` resolves to an `NftContract` that includes an optional `openSea` property of type `OpenSeaCollectionMetadata` when the API returns OpenSea data. The `openSea` object carries the OpenSea-provided values from the API response.
- `OpenSeaCollectionMetadata` is a public type exported from the package's public API. It has the following optional fields: `floorPrice?: number`, `collectionName?: string`, `safelistRequestStatus?: OpenSeaSafelistRequestStatus`, `imageUrl?: string`, `description?: string`, `externalUrl?: string`, `twitterUsername?: string`, `discordUrl?: string`, `lastIngestedAt?: string`.
- `OpenSeaSafelistRequestStatus` is a public enum exported from the package's public API with the members `VERIFIED`, `APPROVED`, `REQUESTED`, and `NOT_REQUESTED`.
