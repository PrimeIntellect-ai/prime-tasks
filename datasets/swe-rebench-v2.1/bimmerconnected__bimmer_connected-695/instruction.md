send_poi no longer working after captcha requirement
### Describe the issue

I'm able to successfully use the CLI to get the status of my vehicle using the captcha-token. However I'm no longer able to call send_poi. I was able to use the CLI with this vehicle before the captcha requirement.

You can see the 200 response in debug so it's not the account or auth

% bimmerconnected --debug sendpoi --captcha-token $CAPTCHA $BMW_USER_NAME $BMW_PASSWORD $BMW_REGION $BMW_VIN $LAT $LON
DEBUG:bimmer_connected.account:Getting vehicle list
DEBUG:bimmer_connected.account:Getting vehicle list
DEBUG:httpx._client:HTTP Request: POST https://cocoapi.bmwgroup.us/eadrax-vcs/v5/vehicle-list "HTTP/1.1 200 OK"
DEBUG:httpx._client:HTTP Request: GET https://cocoapi.bmwgroup.us/eadrax-vcs/v5/vehicle-data/profile "HTTP/1.1 200 OK"
DEBUG:httpx._client:HTTP Request: POST https://cocoapi.bmwgroup.us/eadrax-vcs/v5/vehicle-list "HTTP/1.1 200 OK"
DEBUG:httpx._client:HTTP Request: POST https://cocoapi.bmwgroup.us/eadrax-vcs/v5/vehicle-list "HTTP/1.1 200 OK"
DEBUG:bimmer_connected.vehicle.vehicle:Getting vehicle list
DEBUG:httpx._client:HTTP Request: GET https://cocoapi.bmwgroup.us/eadrax-vcs/v4/vehicles/state?apptimezone=0&appDateTime=1732638728000 "HTTP/1.1 200 OK"
DEBUG:httpx._client:HTTP Request: POST https://cocoapi.bmwgroup.us/eadrax-dcs/v2/user/b2409aba-1056-4e5b-88b7-e77e182a4933/send-to-car "HTTP/1.1 400 Bad Request"
ERROR:bimmer_connected.api.client:MyBMWAPIError due to HTTPStatusError: Bad Request -
MyBMWAPIError: HTTPStatusError: Bad Request -

### Expected behavior

send_poi should send the coordinates to my BMW iDrive as a message allowing me to set the destination

### Which Home Assistant version are you using?

command is running in terminal for testing

### What was the last working version of Home Assistant Core?

pre-captcha was working

### What is your region?

North America

### MyBMW website

- [X] I can still successfully login to the BMW MyBMW website and the car status is available there.
- [X] I have MyBMW enabled for my vehicle.

### Number of cars

- [ ] I have 2 or more cars linked to the MyBMW account.
- [ ] I have a Mini vehicle linked to my account.
- [ ] I have a Toyota Supra vehicle linked to my account.

### Output of bimmer_connected fingerprint

