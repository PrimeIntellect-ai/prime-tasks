Client.PlaceDetails fails for ID ChIJUXcBoFD-nkcR3s74TnqlDHM
in v1.4.0 it fails with
**json: cannot unmarshal array into Go struct field PlaceDetailsResult.result.secondary_opening_hours of type maps.OpeningHours**

commit d757700d4eb9a15a3faa7af90c61d8270e2f8333 added SecondaryOpeningHours as an object:
SecondaryOpeningHours OpeningHours `json:"secondary_opening_hours,omitempty"`

it should be an array imho
[HIDDEN] `json:"secondary_opening_hours,omitempty"`

In ID ChIJUXcBoFD-nkcR3s74TnqlDHM it is an array: "secondary_opening_hours" : [{...}]
and the comment says so too: "SecondaryOpeningHours may contain an array of entries ..."

It works in v1.3.2

### Additional contract requirements

- The `SecondaryOpeningHours` field of `PlaceDetailsResult` is a slice of `OpeningHours` values (`[]OpeningHours`) that holds zero or more secondary opening-hours entries returned by the API.
- `PlaceDetailsFieldMaskSecondaryOpeningHours` is a `PlaceDetailsFieldMask` value that selects the `secondary_opening_hours` sub-field and may be included in the `Fields` slice of a `PlaceDetailsRequest`.
