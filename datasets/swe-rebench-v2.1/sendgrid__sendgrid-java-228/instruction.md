class TrackingSettings use wrong jackson annotation
com.sendgrid.TrackingSettings use @JsonInclude(Include.NON_DEFAULT)
so when you set
OpenTrackingSetting setting1 = new OpenTrackingSetting();
setting1.setEnable(false);
settings.setOpenTrackingSetting(setting1);
ClickTrackingSetting setting2 = new ClickTrackingSetting();
setting2.setEnable(false);

the jackson will give a empty jsonobject, and the http request will get response 400

### Additional contract requirements

The classes `com.sendgrid.OpenTrackingSetting`, `com.sendgrid.ClickTrackingSetting`,
`com.sendgrid.SubscriptionTrackingSetting`, `com.sendgrid.GoogleAnalyticsSetting`,
`com.sendgrid.SpamCheckSetting`, `com.sendgrid.FooterSetting` and `com.sendgrid.BccSettings`
each expose a public method `setEnable(boolean enable)` that stores the supplied value.
Calling it with `true` enables the corresponding feature, and the serialized `enable`
property is then `true`.

When serialized after `setEnable(false)`:

- `OpenTrackingSetting`, `SubscriptionTrackingSetting`, `GoogleAnalyticsSetting`,
  `FooterSetting` and `BccSettings` must each produce exactly `{"enable":false}`.
- `ClickTrackingSetting` must produce exactly `{"enable":false,"enable_text":false}`.
- `SpamCheckSetting` must produce exactly `{"enable":false,"threshold":0}`.