```txt
{
    "capabilities": {
        "a4aType": "BLUETOOTH",
        "alarmSystem": false,
        "climateFunction": "VENTILATION",
        "climateNow": true,
        "climateTimerTrigger": "DEPARTURE_TIMER",
        "digitalKey": {
            "bookedServicePackage": "NONE",
            "isDigitalKeyFirstSupported": false,
            "state": "NOT_AVAILABLE",
            "vehicleSoftwareUpgradeRequired": false
        },
        "horn": true,
        "isBatteryPreconditioningSupported": false,
        "isBmwChargingSupported": false,
        "isCarSharingSupported": false,
        "isChargeNowForBusinessSupported": false,
        "isChargingHistorySupported": false,
        "isChargingHospitalityEnabled": false,
        "isChargingLoudnessEnabled": false,
        "isChargingPlanSupported": false,
        "isChargingPowerLimitEnabled": false,
        "isChargingSettingsEnabled": false,
        "isChargingTargetSocEnabled": false,
        "isClimateTimerSupported": true,
        "isClimateTimerWeeklyActive": false,
        "isCustomerEsimSupported": false,
        "isDCSContractManagementSupported": false,
        "isDataPrivacyEnabled": false,
        "isEasyChargeEnabled": false,
        "isEvGoChargingSupported": false,
        "isLocationBasedChargingSettingsSupported": false,
        "isMiniChargingSupported": false,
        "isNonLscFeatureEnabled": false,
        "isOptimizedChargingSupported": false,
        "isPersonalPictureUploadSupported": false,
        "isPlugAndChargeSupported": false,
        "isRemoteEngineStartSupported": false,
        "isRemoteHistoryDeletionSupported": false,
        "isRemoteHistorySupported": true,
        "isRemoteParkingEes25Active": false,
        "isRemoteParkingSupported": false,
        "isRemoteServicesActivationRequired": false,
        "isRemoteServicesBookingRequired": false,
        "isScanAndChargeSupported": false,
        "isSustainabilityAccumulatedViewEnabled": false,
        "isSustainabilitySupported": false,
        "isThirdPartyAppStoreSupported": false,
        "isWifiHotspotServiceSupported": false,
        "lastStateCallState": "ACTIVATED",
        "lights": true,
        "locationBasedCommerceFeatures": {
            "fueling": false,
            "parking": false,
            "reservations": false
        },
        "lock": true,
        "personalPictureUpload": {
            "aspectRatio": "2:1",
            "state": "NOT_AVAILABLE"
        },
        "remote360": true,
        "remoteChargingCommands": {},
        "remoteServices": {
            "batteryPreconditioningControl": {
                "executionApi": "RS_API_V5",
                "id": "batteryPreconditioningControl",
                "state": "NOT_AVAILABLE"
            },
            "centralLockControl": {
                "executionApi": "RS_API_V5",
                "id": "centralLockControl",
                "state": "NOT_AVAILABLE"
            },
            "departureTimerControl": {
                "executionApi": "RS_API_V5",
                "id": "departureTimerControl",
                "state": "NOT_AVAILABLE"
            },
            "doorLock": {
                "executionApi": "RS_API_V5",
                "id": "doorLock",
                "state": "ACTIVATED"
            },
            "doorUnlock": {
                "executionApi": "RS_API_V5",
                "id": "doorUnlock",
                "state": "ACTIVATED"
            },
            "hornBlow": {
                "executionApi": "RS_API_V5",
                "id": "hornBlow",
                "state": "ACTIVATED"
            },
            "inCarCamera": {
                "executionApi": "RS_360_V4",
                "id": "inCarCamera",
                "state": "NOT_AVAILABLE"
            },
            "inCarCameraDwa": {
                "executionApi": "RS_360_V4",
                "id": "inCarCameraDwa",
                "state": "NOT_AVAILABLE"
            },
            "interiorPreconditioningControl": {
                "executionApi": "RS_API_V5",
                "id": "interiorPreconditioningControl",
                "state": "NOT_AVAILABLE"
            },
            "lightFlash": {
                "executionApi": "RS_API_V5",
                "id": "lightFlash",
                "state": "ACTIVATED"
            },
            "remote360": {
                "executionApi": "RS_360_V4",
                "functions": {
                    "encryptionMethod": [
                        "ENCRYPTION_METHOD_A"
                    ]
                },
                "id": "remote360",
                "state": "ACTIVATED"
            },
            "surroundViewRecorder": {
                "executionApi": "RS_360_V4",
                "id": "surroundViewRecorder",
                "state": "NOT_AVAILABLE"
            },
            "telematicsWakeup": {
                "executionApi": "RS_API_V5",
                "id": "telematicsWakeup",
                "state": "NOT_AVAILABLE"
            },
            "wakeup": {
                "executionApi": "RS_API_V5",
                "id": "wakeup",
                "state": "NOT_AVAILABLE"
            },
            "windowControl": {
                "executionApi": "RS_API_V5",
                "id": "windowControl",
                "state": "NOT_AVAILABLE"
            }
        },
        "sendPoi": true,
        "specialThemeSupport": [],
        "thirdPartyAppStore": {
            "state": "NOT_AVAILABLE"
        },
        "unlock": true,
        "vehicleFinder": true,
        "vehicleStateSource": "LAST_STATE_CALL"
    },
    "state": {
        "checkControlMessages": [
            {
                "severity": "LOW",
                "type": "ENGINE_OIL"
            }
        ],
        "climateTimers": [
            {
                "departureTime": {
                    "hour": 7,
                    "minute": 0
                },
                "isWeeklyTimer": false,
                "timerAction": "DEACTIVATE",
                "timerWeekDays": []
            },
            {
                "departureTime": {
                    "hour": 7,
                    "minute": 0
                },
                "isWeeklyTimer": true,
                "timerAction": "DEACTIVATE",
                "timerWeekDays": [
                    "MONDAY"
                ]
            },
            {
                "departureTime": {
                    "hour": 7,
                    "minute": 0
                },
                "isWeeklyTimer": true,
                "timerAction": "DEACTIVATE",
                "timerWeekDays": [
                    "MONDAY"
                ]
            }
        ],
        "combustionFuelLevel": {
            "range": 219,
            "remainingFuelLiters": 22
        },
        "currentMileage": 111573,
        "departurePlan": {},
        "doorsState": {
            "combinedSecurityState": "UNLOCKED",
            "combinedState": "CLOSED",
            "hood": "CLOSED",
            "leftFront": "CLOSED",
            "leftRear": "CLOSED",
            "rightFront": "CLOSED",
            "rightRear": "CLOSED",
            "trunk": "CLOSED"
        },
        "driverPreferences": {
            "lscPrivacyMode": "OFF"
        },
        "isLeftSteering": true,
        "isLscSupported": true,
        "lastFetched": "2024-11-26T17:21:03.888Z",
        "lastUpdatedAt": "2024-11-26T13:23:57Z",
        "location": {
            "address": {
                "formatted": "some_formatted_address"
            },
            "coordinates": {
                "latitude": 12.3456,
                "longitude": 34.5678
            },
            "heading": 123
        },
        "range": 219,
        "requiredServices": [],
        "roofState": {
            "roofState": "CLOSED",
            "roofStateType": "SUN_ROOF"
        },
        "securityOverviewMode": null,
        "vehicleSoftwareVersion": {
            "iStep": {
                "iStep": 540,
                "month": 11,
                "seriesCluster": "S15A",
                "year": 19
            },
            "puStep": {
                "month": 11,
                "year": 19
            }
        },
        "windowsState": {
            "combinedState": "CLOSED",
            "leftFront": "CLOSED",
            "leftRear": "CLOSED",
            "rightFront": "CLOSED",
            "rightRear": "CLOSED"
        }
    }
}
```


