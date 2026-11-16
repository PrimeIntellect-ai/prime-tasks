Fix _service { sdl } render to hide federated fields
While implementing this PR https://github.com/apollographql/apollo-federation-subgraph-compatibility/pull/35 I found we are not filtering federated schema fields from the SDL render like we should
