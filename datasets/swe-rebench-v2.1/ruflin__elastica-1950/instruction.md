Call to a member function toArray() on array
When i run a query then i get this error `Call to a member function toArray() on array`

My Setup:
----
- symfony/symfony v3.3.8
- friendsofsymfony/elastica-bundle dev-master 96c79eb
- elasticsearch/elasticsearch v6.0.0
- ruflin/elastica 6.0.0
- Elastic-Server Version: 6.0.0

Error:
----
```txt
Call to a member function toArray() on array
```

**Entry-point:** (use of FOSElasticaBundle)
```php
$adapter = $finder->createPaginatorAdapter($aqb->getQuery());
$aggData = $adapter->getAggregations();
```

**stack-trace:**
```txt
Symfony\Component\Debug\Exception\FatalThrowableError:
Call to a member function toArray() on array

  at vendor/ruflin/elastica/lib/Elastica/Query.php:333
  at Elastica\Query->toArray()
     (vendor/ruflin/elastica/lib/Elastica/Search.php:455)
  at Elastica\Search->search()
     (vendor/ruflin/elastica/lib/Elastica/Type.php:356)
  at Elastica\Type->search(object(Query))
     (vendor/friendsofsymfony/elastica-bundle/src/Paginator/RawPaginatorAdapter.php:107)
  at FOS\ElasticaBundle\Paginator\RawPaginatorAdapter->getAggregations()
     (src/ggm/ClassifiedAdBundle/Controller/AdvertController.php:455)
  at ggm\ClassifiedAdBundle\Controller\AdvertController->overviewAction(object(Request), 'literatur')
  at call_user_func_array(array(object(AdvertController), 'overviewAction'), array(object(Request), 'literatur'))
     (vendor/symfony/symfony/src/Symfony/Component/HttpKernel/HttpKernel.php:153)
  at Symfony\Component\HttpKernel\HttpKernel->handleRaw(object(Request), 1)
     (vendor/symfony/symfony/src/Symfony/Component/HttpKernel/HttpKernel.php:68)
  at Symfony\Component\HttpKernel\HttpKernel->handle(object(Request), 1, true)
     (vendor/symfony/symfony/src/Symfony/Component/HttpKernel/Kernel.php:171)
  at Symfony\Component\HttpKernel\Kernel->handle(object(Request))
     (web/app_dev.php:31)
  at require('/home/kokoloko/projects/php/portal-webapp-2/web/app_dev.php')
     (vendor/symfony/symfony/src/Symfony/Bundle/WebServerBundle/Resources/router.php:42)
```

Problem
----

[HIDDEN]

### Additional contract requirements

- `Elastica\Query::setQuery(Elastica\Query\AbstractQuery $query)` replaces the query clause of the request with the given query object and returns the `Query` instance for fluent chaining.
- `Elastica\Query::setParam(string $key, mixed $value)` stores an arbitrary parameter value, including a raw array for the `post_filter` parameter, and returns the `Query` instance for fluent chaining.
- `Elastica\Query::toArray()` returns the full request representation as an array, including the `query` clause and any additional parameters such as `post_filter`. A raw-array `post_filter` that is provided is included in the result, and an empty `post_filter` is omitted from the result.
