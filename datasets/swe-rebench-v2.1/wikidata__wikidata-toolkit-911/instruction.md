Add support for returning better error messages from the MediaWiki API
In some cases, Wikibase editing can return multiple error messages in one go:

```json
{
  "error": {
    "code": "failed-save",
    "info": "The save has failed.",
    "messages": [
      {
        "name": "wikibase-api-failed-save",
        "parameters": [],
        "html": {
          "*": "The save has failed."
        }
      },
      {
        "name": "spam-blacklisted-link",
        "parameters": [
          {
            "list": [
              "tinyurl.com/auniresc"
            ],
            "type": "text"
          }
        ],
        "html": {
          "*": "The text you wanted to publish was blocked by the spam filter.\nThis is probably caused by a link to a forbidden external site.\nThe following text is what triggered our spam filter: tinyurl.com/auniresc"
        }
      }
    ],
    "*": "See https://www.wikidata.org/w/api.php for API usage. Subscribe to the mediawiki-api-announce mailing list at &lt;https://lists.wikimedia.org/postorius/lists/mediawiki-api-announce.lists.wikimedia.org/&gt; for notice of API deprecations and breaking changes."
  },
  "servedby": "mw-api-ext.eqiad.main-79f56d66b6-6hwm5"
}
```

In this case, WDTK ignores the entire `message` part, resulting in an error message that just contains
```
    "code": "failed-save",
    "info": "The save has failed.",
```
which is not very informative. It would be good to expose the inner part of the message too, which mentions the spam blacklist.

The same structure can be found in our own `wdtk-wikibaseapi/src/test/resources`, although the message there does not bring much additional info:
```json
{
  "servedby": "mw1147",
  "error": {
    "code": "no-such-entity",
    "info": "Could not find such an entity (Invalid id: Q0)",
    "messages": [
      {
        "name": "wikibase-api-no-such-entity",
        "parameters": [],
        "html": {
          "*": "Could not find such an entity"
        }
      }
    ],
    "*": "See https://www.wikidata.org/w/api.php for API usage"
  }
}
```

### Additional contract requirements

- Add a public class `MediaWikiErrorMessage` in package `org.wikidata.wdtk.wikibaseapi.apierrors`. It provides a public constructor `MediaWikiErrorMessage(String name, String htmlText)`, a public method `String getName()` returning the message name, and a public method `String getHTMLText()` returning the HTML text. Instances are immutable.
- Add a public method `List<MediaWikiErrorMessage> getDetailedMessages()` to `org.wikidata.wdtk.wikibaseapi.apierrors.MediaWikiApiErrorException`. It returns the detailed messages attached to the exception, or an empty list when none were supplied.
- Add a public static method `void throwMediaWikiApiErrorException(String errorCode, String errorMessage, List<MediaWikiErrorMessage> detailedMessages)` to `org.wikidata.wdtk.wikibaseapi.apierrors.MediaWikiApiErrorHandler`. It always throws a `MediaWikiApiErrorException` (or a subclass) that carries the supplied error code, error message and detailed messages.
- When a MediaWiki API error response contains a `messages` array, the resulting exception exposes those detailed messages through `getDetailedMessages()`, each providing its name and HTML text.
