Possibility to use a content-type in multiple indexes
<!-- This is not an exhaustive model but a help. No step is mandatory. -->

**Description**
Not sure if it is a new feature request or a bug but:
Possibility to use a content-type in multiple indexes
Currently it is possible to create custom indexes and for example create a index called products with content-type Shoes and T-shirts

But once you create one you cannot re-use the content type for another index example "offers".

For my understanding it is possible to do it with meilisearch as you can add any information to any index but it is not possible with this plugin.

**Basic example**
An option could be to change the config of the plugin and instead write the content type name as root of the json, use instead the index name

currently the config looks like

```
module.exports = () => ({
  //...
  meilisearch: {
    config: {
      shirts: {
        indexName: 'products',
      },
      shoes: {
        indexName: 'products',
      },
    shirts: {
indexName: 'offers'. //THIS is not possible right now as overwrite previous index.
}
    },
  },
})
```
What I propose is
```
module.exports = () => ({
  //...
  meilisearch: {
    config: {
      products: {
        contentType: ['shoes','t-shirt']
      },
      offers: {
         contentType: ['jackets','t-shirt']
      },

    },
  },
})
```
Or as it is right now but not overwriting previous information and being able to manage it over the admin panel. But I do believe it would be easier the first option.

### Additional contract requirements

- Add a public method `getIndexNamesOfContentType({ contentType })` on the Meilisearch service (in `server/services/meilisearch/config.js`). It returns an array of index names for the given content type. The `indexName` option may be a non-empty string, an array of non-empty strings, or undefined; when it is undefined, the returned array contains the collection name.
- The Meilisearch service exposes a public method `getContentTypesWithSameIndex({ contentType })` (in `server/services/meilisearch/connector.js`). It returns the fully qualified Strapi content-type identifiers (`api::<type>.<type>`) of every content type that shares at least one index name with the given content type, in the order in which those content types are currently indexed.
- The `listContentTypesWithCustomIndexName({ indexName })` method returns the collection names of all content types configured with the given index name, including when `indexName` is configured as an array.
- When validation rejects the `indexName` option for `restaurant`, log exactly: `The "indexName" option of "restaurant" should be a non-empty string or an array of non-empty strings`.
- When adding two documents with task UID `undefined`, log exactly `The task to add 2 documents to the Meilisearch index "customIndex" has been enqueued (Task uid: undefined).` for `customIndex`, and exactly `The task to add 2 documents to the Meilisearch index "anotherIndex" has been enqueued (Task uid: undefined).` for `anotherIndex`.


- For the tested multi-index add operation, return `[10, 10]`. For the tested multi-index delete operation, return `[{ taskUid: 1 }, { taskUid: 2 }, { taskUid: 1 }, { taskUid: 2 }]`.

When deleting 2 documents from multiple indexes and the task UID is `undefined`, log exactly `A task to delete 2 documents of the index "customIndex" in Meilisearch has been enqueued (Task uid: undefined).` for `customIndex` and `A task to delete 2 documents of the index "anotherIndex" in Meilisearch has been enqueued (Task uid: undefined).` for `anotherIndex`.

When updating settings for multiple indexes and the task UID is `undefined`, log exactly `A task to update the settings to the Meilisearch index "customIndex" has been enqueued (Task uid: undefined).` for `customIndex` and `A task to update the settings to the Meilisearch index "anotherIndex" has been enqueued (Task uid: undefined).` for `anotherIndex`.
