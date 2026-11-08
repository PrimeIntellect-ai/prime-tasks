Mark teams functionality that's based on ID as deprecated
The teams functions that use ID should be deprecated as the REST APIs have been marked a legacy and are under a closing down notice ([ref](https://docs.github.com/en/rest/teams/teams?apiVersion=2022-11-28#get-a-team-legacy)).

### Additional contract requirements

- The team management operations of the teams API that identify the team by its numeric ID must carry a standard Go `Deprecated:` notice in their documentation. These are: GetTeamByID, EditTeamByID, DeleteTeamByID, ListChildTeamsByParentID, ListTeamReposByID, IsTeamRepoByID, AddTeamRepoByID, RemoveTeamRepoByID, ListTeamProjectsByID, ReviewTeamProjectsByID, AddTeamProjectByID, RemoveTeamProjectByID, ListIDPGroupsForTeamByID, and CreateOrUpdateIDPGroupConnectionsByID.
- The slug-based counterparts of these operations are not deprecated.
- The team member, team discussion, and team discussion comment operations are out of scope and are not deprecated by this change.
