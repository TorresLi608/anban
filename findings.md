# Findings

- App stores CareData as one encrypted snapshot; records are extensible string-field objects. `document` exists but its prior entry UI was removed.
- Existing photos capped at 9 per health record; new archive should use one document record per file, not the photo collection.
- VaultSync eagerly downloads/decrypts all attachments on login and rereads all on save; hard 20 MB/file and 100 MB total. Must refactor to lazy remote attachment loading and no total/count cap.
- LocalVault is in-memory encrypted Sembast. Account login/refresh currently restore a fully downloaded backup into a fresh vault.
- Backend file API accepts existing encrypted envelopes up to ~20 MB clear content, owner-scoped; chunking can reuse endpoint without exposing patient files.
- ReminderService schedules earliest 60 notifications on BOTH platforms, sequential numeric IDs, cancelAll before every replan; uses Android exactAllowWhileIdle with independent meal/water notifications even at identical times. Need trace overlapping alarms/channel behavior and platform limits.
- Existing PDF export and image/video/PDF preview can be reused. Unknown file types currently fall through to audio, which must be corrected.
- User confirmed single-file 200 MB cap; no per-folder/upload count cap.
- Android has no reason to share iOS's 60-item limit; frequent water slots can consume that queue before later meals. Plan Android daily repeating slots; iOS bounded scheduling with reserved category capacity and foreground refill watermark. Diagnose per-channel system disablement and display next times/test controls rather than claiming the user's device cause without evidence.
- Notification plugin already exposes channel inspection, daily recurrence and system notification settings; no new native dependency is needed.
- file_picker v13 exposes multiple PlatformFile selections; archive is already transitive. Need inspect streaming read/save APIs before choosing export and upload implementation.
- Emulator queue had 57 scheduled items (48 water, 9 meal). Meals were present; meal and water shared 18:00 exactly. Thus 60-item starvation is a real code flaw but not proven to be this device's sole cause. Co-timed daily alerts now combine their text; settings gain per-category next times, test notifications and blocked-channel diagnostics.
- FilePicker PlatformFile supports readAsByteStream; saving requires all bytes, so archive exports will need bounded ZIP volumes or native streaming support for large totals.
- New attachment path uses existing owner-scoped encrypted file endpoint with 4 MB AES-GCM chunks, one derived key per file, per-file/part AAD, lazy remote readers and local-stage cleanup only after snapshot commit. Large metadata manifests also chunk instead of enforcing an upload count cap.
- Need preserve session-only deleted-file references for undo; publishing must not clear the vault's remote-reference cache wholesale.
- Found another reminder-loss path: app startup refreshed an empty unauthenticated store, cancelling existing alarms before login. Removed this startup clear; explicit logout still clears reminders. Replanning now cancels pending requests only, preserving already-delivered notifications.
- Emulator notification dump showed both meal/water channels importance=HIGH with sound enabled and an existing meal notification. Channel blocking is not the emulator's observed cause; coincident/auto-grouped alerts and queue/display clearing remain the verified code/design issues addressed.
