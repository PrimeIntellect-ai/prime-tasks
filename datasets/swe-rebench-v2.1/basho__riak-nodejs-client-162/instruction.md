Riak Search, empty string "" becomes integer 0. [JIRA: CLIENTS-881]
From the code it looks like isNaN is used to check the "" empty string, https://github.com/basho/riak-nodejs-client/blob/master/lib/commands/yokozuna/search.js#L98

But `isNaN("");        // false: the empty string is converted to 0 which is not NaN.` from https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/isNaN.