### Anything in the logs that might be useful for us?

```txt
DEBUG:bimmer_connected.account:Getting vehicle list
DEBUG:bimmer_connected.account:Getting vehicle list
DEBUG:httpx._client:HTTP Request: POST https://cocoapi.bmwgroup.us/eadrax-vcs/v5/vehicle-list "HTTP/1.1 200 OK"
DEBUG:httpx._client:HTTP Request: GET https://cocoapi.bmwgroup.us/eadrax-vcs/v5/vehicle-data/profile "HTTP/1.1 200 OK"
DEBUG:httpx._client:HTTP Request: POST https://cocoapi.bmwgroup.us/eadrax-vcs/v5/vehicle-list "HTTP/1.1 200 OK"
DEBUG:httpx._client:HTTP Request: POST https://cocoapi.bmwgroup.us/eadrax-vcs/v5/vehicle-list "HTTP/1.1 200 OK"
DEBUG:bimmer_connected.vehicle.vehicle:Getting vehicle list
DEBUG:httpx._client:HTTP Request: GET https://cocoapi.bmwgroup.us/eadrax-vcs/v4/vehicles/state?apptimezone=0&appDateTime=1732638728000 "HTTP/1.1 200 OK"
DEBUG:httpx._client:HTTP Request: POST https://cocoapi.bmwgroup.us/eadrax-dcs/v2/user/b2409aba-1056-4e5b-88b7-e77e182a4933/send-to-car "HTTP/1.1 400 Bad Request"
ERROR:bimmer_connected.api.client:MyBMWAPIError due to HTTPStatusError: Bad Request -
MyBMWAPIError: HTTPStatusError: Bad Request -
```


### Additional information

_No response_

### Additional contract requirements

- The `send_poi` request sent to the BMW API must include the destination coordinates in the place position, using the key `lng` for the longitude (the API rejects `lon`) and the key `lat` for the latitude.
