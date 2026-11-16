Problems with `user_roles` & `user_groups` fieldtypes
> Issue created from conversation in: https://github.com/statamic-rad-pack/runway/issues/196#issuecomment-2095457819

I am currently experiencing problems when trying to set up users as a Runway resource.
While relationships and computed field function perfectly, it has caused an issue with the permission fields:

The user roles & user groups fields no longer function correctly, it seems Runway does not support the `user_roles` & `user_groups` field types?
I don´t see it listed in the list of supported fieldtypes: https://runway.duncanmcclean.com/blueprints#content-supported-fieldtypes

However, in the linked conversation you did mention that these should work as long as the columns are configured properly, and while they do not immediately throw an error, they do not function as they normally would.
Statamic manages permissions through the `role_user` & `group_user` tables, but the field created from the Runway blueprint attempts to save the values into columns directly (which causes an error for a missing column).
I can´t find a way to configure Statamic to manage roles & groups through columns instead, so I am unsure how to properly implement these field types, especially since there is currently no documentation on how to do so.

How should roles & groups be properly implemented for a user runway resource?
