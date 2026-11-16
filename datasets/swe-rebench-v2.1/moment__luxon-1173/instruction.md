`Duration#toFormat` should support a formatting token for `week`
I'm surprised that `Duration#toFormat` doesn't support a token for `week` (7 days). (e.g. `w`)

Is there a reason this unit token was omitted for Duration specifically?

Current release tag source ref: https://github.com/moment/luxon/blob/2.3.1/src/duration.js#L397-L426
