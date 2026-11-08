Multi-character triggers no longer work
## Environment

- @draft-js-plugins/editor version: v4.1.0
- plugin name and version: @draft-js-plugins/mention v4.4.1

## Description

Multi-character triggers appear to be broken for `@draft-js-plugins/mention`.

With [this PR](https://github.com/draft-js-plugins/draft-js-plugins/pull/1807/files#diff-f5be53e8ae08de0a2489882b1824da7087229abf7a92b29c8d5f3a9522e43690R45), support for multi-character triggers appears to have gone away.  I've verified that a change along the following lines to `@draft-js-plugins/mention` v4.4.1 restores the support for multi-character triggers, although I'm not sure whether there are other unwanted side effects, e.g., related to the new group capture:

```patch
diff --git a/packages/mention/src/mentionSuggestionsStrategy.ts b/packages/mention/src/mentionSuggestionsStrategy.ts
index 3107214a..f7d726a8 100644
--- a/packages/mention/src/mentionSuggestionsStrategy.ts
+++ b/packages/mention/src/mentionSuggestionsStrategy.ts
@@ -67,9 +67,9 @@ export default (
   regExp: string
 ): ((contentBlock: ContentBlock, callback: FindWithRegexCb) => void) => {
   //eslint-disable-line
-  const triggerPattern = `[${triggers
[HIDDEN]
     .map((trigger) => escapeRegExp(trigger))
-    .join('')}]`;
[HIDDEN]
   const MENTION_REGEX = supportWhiteSpace
     ? new RegExp(`${triggerPattern}(${regExp}|\\s)*`, 'g')
     : new RegExp(`(\\s|^)${triggerPattern}${regExp}*`, 'g');
```

[HIDDEN]

In version v3.1.5 of `draft-js-mention-plugin`, a trigger of "in:" worked for me:

![2021-04-28_13-22](https://user-images.githubusercontent.com/760949/116460888-cefe6680-a824-11eb-8a37-3a1fd6367589.png)

### Additional contract requirements

- Configured multi-character triggers, such as `in:`, must be recognized as complete trigger strings when locating mention suggestions, rather than matching only one character from the trigger.
