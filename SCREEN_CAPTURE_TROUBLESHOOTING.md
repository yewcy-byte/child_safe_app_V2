# Screen Capture Troubleshooting Guide

## Issue: Screen scanning and NSFW detection not working on Vivo X70

This guide helps diagnose and fix screen capture issues, particularly on devices like Vivo X70.

## Common Issues on Vivo/Oppo/Realme Devices

These manufacturers (all under BBK Electronics) have aggressive security and permission systems that can interfere with screen capture:

### 1. **Media Projection Permission Not Granted**
**Symptoms:**
- App asks for screen recording permission but never starts capturing
- Logs show "mediaProjection is null"

**Solutions:**
- Grant the screen recording permission when prompted
- On Vivo: Go to Settings → Privacy → Permission Manager → Display over other apps → Enable for Child Safe
- On Vivo: Go to Settings → More Settings → Permission management → Auto-start management → Enable for Child Safe

### 2. **Background Restrictions**
**Symptoms:**
- Screen capture works initially but stops after a few minutes
- Virtual display becomes null

**Solutions:**
- Disable battery optimization for the app:
  - Settings → Battery → Background power consumption → Allow background activity for Child Safe
- Enable auto-start:
  - Settings → iManager → App Manager → Auto-start management → Enable for Child Safe

### 3. **Virtual Display Not Creating Images**
**Symptoms:**
- Permission granted, service running, but `captureScreen` returns null
- Logs show "No image available from ImageReader"

**Solutions:**
- This can be a hardware/manufacturer limitation
- Try restarting the device
- Update to the latest FunTouch OS/Origin OS version
- Some Vivo models have restrictions on media projection in certain modes (Game Mode, Ultra Power Saving)

### 4. **NSFW Model Not Loading**
**Symptoms:**
- Screen captures work but NSFW detection returns 0.0
- Logs show NSFW initialization errors

**Solutions:**
- Check if `nsfw.tflite` file exists in assets folder
- Ensure sufficient storage space
- Check if app has storage permissions

## Using the Diagnostic Tool

A diagnostic tool has been added to help identify issues:

1. Open the app and log in as a child
2. Navigate to the **Help** tab
3. Scroll down and tap **"Open Diagnostic Tool"**
4. Tap **"Run Full Diagnostic"**

The tool will test each component:
1. Media projection permission
2. Screen capture service
3. Screen capture functionality
4. NSFW model initialization
5. NSFW detection

Review the logs to identify where the failure occurs.

## Step-by-Step Manual Testing

If the full diagnostic doesn't work, test each component individually:

### Step 1: Test Media Projection Permission
```
Tap "1. Request Media Projection"
```
- ✅ Expected: Permission dialog appears, then "Media projection permission granted"
- ❌ If failed: Check device settings for screen recording permissions

### Step 2: Test Screen Service
```
Tap "2. Start Screen Service"
```
- ✅ Expected: "Service started", "MediaProjection obtained: true"
- ❌ If failed: Grant permission in Step 1 first

### Step 3: Test Screen Capture
```
Tap "3. Capture Screen"
```
- ✅ Expected: "Screen captured", "File exists", image preview shown
- ❌ If failed: 
  - "captureScreen returned null" → Virtual display issue (see solutions above)
  - "File does not exist" → Storage permission issue

### Step 4: Test NSFW Model
```
Tap "4. Initialize NSFW Model"
```
- ✅ Expected: "NSFW service initialized"
- ❌ If failed: Check storage and model file

### Step 5: Test Detection
```
Tap "5. Test NSFW Detection"
```
- ✅ Expected: "NSFW score: [number]"
- ❌ If failed: Run step 3 and 4 first

## Viewing Android Logs

For more detailed debugging:

```bash
# In terminal, run:
flutter run

# Or view Android logs directly:
adb logcat | grep "MainActivity\|_performScan"
```

Look for messages tagged with:
- `MainActivity` - Native Android logs
- `_performScan` - Flutter scan process logs

## Vivo-Specific Settings to Check

1. **iManager → App Manager**
   - White list for high background power consumption
   - Auto-start management
   - Lock in recent tasks

2. **Settings → Privacy → Permission Manager**
   - Display over other apps: ✅ Enabled
   - Modify system settings: ✅ Enabled
   - Access notification: ✅ Enabled (if needed)

3. **Settings → Battery**
   - Background power consumption: ✅ Allow
   - Do not optimize: ✅ Child Safe app

4. **Settings → More Settings → Accessibility**
   - Enable accessibility service for the app

## Known Limitations

### Vivo X70 Specific
- Some Vivo X70 units have firmware restrictions on media projection
- FunTouch OS 12+ has stricter media projection policies
- May not work in certain screen modes (Game Mode, Eye Protection Mode)

### Workarounds
If screen capture absolutely doesn't work:
1. Try on a different device for comparison
2. Check Vivo community forums for device-specific solutions
3. Consider using alternative monitoring methods (accessibility service only)

## Getting Help

If issues persist after trying all solutions:

1. **Save diagnostic logs**:
   - Run full diagnostic
   - Take a screenshot of the logs
   
2. **Check Android version**:
   - Settings → About phone → Android version
   - Settings → About phone → Software version (FunTouch OS)

3. **Report issue with**:
   - Device model (Vivo X70)
   - Android version
   - FunTouch OS version
   - Diagnostic logs screenshot
   - Description of exact behavior

## Technical Details

### How Screen Capture Works

1. **Request Permission**: `MediaProjectionCreator.createMediaProjection()`
2. **Create Service**: Start foreground service with MEDIA_PROJECTION type
3. **Setup Virtual Display**: Create ImageReader and VirtualDisplay
4. **Capture Frames**: Acquire images from ImageReader
5. **Process**: Save as JPEG, run through NSFW TFLite model
6. **React**: Show warning shield if inappropriate content detected

### Why It Might Fail on Vivo

- **Step 3 (Virtual Display)**: Some Vivo ROMs restrict virtual displays for security
- **Step 4 (Capture)**: ImageReader may not receive frames due to hardware restrictions
- **Background Service**: Vivo aggressively kills background services

## Updates

**2026-02-18**:
- Added comprehensive logging to MainActivity
- Created diagnostic tool page
- Fixed `firstTimeStamp` compilation error in UsageTrackingService
- Improved error handling and fallback mechanisms
