Stream::filter_map should use IntoFuture on its closure
Tagging for an 0.2 release to ensure we don't forget it. We're doing this everywhere else with `Stream`, so may as well be consistent.
