[Robots.txt] Empty disallow statement not to clear other rules
In the current implementation of SimpleRobotRulesParser ([line 819](https://github.com/crawler-commons/crawler-commons/blob/0656e9c56137bc66bdd47238f2b6b45c36c30280/src/main/java/crawlercommons/robots/SimpleRobotRulesParser.java#L819)), an empty disallow statement (`Disallow: ` ) clears all rules read so far. It should not.

- the [initial robots.txt RFC draft](https://www.robotstxt.org/robotstxt.html) didn't include the `Allow:` statement and the empty disallow statement was required to express that all paths are allowed.

- the [formal syntax of RFC 9309](https://www.rfc-editor.org/rfc/rfc9309.html#section-2.2) allows empty patterns in allow/disallow statements. However, because longer rules take precedence, empty patterns would be matched last.

The issue was observed with [this robots.txt](https://agriexotic.com/robots.txt). Here the empty disallow statement in the second rule group, clears the already parsed rules. Both groups are addressed to the wildcard user-agent and therefore merged.

### Additional contract requirements

- An empty `Disallow:` must be ignored rather than treated as a zero-length disallow rule. With `Disallow: /disallowed/`, `Allow: /allowed/`, and an empty `Disallow:`, `/` and `/anypage.html` remain allowed, `/disallowed/index.html` remains disallowed, and `/allowed/index.html` remains allowed, including when the empty directive is in a subsequent matching `User-agent: *` group.
