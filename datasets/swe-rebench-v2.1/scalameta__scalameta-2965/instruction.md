Scalafmt fails on manual type ascription after a `{}` block
## Configuration (required) ##

Please paste the contents of your `.scalafmt.conf` file here:
```
version                                  = 3.6.1
runner.dialect                           = scala213
project.git                              = true
style                                    = defaultWithAlign
docstrings.style                         = Asterisk
docstrings.wrap                          = false
indentOperator.preset                    = spray
maxColumn                                = 120
lineEndings                              = preserve
rewrite.rules                            = [RedundantParens, SortImports, AvoidInfix]
indentOperator.exemptScope               = all
align.preset                             = some
align.tokens."+"                         = [
  {
    code   = "~>"
    owners = [
      { regex = "Term.ApplyInfix" }
    ]
  }
]
literals.hexDigits                       = upper
literals.hexPrefix                       = lower
binPack.unsafeCallSite                   = always
binPack.unsafeDefnSite                   = always
binPack.indentCallSiteSingleArg          = false
binPack.indentCallSiteOnce               = true
newlines.avoidForSimpleOverflow          = [slc]
newlines.source                          = keep
newlines.beforeMultiline                 = keep
align.openParenDefnSite                  = false
align.openParenCallSite                  = false
align.allowOverflow                      = true
optIn.breakChainOnFirstMethodDot         = false
optIn.configStyleArguments               = false
danglingParentheses.preset               = false
spaces.inImportCurlyBraces               = true
rewrite.neverInfix.excludeFilters        = [
  and
  min
  max
  until
  to
  by
  eq
  ne
  "should.*"
  "contain.*"
  "must.*"
  in
  ignore
  be
  taggedAs
  thrownBy
  synchronized
  have
  when
  size
  only
  noneOf
  oneElementOf
  noElementsOf
  atLeastOneElementOf
  atMostOneElementOf
  allElementsOf
  inOrderElementsOf
  theSameElementsAs
  theSameElementsInOrderAs
]
rewriteTokens          = {
  "⇒": "=>"
  "→": "->"
  "←": "<-"
}
project.excludeFilters = [
  "scripts/authors.scala"
]
project.layout         = StandardConvention
```

## Command-line parameters (required) ##

When I run scalafmt via CLI like this: `scalafmt`

## Steps

Given code like this:
```scala
        implicit val um: Unmarshaller[HttpResponse, StorageObject] = Unmarshaller.withMaterializer {
          implicit ec => implicit mat =>
            {
              case HttpResponse(status, _, entity, _) if status.isSuccess() =>
                Unmarshal(entity).to[StorageObject]
              case HttpResponse(status, _, entity, _) =>
                Unmarshal(entity).to[String].flatMap { errorString =>
                  Future.failed(new RuntimeException(s"Uploading part failed with status $status: $errorString"))
                }
            }: PartialFunction[HttpResponse, Future[StorageObject]]
        }.withDefaultRetry
```

## Problem

Scalafmt errors with the following message
```scala
org.scalafmt.dynamic.exceptions.PositionExceptionImpl: /Users/mdedetrich/github/incubator-pekko-connectors/google-cloud-storage/src/main/scala/akka/stream/alpakka/googlecloud/storage/impl/GCStorageStream.scala:158: error: [dialect scala213] ; expected but : found
            }: PartialFunction[HttpResponse, Future[StorageObject]]
             ^: /Users/mdedetrich/github/incubator-pekko-connectors/google-cloud-storage/src/main/scala/akka/stream/alpakka/googlecloud/storage/impl/GCStorageStream.scala
```

## Expectation

scalafmt should not error out

## Workaround

Removing the type ascription (i.e. `: PartialFunction[HttpResponse, Future[StorageObject]]`) solves the problem.

## Notes

Original problematic source file is at https://github.com/apache/incubator-pekko-connectors/blob/4ebf24a4f996b088b4ed16cee182accc5ac92e1c/google-cloud-storage/src/main/scala/akka/stream/alpakka/googlecloud/storage/impl/GCStorageStream.scala#L149-L159
