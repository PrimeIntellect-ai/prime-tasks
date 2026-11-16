SUSHI should not log a warning when specifying the version of a CodeSystem
In SUSHI 3.0.0 and later, a warning is logged when trying to look up a CodeSystem with a version specified when assigning codes. When SUSHI fishes for the CodeSystem resource, it treats the version specified as if it is the version of the resource, and not the version of the system itself. The version is assigned in the output correctly. However, SUSHI does not need to fish for the CodeSystem with the version, which would avoid the incorrect warnings being logged when it cannot find a resource with the matching version.

See: https://chat.fhir.org/#narrow/stream/215610-shorthand/topic/Strange.20behaviour.20concerning.20CodeSystem.20versions.20and.20aliases/near/375208251

FSH from the discussion: https://fshschool.org/FSHOnline/#/share/3NT8LKd (note: warning is only logged in SUSHI 3.0.0 and later).
