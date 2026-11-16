BODY not included in issue
It seems like the bot only found the TODO without matching the BODY.

Here's an example issue: https://github.com/roblabla42/KFS/issues/34
The commit responsible: https://github.com/roblabla42/KFS/commit/fbbea9f3f22fb6a6796e6594adcfdbe36e15eb28#diff-fe2e65576035df545f1f4f7908915e70R48
And the config: https://github.com/roblabla42/KFS/blob/master/.github/config.yml

I suppose it's a bug in the body regex?
