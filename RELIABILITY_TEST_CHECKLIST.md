# Medication Reminder Reliability Checklist

Run this checklist on at least one real iPhone and one real Android phone before beta distribution.

## Reminders

- [ ] Allow notifications and exact alarms from Settings > Reminder Reliability.
- [ ] Use the 10-second test and confirm the bottle-shake sound is clear.
- [ ] Confirm a scheduled reminder arrives while the app is open, in the background, and force-closed.
- [ ] Restart the phone and confirm future reminders still arrive.
- [ ] Enable battery saver on Android and repeat the test.
- [ ] Deny notification permission and confirm the app explains how to restore access.
- [ ] Tap Taken and Missed from an expanded notification and verify the timeline keeps the correct status.
- [ ] Change the device time zone and confirm future reminders follow local time.
- [ ] Check a daylight-saving transition date where applicable.

## Medication safety

- [ ] Scan at least ten real labels, including English, Vietnamese, wrapped labels, and low-light photos.
- [ ] Confirm name, strength, Qty, directions, provider, and phone can always be edited before saving.
- [ ] Confirm unclear, PRN, tapering, weekly, conflicting, or incomplete directions never create an automatic schedule.
- [ ] Confirm duplicate photos or duplicate medications do not create duplicate reminders.
- [ ] Confirm deleting a medication removes its future reminders.

## Accessibility

- [ ] Test every main screen with VoiceOver and TalkBack.
- [ ] Test Large and accessibility text sizes without clipped controls.
- [ ] Confirm status is communicated by text/icon, not color alone.
- [ ] Confirm every button has a useful spoken label and a comfortable tap target.
- [ ] Test Increased Contrast and Reduce Motion on iPhone.

## Privacy and recovery

- [ ] Confirm crash reports are off after a fresh installation.
- [ ] Enable crash reports and verify reports contain no medication names, directions, provider data, email, or birthday.
- [ ] Test offline use, sign-out, app relaunch, and account sync recovery.
- [ ] Confirm reinstall/sign-in restores only the data the user chose to sync.

## Platforms

- [ ] Build and run a signed iOS release on a real iPhone.
- [ ] Build an Android App Bundle with a private upload key.
- [ ] Install the Android release build from an internal Play testing track.
- [ ] Verify reminder mirroring and actions on a paired Apple Watch.
- [ ] If a watchOS companion target is added, test phone/Watch sync while either device is temporarily unreachable.
