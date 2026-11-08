In Transmodel API the language parameter is sometimes called "lang"
In the Transmodel API, the language parameter is sometimes called "lang", in those cases we don't use the `GraphQLUtils` methods `getTranslation()` and `getLocale`. We should deprecate the "lang" and use "language" and use the utils for the new parameter.

_Originally posted by @optionsome in https://github.com/opentripplanner/OpenTripPlanner/pull/4971#discussion_r1143070712_

### Additional contract requirements

For both `StopPlace.name` and `Quay.name`, the deprecated `lang` argument must remain usable by existing clients to select a translated name, just as the replacement `language` argument does.
