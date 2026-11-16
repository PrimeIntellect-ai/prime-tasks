circular peer-dependency: core <-> common
Hi there,

great project. Thank you very much.

I noticed that both packages ("core" and "common") list each other as a peerDependency. I am using serverless-bundle (https://github.com/AnomalyInnovations/serverless-bundle) to package my lambda functions and I have to list both "core" and "common" as "externals" to get typedorm to work after packaging (not 100% sure why that is, webpack seems to strip some necessary parts). However the circular dependency causes the bundler to go into an endless loop trying installing core, common, core, common and so on.
I can manually remove the peer dependencies and get it to work, but this is of course not a real solution.
What do you think about this? I can provide more details if needed.

Cheers
Paul
