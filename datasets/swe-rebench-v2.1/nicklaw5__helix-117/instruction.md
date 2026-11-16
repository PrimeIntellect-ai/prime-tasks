Allow querying multiple channels with `GetChannelInformation`
Twitch didn't document this properly in their [docs](https://dev.twitch.tv/docs/api/reference#get-channel-information), but it is possible to specify multiple `broadcaster_id` parameters (up to 100) and you will get back multiple objects for these, quite similarly to how it works in `GetClips` function.

I would need to fetch channel information for ~400 channels and doing that in bulks of 100 seems way more efficient than making separate requests for each of these, but I can't find a way to specify more than 1 `BroadcasterID` in `GetChannelInformationParams`.

I had an idea to change `GetChannelInformationParams.BroadcasterID string` to `GetChannelInformationParams.BroadcasterIDs []string` (also just like it's done in the `GetClips` function), but this would be a breaking change and existing applications would need to update, would you be okay with me PRing this change or should a different solution be considered instead?
Update to the above: I just decided to open a PR for that.

### Additional contract requirements

- Expose `GetChannelInformationParams.BroadcasterIDs` (a slice of strings) as the public input for querying multiple broadcaster IDs, alongside the existing singular `GetChannelInformationParams.BroadcasterID` field.
- A single call with `BroadcasterIDs` must support requests containing up to 100 broadcaster IDs and return the matching channel objects.
- Existing callers requesting one channel must remain able to use `GetChannelInformationParams.BroadcasterID` without changing their code.
