Fetch tags in GitAlg.syncFork
I think we also need to fetch tags in `GitAlg.syncFork` because some repos require tags to be present in order for the build to load successfully. See for example https://github.com/almond-sh/almond/pull/483.
