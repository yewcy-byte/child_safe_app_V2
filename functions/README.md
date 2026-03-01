# Firebase Function: requestChildLocation

This folder contains the backend sender for silent FCM location requests.

## What it does

`requestChildLocation` is a callable function that:

1. Validates caller is authenticated.
2. Validates caller is the parent of `childId`.
3. Reads `users/{childId}.fcmToken`.
4. Writes `users/{childId}/systemRequests/locationRefresh` status `pending`.
5. Sends a high-priority, data-only FCM payload:
   - `command: GET_LOCATION`
   - `childId`
   - `requestId`
   - `requestedAt`

## Deploy steps

Run from project root:

```powershell
npm --prefix functions install
firebase login
firebase use child-safe-app-kita
firebase deploy --only functions:requestChildLocation
```

## Call from Flutter (parent app)

Use `cloud_functions` package and call:

- function name: `requestChildLocation`
- payload: `{ "childId": "<childUid>" }`

The child app then handles FCM and uploads location.

---

# Firebase Function: notifyParentOnScanRuntimeDown

This trigger sends a push notification to the parent when child scanning is expected to run but is detected as not running.

## Trigger path

`users/{childId}/systemHealth/scanRuntimeStatus`

The child app writes:
- `isRunning` (bool)
- `expectedRunning` (bool)
- `parentId` (string)
- `reason` (string)

If `expectedRunning == true` and `isRunning == false`, the function sends a parent FCM notification.

---

# Firebase Function: notifyParentOnScanHeartbeatMissing

This scheduled function is a fallback for silent child-app failures (app killed, process frozen, no status write).

## What it checks

- Runs every 2 minutes.
- Scans `users/{childId}/systemHealth/scanRuntimeStatus` docs where monitoring is expected.
- If `updatedAt` heartbeat is stale, sends a parent push (`scan_runtime_stale`).
- Uses `lastStaleAlertAt` cooldown to prevent spam.

This works together with the child app heartbeat write, which now updates scan runtime status even when state is unchanged.

## Deploy steps

```powershell
npm --prefix functions install
firebase login
firebase use child-safe-app-kita
firebase deploy --only functions:requestChildLocation,functions:notifyParentOnScanRuntimeDown,functions:notifyParentOnScanHeartbeatMissing
```
