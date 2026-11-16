Card wide action not working
Release: v5.2.0
Browser and Operating System: Microsoft Edge / Windows 10 Home v22H2

I have defined a card wide action to trigger the fullscreen mode when the card is tapped based on the example code provide in the README. However, nothing happens when the card is tapped, i.e., clicked on with the mouse pointer.

Here is the yaml:

```
square: false
type: grid
cards:
  - type: custom:frigate-card
    cameras:
      - camera_entity: camera.front_south
        live_provider: image
        dependencies:
          cameras:
            - front_south_sub
      - camera_entity: camera.front_south
        live_provider: go2rtc
        id: front_south_sub
        hide: true
        go2rtc:
          modes:
            - mse
    menu:
      buttons:
        frigate:
          enabled: false
    view:
      actions:
        double_tap_action:
          action: custom:frigate-card-action
          frigate_card_action: fullscreen
    automations:
      - conditions:
          fullscreen: true
        actions:
          - action: custom:frigate-card-action
            frigate_card_action: live_substream_on
        actions_not:
          - action: custom:frigate-card-action
            frigate_card_action: live_substream_off
columns: 3
```

Here's the diagnostic that results if I enable the Frigate button and hold it down. Enabling the Frigate button does not fix the issue.

```
{
  "ha_version": "2024.3.0",
  "card_version": "5.2.0",
  "browser": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36 Edg/122.0.0.0",
  "date": "2024-03-14T13:41:43.882Z",
  "frigate_version": {
    "92f82476c801e2628665f993d5257a32": "5.0.1/0.13.2-6476f8a"
  },
  "lang": "en",
  "timezone": "America/New_York",
  "git": {
    "build_version": "5.2.0-HEAD+g69249b6",
    "build_date": "Fri, 23 Jun 2023 15:26:26 GMT",
    "commit_date": "Thu, 22 Jun 2023 09:21:26 -0600"
  },
  "config": {
    "type": "custom:frigate-card",
    "cameras": [
      {
        "camera_entity": "camera.front_south",
        "live_provider": "image",
        "dependencies": {
          "cameras": [
            "front_south_sub"
          ]
        }
      },
      {
        "camera_entity": "camera.front_south",
        "live_provider": "go2rtc",
        "id": "front_south_sub",
        "hide": true,
        "go2rtc": {
          "modes": [
            "mse"
          ]
        }
      }
    ],
    "menu": {
      "buttons": {
        "frigate": {
          "enabled": true
        }
      }
    },
    "view": {
      "actions": {
        "double_tap_action": {
          "action": "custom:frigate-card-action",
          "frigate_card_action": "fullscreen"
        }
      }
    },
    "automations": [
      {
        "conditions": {
          "fullscreen": true
        },
        "actions": [
          {
            "action": "custom:frigate-card-action",
            "frigate_card_action": "live_substream_on"
          }
        ],
        "actions_not": [
          {
            "action": "custom:frigate-card-action",
            "frigate_card_action": "live_substream_off"
          }
        ]
      }
    ]
  }
}
```

### Additional contract requirements

When the card-wide `double_tap_action` is configured to activate fullscreen, a double-tap on the card must activate fullscreen mode.
