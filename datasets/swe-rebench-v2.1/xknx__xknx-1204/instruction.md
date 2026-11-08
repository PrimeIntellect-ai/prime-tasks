Unhandled management telegram warnings in HA log
**Description of problem:**

When programming a device from ETS and using the "Physikalische Adresse & Applikationsprogram" button, I receive these warnings in my HA log:

```plain
2023-02-21 13:27:30.393 WARNING (MainThread) [xknx.management] Unhandled management telegram: Telegram(destination_address=0/0/0, direction=TelegramDirection.INCOMING, payload=<IndividualAddressRead />, source_address=1.0.1, tpci=TDataBroadcast())
2023-02-21 13:27:30.396 WARNING (MainThread) [xknx.management] Unhandled management telegram: Telegram(destination_address=0/0/0, direction=TelegramDirection.INCOMING, payload=<IndividualAddressRead />, source_address=1.0.1, tpci=TDataBroadcast())
2023-02-21 13:27:33.398 WARNING (MainThread) [xknx.management] Unhandled management telegram: Telegram(destination_address=0/0/0, direction=TelegramDirection.INCOMING, payload=<IndividualAddressRead />, source_address=1.0.1, tpci=TDataBroadcast())
2023-02-21 13:27:33.401 WARNING (MainThread) [xknx.management] Unhandled management telegram: Telegram(destination_address=0/0/0, direction=TelegramDirection.INCOMING, payload=<IndividualAddressRead />, source_address=1.0.1, tpci=TDataBroadcast())
2023-02-21 13:27:36.409 WARNING (MainThread) [xknx.management] Unhandled management telegram: Telegram(destination_address=0/0/0, direction=TelegramDirection.INCOMING, payload=<IndividualAddressRead />, source_address=1.0.1, tpci=TDataBroadcast())
2023-02-21 13:27:36.412 WARNING (MainThread) [xknx.management] Unhandled management telegram: Telegram(destination_address=0/0/0, direction=TelegramDirection.INCOMING, payload=<IndividualAddressRead />, source_address=1.0.1, tpci=TDataBroadcast())
2023-02-21 13:27:39.420 WARNING (MainThread) [xknx.management] Unhandled management telegram: Telegram(destination_address=0/0/0, direction=TelegramDirection.INCOMING, payload=<IndividualAddressRead />, source_address=1.0.1, tpci=TDataBroadcast())
2023-02-21 13:27:39.423 WARNING (MainThread) [xknx.management] Unhandled management telegram: Telegram(destination_address=0/0/0, direction=TelegramDirection.INCOMING, payload=<IndividualAddressRead />, source_address=1.0.1, tpci=TDataBroadcast())
2023-02-21 13:27:42.431 WARNING (MainThread) [xknx.management] Unhandled management telegram: Telegram(destination_address=0/0/0, direction=TelegramDirection.INCOMING, payload=<IndividualAddressRead />, source_address=1.0.1, tpci=TDataBroadcast())
2023-02-21 13:27:42.434 WARNING (MainThread) [xknx.management] Unhandled management telegram: Telegram(destination_address=0/0/0, direction=TelegramDirection.INCOMING, payload=<IndividualAddressRead />, source_address=1.0.1, tpci=TDataBroadcast())
2023-02-21 13:27:45.443 WARNING (MainThread) [xknx.management] Unhandled management telegram: Telegram(destination_address=0/0/0, direction=TelegramDirection.INCOMING, payload=<IndividualAddressRead />, source_address=1.0.1, tpci=TDataBroadcast())
2023-02-21 13:27:45.446 WARNING (MainThread) [xknx.management] Unhandled management telegram: Telegram(destination_address=0/0/0, direction=TelegramDirection.INCOMING, payload=<IndividualAddressRead />, source_address=1.0.1, tpci=TDataBroadcast())
2023-02-21 13:27:48.454 WARNING (MainThread) [xknx.management] Unhandled management telegram: Telegram(destination_address=0/0/0, direction=TelegramDirection.INCOMING, payload=<IndividualAddressRead />, source_address=1.0.1, tpci=TDataBroadcast())
2023-02-21 13:27:48.457 WARNING (MainThread) [xknx.management] Unhandled management telegram: Telegram(destination_address=0/0/0, direction=TelegramDirection.INCOMING, payload=<IndividualAddressRead />, source_address=1.0.1, tpci=TDataBroadcast())
2023-02-21 13:27:51.467 WARNING (MainThread) [xknx.management] Unhandled management telegram: Telegram(destination_address=0/0/0, direction=TelegramDirection.INCOMING, payload=<IndividualAddressRead />, source_address=1.0.1, tpci=TDataBroadcast())
2023-02-21 13:27:51.469 WARNING (MainThread) [xknx.management] Unhandled management telegram: Telegram(destination_address=0/0/0, direction=TelegramDirection.INCOMING, payload=<IndividualAddressRead />, source_address=1.0.1, tpci=TDataBroadcast())
2023-02-21 13:27:51.515 WARNING (MainThread) [xknx.management] Unhandled management telegram: Telegram(destination_address=0/0/0, direction=TelegramDirection.INCOMING, payload=<IndividualAddressResponse />, source_address=1.0.5, tpci=TDataBroadcast())
2023-02-21 13:27:51.518 WARNING (MainThread) [xknx.management] Unhandled management telegram: Telegram(destination_address=0/0/0, direction=TelegramDirection.INCOMING, payload=<IndividualAddressResponse />, source_address=1.0.5, tpci=TDataBroadcast())
2023-02-21 13:27:54.852 WARNING (MainThread) [xknx.management] Unhandled management telegram: Telegram(destination_address=0/0/0, direction=TelegramDirection.INCOMING, payload=<IndividualAddressRead />, source_address=1.0.1, tpci=TDataBroadcast())
2023-02-21 13:27:54.854 WARNING (MainThread) [xknx.management] Unhandled management telegram: Telegram(destination_address=0/0/0, direction=TelegramDirection.INCOMING, payload=<IndividualAddressRead />, source_address=1.0.1, tpci=TDataBroadcast())

```

I don't think they should be there

- [ ] using xknx standalone
- [x] using Home-Assistant knx integration

**Version information:**
- xknx / Home-Assistant release with the issue: 2023.2.1 (I know .5 exists but according to the changelog, no xknx updates are in these releases)
- last working xknx / Home-Assistant release (if known): N/A

**KNX installation:**
<!--
Please provide details about your installation.
- Manufacturer and model of relevant actors, sensors or interfaces.
- if you have access to ETS:
  - provide relevant group address parameters (DPT, Flags)
  - if applicable: excerpt of bus monitor output
-->

1.0.1 is the tunnel address ETS used
1.0.5 is a MDT BE-16000.02


**Problem-relevant `configuration.yaml` entries (fill out even if it seems unimportant):**

**Diagnostic data of the config entry (only when Home Assistant is used)**

[config_entry-knx-45c5f69670ca8326b6d870984a44f938.json.txt](https://github.com/XKNX/xknx/files/10793589/config_entry-knx-45c5f69670ca8326b6d870984a44f938.json.txt)

**Traceback (if applicable):**
