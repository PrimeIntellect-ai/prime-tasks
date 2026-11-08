wikibase: Bug introduced by property label resolution in QA issues when new entities are created
As mentioned by @sunilnatraj  in https://github.com/OpenRefine/OpenRefine/pull/7068#discussion_r1914734982:

> For the new entity case, setting self as the reference is incorrect.
>
> The value of new entity is this non-existent Q2852607907487331030.
>
> As part of https://github.com/OpenRefine/OpenRefine/pull/6895 the code resolves the entity to a proper label, this code fails in this scenario.
>
> `java.util.concurrent.ExecutionException: org.wikidata.wdtk.wikibaseapi.apierrors.NoSuchEntityErrorException: [no-such-entity] Could not find an entity with the ID "Q2852607907487331030".
> 	at com.google.common.cache.LocalCache.loadAll(LocalCache.java:4136)
> 	at com.google.common.cache.LocalCache.getAll(LocalCache.java:4087)
> 	at com.google.common.cache.LocalCache$LocalLoadingCache.getAll(LocalCache.java:5004)
> 	at org.openrefine.wikibase.utils.EntityCache.getMultipleDocuments(EntityCache.java:117)
> 	at org.openrefine.wikibase.qa.EditInspector.resolveWarningPropertyLabels(EditInspector.java:235)`

So the changes in https://github.com/OpenRefine/OpenRefine/pull/6895 introduced a bug that should be fixed.

### Additional contract requirements

- QA warnings containing an ordinary Wikibase item or property ID that has no associated label must receive its resolved label.
