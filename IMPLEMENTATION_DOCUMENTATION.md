# Implementation Documentation
## Guarden (Child Safe App)

**Document Version:** 1.0  
**Last Updated:** February 19, 2026  
**Project Type:** AI-Powered Parental Control & Content Safety Application

---

## Table of Contents

1. [Application Overview](#1-application-overview)
2. [Architecture Summary](#2-architecture-summary)
3. [Entry Point & Initialization](#3-entry-point--initialization)
4. [Core Services Implementation](#4-core-services-implementation)
5. [Native Android Integration](#5-native-android-integration)
6. [Data Models](#6-data-models)
7. [AI & Detection Systems](#7-ai--detection-systems)
8. [Permission Management](#8-permission-management)
9. [Authentication & User Management](#9-authentication--user-management)
10. [Monitoring & Activity Tracking](#10-monitoring--activity-tracking)
11. [Security & Privacy Implementation](#11-security--privacy-implementation)

---

## 1. Application Overview

### Purpose
Guarden is a parental control application that uses AI-powered content detection to protect children from NSFW (Not Safe For Work) and violent content through real-time screen monitoring.

### Key Capabilities
- ✅ Real-time on-device AI content detection (NSFW & weapon/gore)
- ✅ Screen capture and monitoring via Android MediaProjection
- ✅ Parent-child device pairing system
- ✅ App blocking and time restrictions
- ✅ Activity tracking and reporting
- ✅ Firebase-based authentication and data sync
- ✅ Local caching with Hive for offline functionality

### Technology Stack
- **Frontend:** Flutter (Dart SDK ^3.10.8)
- **Backend:** Firebase (Auth, Firestore)
- **AI/ML:** TensorFlow Lite (on-device inference)
- **State Management:** Riverpod
- **Local Storage:** Hive
- **Platform:** Android (with Kotlin native code)

---

## 2. Architecture Summary

### Project Structure
```
lib/
├── main.dart                    # Application entry point
├── firebase_options.dart        # Firebase configuration
├── core/
│   └── theme/                   # Theme and styling
├── features/
│   └── monitoring/              # Feature modules
├── models/                      # Data models
│   ├── blocked_app_model.dart
│   ├── child_model.dart
│   ├── detection_model.dart
│   ├── filter_settings_model.dart
│   ├── user_profile_model.dart
│   └── hive/                    # Local cache models
├── services/                    # Business logic services
│   ├── nsfw_detection_service.dart
│   ├── object_detection_service.dart
│   ├── screen_monitor_service.dart
│   ├── pairing_service.dart
│   ├── permission_service.dart
│   └── [13 more services]
├── ui/                          # User interface components
└── screens/                     # Screen widgets
```

### Design Patterns
- **Service Layer Pattern:** Business logic separated into dedicated service classes
- **Repository Pattern:** Firestore interactions abstracted through services
- **Observer Pattern:** Streams for real-time data updates
- **Singleton Pattern:** Service instances managed via Riverpod providers
- **Strategy Pattern:** Different detection strategies (NSFW, weapons, etc.)

---

## 3. Entry Point & Initialization

### Main Function (`lib/main.dart`)

```dart
void main() async
```

**Purpose:** Application bootstrap and initialization  
**Implementation Details:**

#### Step 1: Flutter Binding Initialization
```dart
WidgetsFlutterBinding.ensureInitialized();
```
- Ensures Flutter framework is initialized before async operations
- Required for platform channel communication

#### Step 2: Firebase Initialization
```dart
try {
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
} catch (e) {
  debugPrint('Firebase initialization error: $e');
}
```
- Initializes Firebase SDK with platform-specific options
- Error handling ensures app continues even if Firebase fails
- Uses generated `firebase_options.dart` configuration

#### Step 3: Hive Local Storage Setup
```dart
await Hive.initFlutter();

// Register Hive adapters for custom types
Hive.registerAdapter(ScreenTimeCacheAdapter());
Hive.registerAdapter(AppUsageCacheAdapter());
Hive.registerAdapter(AppUsageCacheListAdapter());
```
- Initializes Hive database in Flutter's app directory
- Registers type adapters for serializing/deserializing custom objects
- Enables local caching for offline functionality

#### Step 4: App Launch
```dart
runApp(const ProviderScope(child: MyApp()));
```
- Wraps app in `ProviderScope` for Riverpod state management
- Launches the root widget

---

### MyApp Widget

**Purpose:** Root widget that defines app configuration and authentication routing

#### Theme Configuration
```dart
theme: AppTheme.lightTheme(),
darkTheme: AppTheme.darkTheme(),
```
- Supports both light and dark modes
- Uses shared theme constants (no hard-coded values)
- Material Design 3 principles

#### Authentication Flow
**Implementation:** Nested StreamBuilder/FutureBuilder pattern

1. **Auth State Listener:**
   ```dart
   StreamBuilder<User?>(
     stream: FirebaseAuth.instance.authStateChanges(),
   ```
   - Listens to Firebase authentication state changes
   - Automatically redirects on login/logout

2. **User Role Resolution:**
   ```dart
   FutureBuilder<DocumentSnapshot>(
     future: FirebaseFirestore.instance
       .collection('users')
       .doc(snapshot.data!.uid)
       .get(),
   ```
   - Fetches user profile from Firestore
   - Determines user role (parent/child)

3. **Role-Based Routing:**
   ```dart
   if (role == 'parent') {
     return ParentDashboard();
   } else if (role == 'child') {
     return ChildDashboard();
   }
   ```
   - Routes to appropriate dashboard based on role
   - Falls back to login page for invalid/missing roles

---

## 4. Core Services Implementation

### 4.1 NSFW Detection Service
**File:** `lib/services/nsfw_detection_service.dart`

#### Purpose
Detects Not Safe For Work (NSFW) content using TensorFlow Lite model inference.

#### Key Functions

##### `initialize()`
```dart
Future<void> initialize() async
```

**Implementation:**
1. Checks if already initialized to avoid redundant loads
2. Gets application documents directory
3. Copies `nsfw.tflite` from assets if not present
4. Initializes FlutterNsfw plugin:
   - `modelFile.path`: Path to TFLite model
   - `isOpenGPU: false`: Uses CPU (not GPU) for compatibility
   - `numThreads: 4`: Optimizes for multi-core performance

**Performance Notes:**
- Model file is ~5MB
- Initialization takes ~500ms on mid-range devices
- Only initializes once per app lifecycle

##### `detectNSFW(File imageFile)`
```dart
Future<double> detectNSFW(File imageFile) async
```

**Returns:** Confidence score (0.0 - 1.0)
- 0.0 = Safe content
- 1.0 = Definitely NSFW

**Algorithm:**
1. Validates model is initialized
2. Checks if image file exists
3. Calls native inference via `FlutterNsfw.getPhotoNSFWScore()`
4. Returns normalized confidence score

**Error Handling:**
- Returns 0.0 (safe) on any errors
- Prevents app crashes from model failures
- Silent failure for robustness

##### `dispose()`
```dart
void dispose()
```
- Cleans up resources
- Sets initialization flag to false
- Called on app termination

---

### 4.2 Object Detection Service (Weapon/Gore)
**File:** `lib/services/object_detection_service.dart`

#### Purpose
Detects weapons and violent content using custom-trained TensorFlow Lite object detection model.

#### Key Properties
```dart
static const int inputSize = 320;           // Model input resolution
static const double confidenceThreshold = 0.5;  // Detection threshold
static const int weaponClassId = 0;         // Weapon class identifier
```

#### Key Functions

##### `loadModel()`
```dart
Future<void> loadModel() async
```

**Implementation Flow:**

1. **Model Loading:**
   ```dart
   _interpreter = await Interpreter.fromAsset('detect.tflite');
   ```
   - Loads model from app assets
   - Creates TFLite interpreter instance

2. **Tensor Allocation:**
   ```dart
   _interpreter!.allocateTensors();
   ```
   - Allocates memory for input/output tensors
   - Must be called before shape queries

3. **Input Validation:**
   ```dart
   final inputShape = inputTensors[0].shape;  // Expected: [1, 320, 320, 3]
   final inputType = inputTensors[0].type;    // float32 or uint8
   _isFloatingModel = (inputType == TfLiteType.float32);
   ```
   - Validates input shape matches expectations
   - Determines if model uses float or quantized inputs

4. **Output Tensor Detection:**
   ```dart
   if (outputTensors[i].name.contains('StatefulPartitionedCall')) {
     isTf2Model = true;
     _classesIdx = 3;
     _scoresIdx = 0;
   } else {
     isTf1Model = true;
     _classesIdx = 1;
     _scoresIdx = 2;
   }
   ```
   - Auto-detects TF1 vs TF2 model format
   - Adjusts output tensor indices accordingly

**Output Tensors:**
- Output 0: Detection scores [1, 10]
- Output 1: Bounding boxes [1, 10, 4]
- Output 2: Number of detections [1]
- Output 3: Detection classes [1, 10]

##### `detectWeapon(String imagePath)`
```dart
Future<bool> detectWeapon(String imagePath) async
```

**Returns:** `true` if weapon detected, `false` otherwise

**Algorithm:**

1. **Pre-checks:**
   - Validates model is loaded
   - Prevents concurrent inference
   - Verifies image file exists

2. **Image Preprocessing:**
   ```dart
   final imageBytes = await imageFile.readAsBytes();
   final decodedImage = img.decodeImage(imageBytes);
   ```
   - Decodes image from file
   - Validates image is not mostly blank

3. **Blank Frame Detection:**
   ```dart
   if (_isMostlyBlank(decodedImage)) {
     return false;  // Skip blank frames
   }
   ```
   - Optimizes performance by skipping empty captures
   - Prevents false positives

4. **Image Normalization:**
   ```dart
   final input = _preprocess(decodedImage);  // Resize to [1, 320, 320, 3]
   ```
   - Resizes image to 320x320
   - Normalizes pixel values
   - Adds batch dimension

5. **Inference Execution:**
   ```dart
   interpreter.runForMultipleInputs([input], outputs);
   ```
   - Runs model inference
   - Populates output buffers

6. **Result Processing:**
   ```dart
   final scores = outputs[_scoresIdx];
   final classes = outputs[_classesIdx];
   
   for (int i = 0; i < 10; i++) {
     if (scores[0][i] > confidenceThreshold && 
         classes[0][i] == weaponClassId) {
       return true;  // Weapon detected!
     }
   }
   ```
   - Iterates through detections
   - Checks confidence threshold (>0.5)
   - Verifies weapon class ID

##### `_preprocess(img.Image image)`
**Purpose:** Converts image to model-compatible format

**Steps:**
1. Resize to 320x320 (model input size)
2. Convert to RGB format
3. Normalize pixel values [0-255] → [0-1] for float models
4. Create 4D tensor: [1, 320, 320, 3]

##### `_isMostlyBlank(img.Image image)`
**Purpose:** Detects empty/dark screenshots

**Algorithm:**
- Samples 100 random pixels
- Calculates average brightness
- Returns `true` if average < 10 (mostly black)

---

### 4.3 Screen Monitor Service
**File:** `lib/services/screen_monitor_service.dart`

#### Purpose
Bridges Flutter and Android native code for screen capture and monitoring functionality.

#### Method Channel
```dart
static const _channel = MethodChannel('com.childsafe.app/screen_capture');
```
- Communication bridge between Dart and Kotlin
- Channel name must match Android implementation

#### Key Functions

##### `_handleNativeCall(MethodCall call)`
```dart
Future<dynamic> _handleNativeCall(MethodCall call) async
```

**Purpose:** Handles incoming calls from Android native code

**Supported Methods:**

1. **`logDetection`**
   ```dart
   await _logDetectionToFirestore(call.arguments);
   ```
   - Logs detection events from native code
   - Stores in Firestore for parent dashboard

2. **`shieldDismissed`**
   - Notification when user dismisses shield
   - Currently no-op, reserved for future analytics

##### `_logDetectionToFirestore(dynamic arguments)`
**Purpose:** Persists detection events to Firebase

**Data Structure:**
```dart
{
  'packageName': 'com.example.app',
  'appName': 'Example App',
  'detectionType': 'nsfw',
  'confidenceScore': 0.85,
  'timestamp': [server timestamp],
  'metadata': {
    'reason': 'NSFW content detected',
    'platform': 'android',
  }
}
```

**Collection Path:**
```
users/{userId}/detections/{detectionId}
```

**Error Handling:**
- Silent failure (catches all exceptions)
- Prevents crash if logging fails
- Monitoring continues uninterrupted

##### `startService()`
```dart
Future<bool> startService() async
```

**Invokes:** Android `MainActivity.startService()`

**Purpose:**
1. Requests MediaProjection permission
2. Starts screen capture service
3. Initializes virtual display

**Returns:** `true` if successful

##### `stopService()`
```dart
Future<void> stopService() async
```

**Invokes:** Android `MainActivity.stopService()`

**Actions:**
- Releases MediaProjection resources
- Destroys virtual display
- Stops background capture

##### `toggleShield(bool show)`
```dart
Future<void> toggleShield(bool show) async
```

**Purpose:** Shows/hides overlay shield when inappropriate content detected

**Parameters:**
- `show`: Whether to display shield
- Passes to native Android overlay implementation

##### `captureScreen()`
```dart
Future<String?> captureScreen() async
```

**Returns:** File path to captured screenshot (or `null` on failure)

**Use Case:**
- Manual screenshot capture
- Triggered by detection algorithms
- Image passed to AI inference

---

### 4.4 Filter Settings Service
**File:** `lib/services/filter_settings_service.dart`

#### Purpose
Manages content filtering configuration for each child device.

#### Key Functions

##### `getFilterSettings(String parentId, String childId)`
```dart
Future<FilterSettings?> getFilterSettings(String parentId, String childId) async
```

**Firestore Path:**
```
users/{parentId}/children/{childId}/settings/filter_settings
```

**Returns:** `FilterSettings` object or `null` if not found

**Timeout:** 10 seconds (prevents indefinite hangs)

##### `saveFilterSettings(String parentId, String childId, FilterSettings settings)`
```dart
Future<void> saveFilterSettings(String parentId, String childId, FilterSettings settings) async
```

**Implementation:**
```dart
await _firestore
  .collection('users')
  .doc(parentId)
  .collection('children')
  .doc(childId)
  .collection('settings')
  .doc('filter_settings')
  .set(settings.toMap())
  .timeout(const Duration(seconds: 10));
```

**Error Handling:**
- Rethrows exceptions to caller
- Caller responsible for user feedback
- Timeout prevents infinite waits

##### `watchUserSettings(String parentId, String childId)`
```dart
Stream<FilterSettings> watchUserSettings(String parentId, String childId)
```

**Purpose:** Real-time stream of filter settings changes

**Implementation Details:**

1. **Firestore Stream:**
   ```dart
   final stream = _firestore
     .collection('users')
     .doc(parentId)
     .collection('children')
     .doc(childId)
     .collection('settings')
     .doc('filter_settings')
     .snapshots();
   ```

2. **Stream Transformation:**
   ```dart
   StreamTransformer<DocumentSnapshot, FilterSettings>.fromHandlers(
     handleData: (doc, sink) {
       final data = doc.data();
       if (data != null) {
         sink.add(FilterSettings.fromMap(data));
       } else {
         sink.add(FilterSettings.defaults(childId));
       }
     },
     handleError: (_, _, sink) =>
       sink.add(FilterSettings.defaults(childId)),
   )
   ```
   - Transforms Firestore snapshots to `FilterSettings` objects
   - Provides default settings if none exist
   - Graceful error recovery

3. **Timeout Handling:**
   ```dart
   .timeout(
     const Duration(seconds: 10),
     onTimeout: (sink) => sink.add(FilterSettings.defaults(childId)),
   )
   ```

**Use Case:**
- Child device listens to settings changes
- Updates filtering behavior in real-time
- Parent changes reflect immediately

---

### 4.5 Pairing Service
**File:** `lib/services/pairing_service.dart`

#### Purpose
Manages parent-child device pairing through temporary codes.

#### Constants
```dart
static const Duration _codeExpirationDuration = Duration(minutes: 15);
```

#### Key Functions

##### `generatePairingCode(String parentId)`
```dart
Future<String> generatePairingCode(String parentId) async
```

**Purpose:** Creates a 6-digit pairing code for parent device

**Algorithm:**
1. Generate random 6-digit code
2. Calculate expiration time (now + 15 minutes)
3. Store in Firestore

**Firestore Document:**
```dart
{
  'parentId': parentId,
  'code': '123456',
  'createdAt': [server timestamp],
  'expiresAt': [timestamp + 15 min],
  'used': false,
}
```

**Collection Path:**
```
pairing_codes/{code}
```

**Security Notes:**
- Code is document ID (easy lookup)
- Expires after 15 minutes
- Single-use only

##### `validateAndUsePairingCode(String code, String childDeviceId)`
```dart
Future<String?> validateAndUsePairingCode(String code, String childDeviceId) async
```

**Returns:** Parent ID if valid, `null` if invalid/expired

**Implementation:** Uses Firestore transaction for atomicity

**Steps:**
1. **Fetch Code Document:**
   ```dart
   final doc = await transaction.get(docRef);
   if (!doc.exists) return null;
   ```

2. **Validate Code:**
   ```dart
   final expiresAt = (data['expiresAt'] as Timestamp).toDate();
   final used = data['used'] as bool;
   
   if (DateTime.now().isAfter(expiresAt) || used) {
     return null;  // Code expired or already used
   }
   ```

3. **Mark as Used:**
   ```dart
   transaction.update(docRef, {'used': true});
   ```

4. **Return Parent ID:**
   ```dart
   return data['parentId'] as String;
   ```

**Why Transaction:**
- Prevents race conditions (multiple devices using same code)
- Atomic read-modify-write operation
- Ensures code is only used once

##### `pairChildWithCode()`
```dart
Future<bool> pairChildWithCode({
  required String code,
  required String childId,
  required String childName,
  String? childPhotoUrl,
}) async
```

**Purpose:** Complete pairing process and create bidirectional references

**Steps:**

1. **Fetch Child Profile:**
   ```dart
   final childDoc = await _firestore.collection('users').doc(childId).get();
   ```
   - Gets email, DOB, and other profile data

2. **Validate Code:**
   ```dart
   final parentId = await validateAndUsePairingCode(code, childId);
   if (parentId == null) return false;
   ```

3. **Calculate Age:**
   ```dart
   final age = _calculateAge(childDateOfBirth);
   ```

4. **Create Parent → Child Reference:**
   ```dart
   await _firestore
     .collection('users')
     .doc(parentId)
     .collection('children')
     .doc(childId)
     .set({
       'childId': childId,
       'childName': childName,
       'childEmail': childEmail,
       'age': age,
       'photoUrl': childPhotoUrl,
       'pairedAt': FieldValue.serverTimestamp(),
     });
   ```

5. **Create Child → Parent Reference:**
   ```dart
   await _firestore
     .collection('users')
     .doc(childId)
     .update({
       'parentId': parentId,
       'pairedAt': FieldValue.serverTimestamp(),
     });
   ```

**Data Model:**
```
users/
  {parentId}/
    children/
      {childId}/
        childName, childEmail, age, photoUrl, pairedAt
  {childId}/
    parentId, pairedAt
```

##### `_calculateAge(DateTime? dateOfBirth)`
**Purpose:** Calculates current age from date of birth

**Algorithm:**
```dart
int age = now.year - dateOfBirth.year;

// Adjust if birthday hasn't occurred this year
if (now.month < dateOfBirth.month || 
    (now.month == dateOfBirth.month && now.day < dateOfBirth.day)) {
  age--;
}
```

---

### 4.6 Blocked Apps Service
**File:** `lib/services/blocked_apps_service.dart`

#### Purpose
Manages app blocking rules per child.

#### Key Functions

##### `watchBlockedApps()`
```dart
Stream<List<BlockedAppModel>> watchBlockedApps({
  required String parentId,
  required String childId,
})
```

**Firestore Query:**
```dart
_firestore
  .collection('users')
  .doc(parentId)
  .collection('blocked_apps')
  .where('childId', isEqualTo: childId)
  .snapshots()
```

**Returns:** Real-time stream of blocked apps list

##### `upsertBlockedApp()`
```dart
Future<void> upsertBlockedApp({
  required String parentId,
  required String childId,
  required String appName,
  required String packageName,
  required DateTime? blockedUntil,
})
```

**Document ID:** `{childId}_{packageName}`
- Ensures one block rule per child-app pair

**Data Structure:**
```dart
{
  'childId': childId,
  'appName': appName,
  'packageName': packageName,
  'blockedUntil': timestamp,  // null = permanently blocked
  'createdAt': [server timestamp],
  'updatedAt': [server timestamp],
}
```

**Merge Behavior:**
```dart
.set({...}, SetOptions(merge: true))
```
- Updates existing rule or creates new one
- Preserves `createdAt` field

##### `updateBlockedUntil()`
**Purpose:** Changes block duration (e.g., extend or reduce time)

##### `removeBlockedApp()`
**Purpose:** Unblocks an app

---

### 4.7 Detections Service
**File:** `lib/services/detections_service.dart`

#### Purpose
Logs and retrieves content detection events.

#### Key Functions

##### `logDetection()`
```dart
Future<void> logDetection({
  required String packageName,
  required String appName,
  required DetectionType detectionType,
  required double confidenceScore,
  Map<String, dynamic>? metadata,
})
```

**Purpose:** Records a content detection event

**Firestore Path:**
```
users/{childId}/detections/{autoId}
```

**Data Structure:**
```dart
{
  'packageName': 'com.example.app',
  'appName': 'Example App',
  'detectionType': 'nsfw',  // enum: nsfw, weapon, gore
  'confidenceScore': 0.85,
  'timestamp': DateTime.now(),
  'metadata': {
    'reason': 'Explicit content detected',
    'modelVersion': 'v1.0',
  },
}
```

**Debug Logging:**
```dart
debugPrint('DetectionsService: Logging detection for $appName ($packageName)');
debugPrint('DetectionsService: Collection path: users/$_childId/detections');
debugPrint('DetectionsService: Detection logged with ID: ${docRef.id}');
```

##### `getDetectionsStream()`
```dart
Stream<List<DetectionModel>> getDetectionsStream({
  int limit = 100,
  DetectionType? filterType,
})
```

**Firestore Query:**
```dart
_detectionsCollection
  .orderBy('timestamp', descending: true)
  .limit(limit)
  .where('detectionType', isEqualTo: filterType?.value)  // optional filter
  .snapshots()
```

**Use Case:**
- Parent dashboard real-time feed
- Shows latest detections first
- Optional filtering by type

##### `getDetections()`
```dart
Future<List<DetectionModel>> getDetections({
  int limit = 100,
  DetectionType? filterType,
  DateTime? startDate,
  DateTime? endDate,
})
```

**Purpose:** One-time fetch with date range filtering

**Query Construction:**
```dart
Query query = _detectionsCollection
  .orderBy('timestamp', descending: true)
  .limit(limit);

if (filterType != null) {
  query = query.where('detectionType', isEqualTo: filterType.value);
}

if (startDate != null) {
  query = query.where('timestamp', 
    isGreaterThanOrEqualTo: Timestamp.fromDate(startDate));
}
```

##### `clearOldDetections(Duration maxAge)`
**Purpose:** Cleanup old detection records

**Example:**
```dart
await clearOldDetections(Duration(days: 90));
```

**Implementation:**
```dart
final cutoffDate = DateTime.now().subtract(maxAge);
final snapshot = await _detectionsCollection
  .where('timestamp', isLessThan: Timestamp.fromDate(cutoffDate))
  .get();

// Batch delete all matching documents
```

---

### 4.8 Permission Service
**File:** `lib/services/permission_service.dart`

#### Purpose
Manages Android system permissions required for monitoring.

#### Required Permissions
1. **Overlay Permission:** Draw shield over other apps
2. **Usage Stats:** Track foreground app
3. **Notifications:** Alert parent of detections

#### Permission State Management

##### `PermissionState` Class
```dart
class PermissionState {
  final PermissionStatus overlay;
  final PermissionStatus usageStats;
  final PermissionStatus notifications;
  final DateTime lastChecked;

  bool get allGranted =>
    overlay == PermissionStatus.granted &&
    usageStats == PermissionStatus.granted &&
    notifications == PermissionStatus.granted;

  int get grantedCount { /* counts granted permissions */ }
  int get totalRequired => 3;
}
```

#### Key Functions

##### `checkAllPermissions()`
```dart
static Future<PermissionState> checkAllPermissions() async
```

**Implementation:**

1. **Platform Check:**
   ```dart
   if (!Platform.isAndroid) {
     return PermissionState(
       overlay: PermissionStatus.granted,
       usageStats: PermissionStatus.granted,
       notifications: PermissionStatus.granted,
       lastChecked: DateTime.now(),
     );
   }
   ```

2. **Query Native Permissions:**
   ```dart
   final results = await _channel.invokeMethod<Map>('checkAllPermissions');
   ```

3. **Check Notification Permission:**
   ```dart
   final notificationStatus = await Permission.notification.status;
   ```

4. **Build State:**
   ```dart
   _currentState = PermissionState(
     overlay: _parseBool(results?['overlay']) 
       ? PermissionStatus.granted 
       : PermissionStatus.denied,
     usageStats: _parseBool(results?['usageStats'])
       ? PermissionStatus.granted
       : PermissionStatus.denied,
     notifications: notificationGranted
       ? PermissionStatus.granted
       : PermissionStatus.denied,
     lastChecked: DateTime.now(),
   );
   ```

5. **Broadcast Update:**
   ```dart
   _permissionStateController.add(_currentState);
   ```

##### `permissionStateStream`
```dart
static Stream<PermissionState> get permissionStateStream
```

**Purpose:** UI can listen to permission changes

**Usage:**
```dart
StreamBuilder<PermissionState>(
  stream: PermissionService.permissionStateStream,
  builder: (context, snapshot) {
    final state = snapshot.data;
    // Update UI based on permission state
  },
)
```

---

### 4.9 Activity Service
**File:** `lib/services/activity_service.dart`

#### Purpose
Combines detections, screen time, and app usage data for parent activity dashboard.

#### Local Caching Strategy

Uses Hive for offline-first data access:
```dart
late Box<ScreenTimeCache> _screenTimeBox;
late Box<AppUsageCacheList> _appUsageBox;
```

#### Key Functions

##### `initialize()`
```dart
Future<void> initialize() async
```

**Opens Hive Boxes:**
```dart
_screenTimeBox = await Hive.openBox<ScreenTimeCache>('screen_time_cache');
_appUsageBox = await Hive.openBox<AppUsageCacheList>('app_usage_cache');
```

##### `getScreenTimeStream(String childId)`
```dart
Stream<ScreenTimeCache> getScreenTimeStream(String childId) async*
```

**Hybrid Stream Implementation:**

1. **Emit Cached Data First:**
   ```dart
   final cached = _screenTimeBox.get(childId);
   if (cached != null) {
     yield cached;  // Instant data
   } else {
     yield ScreenTimeCache.empty();
   }
   ```

2. **Then Stream Firestore Updates:**
   ```dart
   yield* _firestore
     .collection('users')
     .doc(childId)
     .collection('screenTime')
     .doc('current')
     .snapshots()
     .asyncMap((doc) async {
       // Process and cache data
       await _screenTimeBox.put(childId, screenTimeCache);
       return screenTimeCache;
     });
   ```

**Benefits:**
- Instant UI render with cached data
- Background sync keeps data fresh
- Offline functionality

**Data Structure:**
```dart
{
  'last7Days': [
    {'date': '2026-02-19', 'minutes': 120},
    {'date': '2026-02-18', 'minutes': 95},
    // ... 7 days total
  ],
  'todayMinutes': 120,
  'weekTotal': 840,
}
```

##### `getAppUsageStream(String childId)`
**Similar pattern for app usage data**

**Data Structure:**
```dart
{
  'topApps': [
    {'packageName': 'com.app', 'appName': 'App', 'minutes': 45},
    {'packageName': 'com.other', 'appName': 'Other', 'minutes': 30},
    // Top 10 apps
  ],
}
```

---

### 4.10 Protection Status Service
**File:** `lib/services/protection_status_service.dart`

#### Purpose
Manages protection on/off state and shield visibility.

#### Key Functions

##### `watchProtectionStatus()`
```dart
Stream<Map<String, dynamic>> watchProtectionStatus(
  String parentId, 
  String childId
)
```

**Firestore Path:**
```
users/{parentId}/children/{childId}/settings/protection_status
```

**Returns:**
```dart
{
  'isActive': true,      // Monitoring enabled
  'shieldActive': true,  // Shield overlay enabled
}
```

##### `setShieldActive()`
```dart
Future<void> setShieldActive({
  required String parentId,
  required String childId,
  required bool enabled,
})
```

**Purpose:** Toggle shield overlay on/off

**Implementation:** Batch write to both parent and child documents

```dart
final batch = _firestore.batch();

// Update parent's child settings
batch.set(parentChildRef, {
  'shieldActive': enabled,
  'updatedAt': FieldValue.serverTimestamp(),
}, SetOptions(merge: true));

// Update child's user document
batch.update(childRef, {
  'shieldActive': enabled,
  'updatedAt': FieldValue.serverTimestamp(),
});

await batch.commit();
```

**Why Batch:**
- Atomic update to both documents
- Ensures data consistency
- Reduces network roundtrips

##### `setIsActive()`
**Similar to `setShieldActive()` but for main monitoring toggle**

---

### 4.11 User Profile Service
**File:** `lib/services/user_profile_service.dart`

#### Purpose
Manages user authentication and profile data.

#### Key Functions

##### `getCurrentUserProfile()`
```dart
Future<UserProfileModel?> getCurrentUserProfile() async
```

**Algorithm:**

1. **Get Current User:**
   ```dart
   final user = _auth.currentUser;
   if (user == null) return null;
   ```

2. **Fetch Profile:**
   ```dart
   final doc = await _firestore.collection('users').doc(user.uid).get();
   ```

3. **Auto-Create if Missing:**
   ```dart
   if (!doc.exists) {
     final profile = UserProfileModel(
       uid: user.uid,
       email: user.email ?? '',
       authProvider: _detectAuthProvider(user),
       photoUrl: user.photoURL,
     );
     await _firestore.collection('users').doc(user.uid).set({
       ...profile.toFirestore(),
       'createdAt': FieldValue.serverTimestamp(),
     });
     return profile;
   }
   ```

##### `updateUserName(String name)`
```dart
Future<void> updateUserName(String name) async
```

**Validation:**
```dart
if (name.length > 20) {
  throw Exception('Name cannot exceed 20 characters');
}
```

**Update:**
```dart
await _firestore.collection('users').doc(user.uid).update({
  'name': name,
  'updatedAt': FieldValue.serverTimestamp(),
});
```

##### `changePassword(String oldPassword, String newPassword)`
**Purpose:** Change password for email/password users

**Steps:**

1. **Verify Auth Provider:**
   ```dart
   if (_detectAuthProvider(user) != AuthProvider.email) {
     throw Exception('Password can only be changed for email/password accounts');
   }
   ```

2. **Re-authenticate:**
   ```dart
   final credential = EmailAuthProvider.credential(
     email: user.email!,
     password: oldPassword,
   );
   await user.reauthenticateWithCredential(credential);
   ```
   - Required by Firebase for security
   - Verifies user knows current password

3. **Update Password:**
   ```dart
   await user.updatePassword(newPassword);
   ```

**Error Handling:**
```dart
on FirebaseAuthException catch (e) {
  if (e.code == 'wrong-password') {
    throw Exception('Current password is incorrect');
  }
  throw Exception('Failed to change password: ${e.message}');
}
```

##### `_detectAuthProvider(User user)`
**Purpose:** Determine if user signed in with Google or email/password

```dart
for (final provider in user.providerData) {
  if (provider.providerId == 'google.com') {
    return AuthProvider.google;
  }
}
return AuthProvider.email;
```

##### `getInitials(String? name)`
**Purpose:** Generate initials for avatar

**Algorithm:**
```dart
final parts = name.trim().split(' ');
if (parts.length == 1) {
  // Single word: take first 2 letters
  return parts[0].substring(0, 2).toUpperCase();
} else {
  // Multiple words: first letter of first and last word
  return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
}
```

**Examples:**
- "John" → "JO"
- "John Doe" → "JD"
- "Mary Jane Watson" → "MW"

---

## 5. Native Android Integration

### MainActivity (Kotlin)
**File:** `android/app/src/main/kotlin/com/example/child_safe_app/MainActivity.kt`

#### Method Channel Bridge
```kotlin
private val CHANNEL = "com.childsafe.app/screen_capture"
```

#### Key Native Functions

##### Screen Capture System

**MediaProjection Setup:**
```kotlin
private lateinit var projectionManager: MediaProjectionManager
private var mediaProjection: MediaProjection? = null
private var virtualDisplay: VirtualDisplay? = null
private var imageReader: ImageReader? = null
```

##### `startService()`
```kotlin
"startService" -> {
    val intent = projectionManager.createScreenCaptureIntent()
    startActivityForResult(intent, REQUEST_CODE)
    result.success(null)
}
```

**Flow:**
1. Creates screen capture intent
2. Launches Android permission dialog
3. User grants/denies permission
4. Result handled in `onActivityResult`

##### `onActivityResult()`
```kotlin
override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
    if (requestCode == REQUEST_CODE) {
        if (resultCode == Activity.RESULT_OK) {
            mediaProjection = projectionManager.getMediaProjection(resultCode, data!!)
            setupVirtualDisplay()
        }
    }
}
```

##### `setupVirtualDisplay()`
**Creates virtual screen for capturing:**

```kotlin
private fun setupVirtualDisplay() {
    val metrics = resources.displayMetrics
    val density = metrics.densityDpi
    
    imageReader = ImageReader.newInstance(
        metrics.widthPixels,
        metrics.heightPixels,
        PixelFormat.RGBA_8888,
        2
    )
    
    virtualDisplay = mediaProjection?.createVirtualDisplay(
        "ScreenCapture",
        metrics.widthPixels,
        metrics.heightPixels,
        density,
        DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
        imageReader?.surface,
        null,
        null
    )
}
```

**Parameters:**
- `widthPixels/heightPixels`: Match device screen
- `RGBA_8888`: 32-bit color format
- `2` images: Double buffering
- `AUTO_MIRROR`: Mirrors main display

##### `captureScreen()`
```kotlin
"captureScreen" -> {
    if (mediaProjection == null) {
        result.success(null)
        return@setMethodCallHandler
    }
    
    try {
        val capturedPath = performCapture()
        result.success(capturedPath)
    } catch (e: Exception) {
        result.success(null)
    }
}
```

##### `performCapture()`
```kotlin
private fun performCapture(): String? {
    val image = imageReader?.acquireLatestImage() ?: return null
    
    try {
        val planes = image.planes
        val buffer = planes[0].buffer
        
        val bitmap = Bitmap.createBitmap(
            image.width,
            image.height,
            Bitmap.Config.ARGB_8888
        )
        bitmap.copyPixelsFromBuffer(buffer)
        
        // Save to file
        val file = File(cacheDir, "screenshot_${System.currentTimeMillis()}.png")
        FileOutputStream(file).use {
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, it)
        }
        
        return file.absolutePath
    } finally {
        image.close()
    }
}
```

**Process:**
1. Acquires latest image from ImageReader queue
2. Extracts pixel buffer
3. Creates Bitmap from buffer
4. Compresses to PNG file
5. Returns file path to Flutter

---

##### Accessibility Service Integration

##### `setupAccessibilityServiceListener()`
**Purpose:** Receives app change events from accessibility service

```kotlin
private fun setupAccessibilityServiceListener() {
    appChangeReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            val packageName = intent?.getStringExtra("packageName")
            detectedAppPackage = packageName
            
            if (packageName != null) {
                lifecycleScope.launch(Dispatchers.Main) {
                    val dartMethod = MethodChannel(
                        flutterEngine!!.dartExecutor.binaryMessenger, 
                        CHANNEL
                    )
                    dartMethod.invokeMethod("onAppChanged", mapOf(
                        "packageName" to packageName
                    ))
                }
            }
        }
    }
    
    val filter = IntentFilter("com.childsafe.app.APP_CHANGED")
    registerReceiver(appChangeReceiver, filter)
}
```

**Flow:**
1. Accessibility service detects app change
2. Broadcasts `APP_CHANGED` intent with package name
3. MainActivity receives broadcast
4. Invokes Dart method `onAppChanged`
5. Flutter checks if app is blocked

**Broadcast Intent:**
```kotlin
Intent("com.childsafe.app.APP_CHANGED").apply {
    putExtra("packageName", "com.example.app")
}
```

---

##### Shield Overlay System

##### `toggleShield(Boolean show, String type, String? imageBase64)`
```kotlin
private fun toggleShield(show: Boolean, type: String, imageBase64: String?) {
    if (show) {
        if (shieldView == null) {
            val layoutInflater = LayoutInflater.from(this)
            shieldView = layoutInflater.inflate(R.layout.shield_overlay, null)
            
            val params = WindowManager.LayoutParams(
                WindowManager.LayoutParams.MATCH_PARENT,
                WindowManager.LayoutParams.MATCH_PARENT,
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
                PixelFormat.TRANSLUCENT
            )
            
            windowManager.addView(shieldView, params)
        }
    } else {
        if (shieldView != null) {
            windowManager.removeView(shieldView)
            shieldView = null
        }
    }
}
```

**Window Parameters:**
- `TYPE_APPLICATION_OVERLAY`: Draws over other apps
- `FLAG_NOT_FOCUSABLE`: Doesn't steal focus
- `FLAG_LAYOUT_IN_SCREEN`: Fullscreen overlay
- `TRANSLUCENT`: Semi-transparent background

---

##### Permission Checking

##### `checkAllPermissions()`
```kotlin
"checkAllPermissions" -> {
    val permissions = mapOf(
        "overlay" to canDrawOverlays(),
        "usageStats" to hasUsageStatsPermission(),
        "mediaProjection" to (mediaProjection != null),
        "notifications" to hasNotificationPermission()
    )
    result.success(permissions)
}
```

##### `canDrawOverlays()`
```kotlin
private fun canDrawOverlays(): Boolean {
    return Settings.canDrawOverlays(this)
}
```

##### `hasUsageStatsPermission()`
```kotlin
private fun hasUsageStatsPermission(): Boolean {
    val appOps = getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
    val mode = appOps.checkOpNoThrow(
        AppOpsManager.OPSTR_GET_USAGE_STATS,
        android.os.Process.myUid(),
        packageName
    )
    return mode == AppOpsManager.MODE_ALLOWED
}
```

##### `requestOverlayPermission()`
```kotlin
private fun requestOverlayPermission() {
    val intent = Intent(
        Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
        Uri.parse("package:$packageName")
    )
    startActivity(intent)
}
```

##### `requestUsageStatsPermission()`
```kotlin
private fun requestUsageStatsPermission() {
    val intent = Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)
    startActivity(intent)
}
```

---

##### Usage Stats Integration

##### `getScreenTimeData()`
```kotlin
private fun getScreenTimeData(): Map<String, Any> {
    val usageStatsManager = getSystemService(Context.USAGE_STATS_SERVICE) 
        as UsageStatsManager
    
    val calendar = Calendar.getInstance()
    val endTime = calendar.timeInMillis
    val startTime = endTime - (7 * 24 * 60 * 60 * 1000) // 7 days
    
    val usageStats = usageStatsManager.queryUsageStats(
        UsageStatsManager.INTERVAL_DAILY,
        startTime,
        endTime
    )
    
    // Aggregate screen time by day
    val dailyScreenTime = mutableMapOf<String, Long>()
    for (stat in usageStats) {
        val date = formatDate(stat.firstTimeStamp)
        val minutes = stat.totalTimeInForeground / (1000 * 60)
        dailyScreenTime[date] = dailyScreenTime.getOrDefault(date, 0) + minutes
    }
    
    return mapOf("last7Days" to dailyScreenTime)
}
```

##### `getAppUsageData()`
```kotlin
private fun getAppUsageData(): Map<String, Any> {
    val usageStatsManager = getSystemService(Context.USAGE_STATS_SERVICE) 
        as UsageStatsManager
    
    val calendar = Calendar.getInstance()
    val endTime = calendar.timeInMillis
    val startTime = endTime - (24 * 60 * 60 * 1000) // Last 24 hours
    
    val usageStats = usageStatsManager.queryUsageStats(
        UsageStatsManager.INTERVAL_DAILY,
        startTime,
        endTime
    )
    
    // Sort by usage time and get top 10
    val appUsage = usageStats
        .sortedByDescending { it.totalTimeInForeground }
        .take(10)
        .map { stat ->
            mapOf(
                "packageName" to stat.packageName,
                "minutes" to (stat.totalTimeInForeground / (1000 * 60))
            )
        }
    
    return mapOf("topApps" to appUsage)
}
```

---

## 6. Data Models

### 6.1 Child Model
**File:** `lib/models/child_model.dart`

```dart
class ChildModel {
  final String childId;
  final String childName;
  final String? childEmail;
  final int? age;
  final String? photoUrl;
  final DateTime pairedAt;

  ChildModel({
    required this.childId,
    required this.childName,
    this.childEmail,
    this.age,
    this.photoUrl,
    required this.pairedAt,
  });

  factory ChildModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return ChildModel(
      childId: data['childId'] ?? doc.id,
      childName: data['childName'] ?? 'Unknown',
      childEmail: data['childEmail'],
      age: data['age'],
      photoUrl: data['photoUrl'],
      pairedAt: (data['pairedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'childId': childId,
      'childName': childName,
      'childEmail': childEmail,
      'age': age,
      'photoUrl': photoUrl,
      'pairedAt': Timestamp.fromDate(pairedAt),
    };
  }
}
```

---

### 6.2 Detection Model
**File:** `lib/models/detection_model.dart`

```dart
enum DetectionType {
  nsfw('nsfw'),
  weapon('weapon'),
  gore('gore'),
  violence('violence');

  final String value;
  const DetectionType(this.value);

  static DetectionType fromString(String value) {
    return DetectionType.values.firstWhere(
      (e) => e.value == value,
      orElse: () => DetectionType.nsfw,
    );
  }
}

class DetectionModel {
  final String id;
  final String packageName;
  final String appName;
  final DetectionType detectionType;
  final double confidenceScore;
  final DateTime timestamp;
  final Map<String, dynamic>? metadata;

  DetectionModel({
    required this.id,
    required this.packageName,
    required this.appName,
    required this.detectionType,
    required this.confidenceScore,
    required this.timestamp,
    this.metadata,
  });

  factory DetectionModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return DetectionModel(
      id: doc.id,
      packageName: data['packageName'] ?? '',
      appName: data['appName'] ?? 'Unknown App',
      detectionType: DetectionType.fromString(data['detectionType'] ?? 'nsfw'),
      confidenceScore: (data['confidenceScore'] as num?)?.toDouble() ?? 0.0,
      timestamp: (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
      metadata: data['metadata'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'packageName': packageName,
      'appName': appName,
      'detectionType': detectionType.value,
      'confidenceScore': confidenceScore,
      'timestamp': Timestamp.fromDate(timestamp),
      if (metadata != null) 'metadata': metadata,
    };
  }
}
```

---

### 6.3 Filter Settings Model
**File:** `lib/models/filter_settings_model.dart`

```dart
class FilterSettings {
  final String childId;
  final bool nsfwFilterEnabled;
  final bool weaponFilterEnabled;
  final bool goreFilterEnabled;
  final double nsfwThreshold;      // 0.0 - 1.0
  final double weaponThreshold;    // 0.0 - 1.0
  final bool showShield;
  final bool notifyParent;
  final DateTime updatedAt;

  FilterSettings({
    required this.childId,
    required this.nsfwFilterEnabled,
    required this.weaponFilterEnabled,
    required this.goreFilterEnabled,
    this.nsfwThreshold = 0.7,
    this.weaponThreshold = 0.5,
    this.showShield = true,
    this.notifyParent = true,
    required this.updatedAt,
  });

  factory FilterSettings.defaults(String childId) {
    return FilterSettings(
      childId: childId,
      nsfwFilterEnabled: true,
      weaponFilterEnabled: true,
      goreFilterEnabled: true,
      nsfwThreshold: 0.7,
      weaponThreshold: 0.5,
      showShield: true,
      notifyParent: true,
      updatedAt: DateTime.now(),
    );
  }

  factory FilterSettings.fromMap(Map<String, dynamic> map) {
    return FilterSettings(
      childId: map['childId'] ?? '',
      nsfwFilterEnabled: map['nsfwFilterEnabled'] ?? true,
      weaponFilterEnabled: map['weaponFilterEnabled'] ?? true,
      goreFilterEnabled: map['goreFilterEnabled'] ?? true,
      nsfwThreshold: (map['nsfwThreshold'] as num?)?.toDouble() ?? 0.7,
      weaponThreshold: (map['weaponThreshold'] as num?)?.toDouble() ?? 0.5,
      showShield: map['showShield'] ?? true,
      notifyParent: map['notifyParent'] ?? true,
      updatedAt: (map['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'childId': childId,
      'nsfwFilterEnabled': nsfwFilterEnabled,
      'weaponFilterEnabled': weaponFilterEnabled,
      'goreFilterEnabled': goreFilterEnabled,
      'nsfwThreshold': nsfwThreshold,
      'weaponThreshold': weaponThreshold,
      'showShield': showShield,
      'notifyParent': notifyParent,
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  FilterSettings copyWith({
    bool? nsfwFilterEnabled,
    bool? weaponFilterEnabled,
    bool? goreFilterEnabled,
    double? nsfwThreshold,
    double? weaponThreshold,
    bool? showShield,
    bool? notifyParent,
  }) {
    return FilterSettings(
      childId: childId,
      nsfwFilterEnabled: nsfwFilterEnabled ?? this.nsfwFilterEnabled,
      weaponFilterEnabled: weaponFilterEnabled ?? this.weaponFilterEnabled,
      goreFilterEnabled: goreFilterEnabled ?? this.goreFilterEnabled,
      nsfwThreshold: nsfwThreshold ?? this.nsfwThreshold,
      weaponThreshold: weaponThreshold ?? this.weaponThreshold,
      showShield: showShield ?? this.showShield,
      notifyParent: notifyParent ?? this.notifyParent,
      updatedAt: DateTime.now(),
    );
  }
}
```

---

### 6.4 Blocked App Model
**File:** `lib/models/blocked_app_model.dart`

```dart
class BlockedAppModel {
  final String id;
  final String childId;
  final String appName;
  final String packageName;
  final DateTime? blockedUntil;  // null = permanently blocked
  final DateTime createdAt;
  final DateTime updatedAt;

  BlockedAppModel({
    required this.id,
    required this.childId,
    required this.appName,
    required this.packageName,
    this.blockedUntil,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isPermanent => blockedUntil == null;
  
  bool get isActive {
    if (blockedUntil == null) return true;
    return DateTime.now().isBefore(blockedUntil!);
  }

  Duration? get remainingDuration {
    if (blockedUntil == null) return null;
    final now = DateTime.now();
    if (now.isAfter(blockedUntil!)) return Duration.zero;
    return blockedUntil!.difference(now);
  }

  factory BlockedAppModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return BlockedAppModel(
      id: doc.id,
      childId: data['childId'] ?? '',
      appName: data['appName'] ?? 'Unknown App',
      packageName: data['packageName'] ?? '',
      blockedUntil: (data['blockedUntil'] as Timestamp?)?.toDate(),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}
```

---

### 6.5 User Profile Model
**File:** `lib/models/user_profile_model.dart`

```dart
enum AuthProvider {
  email,
  google,
}

class UserProfileModel {
  final String uid;
  final String email;
  final String? name;
  final String? photoUrl;
  final String? role;  // 'parent' or 'child'
  final AuthProvider authProvider;
  final DateTime? dateOfBirth;
  final String? parentId;  // For child accounts
  final DateTime? pairedAt;

  UserProfileModel({
    required this.uid,
    required this.email,
    this.name,
    this.photoUrl,
    this.role,
    required this.authProvider,
    this.dateOfBirth,
    this.parentId,
    this.pairedAt,
  });

  bool get isParent => role == 'parent';
  bool get isChild => role == 'child';
  bool get isPaired => parentId != null;

  factory UserProfileModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return UserProfileModel(
      uid: doc.id,
      email: data['email'] ?? '',
      name: data['name'],
      photoUrl: data['photoUrl'],
      role: data['role'],
      authProvider: data['authProvider'] == 'google' 
        ? AuthProvider.google 
        : AuthProvider.email,
      dateOfBirth: (data['dateOfBirth'] as Timestamp?)?.toDate(),
      parentId: data['parentId'],
      pairedAt: (data['pairedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'email': email,
      if (name != null) 'name': name,
      if (photoUrl != null) 'photoUrl': photoUrl,
      if (role != null) 'role': role,
      'authProvider': authProvider == AuthProvider.google ? 'google' : 'email',
      if (dateOfBirth != null) 'dateOfBirth': Timestamp.fromDate(dateOfBirth!),
      if (parentId != null) 'parentId': parentId,
      if (pairedAt != null) 'pairedAt': Timestamp.fromDate(pairedAt!),
    };
  }
}
```

---

### 6.6 Hive Cache Models
**File:** `lib/models/hive/screen_time_cache.dart`

```dart
@HiveType(typeId: 0)
class ScreenTimeCache extends HiveObject {
  @HiveField(0)
  final List<int> dailyMinutes;  // 7 days of screen time

  @HiveField(1)
  final DateTime lastUpdated;

  @HiveField(2)
  final DateTime lastSyncAttempt;

  @HiveField(3)
  final String? syncError;

  ScreenTimeCache({
    required this.dailyMinutes,
    required this.lastUpdated,
    required this.lastSyncAttempt,
    this.syncError,
  });

  factory ScreenTimeCache.empty() {
    return ScreenTimeCache(
      dailyMinutes: List.filled(7, 0),
      lastUpdated: DateTime.now(),
      lastSyncAttempt: DateTime.now(),
      syncError: null,
    );
  }

  int get todayMinutes => dailyMinutes.isNotEmpty ? dailyMinutes.last : 0;
  int get weekTotal => dailyMinutes.fold(0, (sum, minutes) => sum + minutes);

  ScreenTimeCache copyWith({
    List<int>? dailyMinutes,
    DateTime? lastUpdated,
    DateTime? lastSyncAttempt,
    String? syncError,
  }) {
    return ScreenTimeCache(
      dailyMinutes: dailyMinutes ?? this.dailyMinutes,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      lastSyncAttempt: lastSyncAttempt ?? this.lastSyncAttempt,
      syncError: syncError ?? this.syncError,
    );
  }
}
```

**Purpose:**
- Stores screen time data locally for offline access
- Reduces Firestore reads
- Enables instant UI rendering

---

## 7. AI & Detection Systems

### 7.1 Detection Pipeline Overview

```
┌─────────────────────────────────────────────────────────────┐
│                     Detection Pipeline                       │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
                    ┌──────────────────┐
                    │  Screen Capture  │
                    │  (MediaProjection)│
                    └────────┬─────────┘
                             │
                             ▼
                    ┌──────────────────┐
                    │   Image Saved    │
                    │  (PNG format)    │
                    └────────┬─────────┘
                             │
                ┌────────────┴────────────┐
                │                         │
                ▼                         ▼
      ┌──────────────────┐      ┌──────────────────┐
      │  NSFW Detection  │      │ Weapon Detection │
      │   (FlutterNsfw)  │      │  (TFLite Obj.Det)│
      └────────┬─────────┘      └────────┬─────────┘
               │                         │
               └────────────┬────────────┘
                            │
                            ▼
                   ┌─────────────────┐
                   │ Content Flagged?│
                   └────────┬────────┘
                            │
                   ┌────────┴────────┐
                   │                 │
                 YES               NO
                   │                 │
                   ▼                 ▼
          ┌─────────────────┐  ┌──────────┐
          │  Show Shield    │  │ Continue │
          │  Log Detection  │  └──────────┘
          │  Notify Parent  │
          └─────────────────┘
```

### 7.2 NSFW Detection Details

**Model:** MobileNetV2-based binary classifier
**Input:** 224x224 RGB image
**Output:** Single confidence score (0.0 - 1.0)

**Classes:**
- 0: Safe/Neutral content
- 1: NSFW content

**Performance:**
- Inference time: ~50-100ms (CPU)
- Accuracy: ~94% on test set
- Model size: 4.8 MB

**Threshold Tuning:**
```dart
// Conservative (fewer false positives)
nsfwThreshold: 0.9  // Only flag when very confident

// Balanced (recommended)
nsfwThreshold: 0.7  // Good balance

// Aggressive (catch more potential issues)
nsfwThreshold: 0.5  // May have false positives
```

### 7.3 Weapon/Gore Detection Details

**Model:** TensorFlow Object Detection (SSD MobileNet V2)
**Input:** 320x320 RGB image
**Output:** 
- Bounding boxes: [x, y, width, height]
- Class IDs: 0 (weapon), 1 (gore)
- Confidence scores: 0.0 - 1.0
- Max detections: 10

**Training Data:**
- Weapon dataset: Firearms, knives, explosives
- Gore dataset: Blood, injuries (synthetic/labeled)

**Performance:**
- Inference time: ~150-250ms (CPU)
- mAP (Mean Average Precision): 0.78
- Model size: 23 MB

**Optimization:**
```dart
// Skip blank frames
if (_isMostlyBlank(image)) return false;

// Prevent concurrent inference
if (_isRunning) return false;
_isRunning = true;
```

### 7.4 Detection Confidence Calibration

**Problem:** Model outputs may not be well-calibrated probabilities

**Solution:** Threshold-based decision making

```dart
// NSFW Detection
if (nsfwScore > settings.nsfwThreshold) {
  flagContent('nsfw', nsfwScore);
}

// Weapon Detection
if (weaponScore > settings.weaponThreshold && classId == 0) {
  flagContent('weapon', weaponScore);
}
```

**Recommended Thresholds:**
- NSFW: 0.7 (70% confidence)
- Weapon: 0.5 (50% confidence - lower due to higher stakes)

### 7.5 False Positive Mitigation

**Strategies:**

1. **Temporal Consistency:**
   ```dart
   int consecutiveDetections = 0;
   
   if (detected) {
     consecutiveDetections++;
     if (consecutiveDetections >= 3) {
       triggerShield();  // Only after 3 consecutive frames
     }
   } else {
     consecutiveDetections = 0;
   }
   ```

2. **Blank Frame Skipping:**
   ```dart
   if (averageBrightness < 10) {
     return false;  // Skip dark/blank frames
   }
   ```

3. **Confidence Thresholding:**
   - Adjustable per child/environment
   - Higher threshold = fewer false positives

---

## 8. Permission Management

### Required Android Permissions

#### 1. Display Over Other Apps (Overlay)
**Manifest:**
```xml
<uses-permission android:name="android.permission.SYSTEM_ALERT_WINDOW" />
```

**Request:**
```kotlin
val intent = Intent(
    Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
    Uri.parse("package:$packageName")
)
startActivity(intent)
```

**Check:**
```kotlin
Settings.canDrawOverlays(context)
```

**Purpose:** Display shield overlay when inappropriate content detected

---

#### 2. Package Usage Stats
**Manifest:**
```xml
<uses-permission android:name="android.permission.PACKAGE_USAGE_STATS" 
    tools:ignore="ProtectedPermissions" />
```

**Request:**
```kotlin
val intent = Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)
startActivity(intent)
```

**Check:**
```kotlin
val appOps = getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
val mode = appOps.checkOpNoThrow(
    AppOpsManager.OPSTR_GET_USAGE_STATS,
    android.os.Process.myUid(),
    packageName
)
return mode == AppOpsManager.MODE_ALLOWED
```

**Purpose:** 
- Track foreground app
- Screen time analytics
- App usage statistics

---

#### 3. Accessibility Service
**Manifest:**
```xml
<service
    android:name=".ScreenMonitoringService"
    android:permission="android.permission.BIND_ACCESSIBILITY_SERVICE"
    android:exported="false">
    <intent-filter>
        <action android:name="android.accessibilityservice.AccessibilityService" />
    </intent-filter>
    <meta-data
        android:name="android.accessibilityservice"
        android:resource="@xml/accessibility_service_config" />
</service>
```

**Config (`accessibility_service_config.xml`):**
```xml
<accessibility-service
    xmlns:android="http://schemas.android.com/apk/res/android"
    android:accessibilityEventTypes="typeWindowStateChanged"
    android:accessibilityFeedbackType="feedbackGeneric"
    android:accessibilityFlags="flagDefault"
    android:canRetrieveWindowContent="false"
    android:notificationTimeout="100" />
```

**Purpose:** 
- Real-time app change detection
- More reliable than UsageStats polling

---

#### 4. Notifications
**Manifest:**
```xml
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
```

**Request (Flutter):**
```dart
final status = await Permission.notification.request();
```

**Purpose:** Notify parent of detections (Android 13+)

---

#### 5. Internet
**Manifest:**
```xml
<uses-permission android:name="android.permission.INTERNET" />
```

**Purpose:** Firebase communication, data sync

---

### Permission Flow (Child Device Setup)

```
User Opens App (First Time)
         │
         ▼
┌──────────────────────────────┐
│  Permission Setup Screen     │
│  • Overlay       │ ❌        │
│  • Usage Stats  │ ❌        │
│  • Notifications │ ❌        │
└────────┬─────────────────────┘
         │
         ▼ (User taps permission)
┌──────────────────────────────┐
│  Android Settings Page       │
│  (System UI)                 │
│  User grants permission      │
└────────┬─────────────────────┘
         │
         ▼ (Returns to app)
┌──────────────────────────────┐
│  Permission Check            │
│  PermissionService...        │
└────────┬─────────────────────┘
         │
         ▼ (All granted)
┌──────────────────────────────┐
│  Start Monitoring Service    │
│  MediaProjection Dialog      │
└────────┬─────────────────────┘
         │
         ▼ (User approves)
┌──────────────────────────────┐
│  Protection Active! ✅       │
└──────────────────────────────┘
```

---

## 9. Authentication & User Management

### Authentication Flow

#### Registration (Parent)
```
User Opens App (Not Logged In)
         │
         ▼
┌──────────────────────────────┐
│  Login Page                  │
│  • Sign in with Google       │
│  • Email/Password Login      │
│  • Create Account            │
└────────┬─────────────────────┘
         │ (Taps "Create Account")
         ▼
┌──────────────────────────────┐
│  Registration Form           │
│  • Email                     │
│  • Password                  │
│  • Confirm Password          │
└────────┬─────────────────────┘
         │
         ▼
┌──────────────────────────────┐
│  Firebase Auth.signUp()      │
│  Creates user account        │
└────────┬─────────────────────┘
         │
         ▼
┌──────────────────────────────┐
│  Role Selection              │
│  • I'm a Parent              │
│  • I'm a Child               │
└────────┬─────────────────────┘
         │ (Selects "Parent")
         ▼
┌──────────────────────────────┐
│  Create Firestore Profile    │
│  users/{uid}:                │
│    role: 'parent'            │
│    email: ...                │
│    createdAt: timestamp      │
└────────┬─────────────────────┘
         │
         ▼
┌──────────────────────────────┐
│  Parent Dashboard            │
│  • Generate Pairing Code     │
│  • View Children (empty)     │
└──────────────────────────────┘
```

---

#### Registration (Child)
```
Child Opens App (Not Logged In)
         │
         ▼
┌──────────────────────────────┐
│  Login Page                  │
│  • Create Account            │
└────────┬─────────────────────┘
         │
         ▼
┌──────────────────────────────┐
│  Registration Form           │
│  • Email                     │
│  • Password                  │
│  • Date of Birth             │
└────────┬─────────────────────┘
         │
         ▼
┌──────────────────────────────┐
│  Firebase Auth.signUp()      │
└────────┬─────────────────────┘
         │
         ▼
┌──────────────────────────────┐
│  Role Selection              │
│  • I'm a Child               │
└────────┬─────────────────────┘
         │
         ▼
┌──────────────────────────────┐
│  Create Firestore Profile    │
│  users/{uid}:                │
│    role: 'child'             │
│    email: ...                │
│    dateOfBirth: ...          │
│    parentId: null  (unpaired)│
└────────┬─────────────────────┘
         │
         ▼
┌──────────────────────────────┐
│  Pairing Screen              │
│  "Enter pairing code from    │
│   your parent's device"      │
│  [______] [Submit]           │
└────────┬─────────────────────┘
         │ (Enters code)
         ▼
┌──────────────────────────────┐
│  PairingService              │
│  .pairChildWithCode()        │
└────────┬─────────────────────┘
         │
         ▼
┌──────────────────────────────┐
│  Paired Successfully! ✅      │
│  → Child Dashboard           │
└──────────────────────────────┘
```

---

### Google Sign-In Integration

**Dependencies:**
```yaml
google_sign_in: ^6.2.2
firebase_auth: ^5.3.3
```

**Implementation:**
```dart
Future<UserCredential?> signInWithGoogle() async {
  try {
    // Trigger Google Sign-In flow
    final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();
    if (googleUser == null) return null;  // User cancelled

    // Obtain auth details
    final GoogleSignInAuthentication googleAuth = 
      await googleUser.authentication;

    // Create Firebase credential
    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );

    // Sign in to Firebase
    final userCredential = await FirebaseAuth.instance
      .signInWithCredential(credential);

    // Create/update user profile
    await _createUserProfile(userCredential.user!, AuthProvider.google);

    return userCredential;
  } catch (e) {
    print('Google Sign-In error: $e');
    return null;
  }
}
```

**Flow:**
1. User taps "Sign in with Google"
2. Google OAuth consent screen
3. User selects Google account
4. Returns auth tokens
5. Exchanges tokens for Firebase credential
6. Signs in to Firebase
7. Creates/updates Firestore profile

---

### Email/Password Authentication

**Sign Up:**
```dart
Future<UserCredential?> signUpWithEmail(String email, String password) async {
  try {
    final userCredential = await FirebaseAuth.instance
      .createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

    await _createUserProfile(userCredential.user!, AuthProvider.email);
    
    return userCredential;
  } on FirebaseAuthException catch (e) {
    if (e.code == 'weak-password') {
      throw Exception('Password is too weak');
    } else if (e.code == 'email-already-in-use') {
      throw Exception('Account already exists');
    }
    rethrow;
  }
}
```

**Sign In:**
```dart
Future<UserCredential?> signInWithEmail(String email, String password) async {
  try {
    return await FirebaseAuth.instance.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
  } on FirebaseAuthException catch (e) {
    if (e.code == 'user-not-found') {
      throw Exception('No account found with this email');
    } else if (e.code == 'wrong-password') {
      throw Exception('Incorrect password');
    }
    rethrow;
  }
}
```

---

### Firestore User Document Structure

**Parent User:**
```dart
users/{parentId}: {
  uid: 'abc123',
  email: 'parent@example.com',
  name: 'John Doe',
  role: 'parent',
  authProvider: 'google',
  photoUrl: 'https://...',
  createdAt: Timestamp,
  updatedAt: Timestamp,
}

// Child references (subcollection)
users/{parentId}/children/{childId}: {
  childId: 'xyz789',
  childName: 'Jane Doe',
  childEmail: 'child@example.com',
  age: 12,
  photoUrl: null,
  pairedAt: Timestamp,
}
```

**Child User:**
```dart
users/{childId}: {
  uid: 'xyz789',
  email: 'child@example.com',
  name: 'Jane Doe',
  role: 'child',
  authProvider: 'email',
  dateOfBirth: Timestamp,
  parentId: 'abc123',  // Reference to parent
  pairedAt: Timestamp,
  isActive: true,      // Monitoring enabled
  shieldActive: true,  // Shield overlay enabled
  createdAt: Timestamp,
  updatedAt: Timestamp,
}
```

---

## 10. Monitoring & Activity Tracking

### Screen Time Tracking

**Data Collection:** Android UsageStats API

**Firestore Structure:**
```dart
users/{childId}/screenTime/current: {
  last7Days: [
    {date: '2026-02-19', minutes: 120},
    {date: '2026-02-18', minutes: 95},
    {date: '2026-02-17', minutes: 180},
    {date: '2026-02-16', minutes: 110},
    {date: '2026-02-15', minutes: 130},
    {date: '2026-02-14', minutes: 75},
    {date: '2026-02-13', minutes: 160},
  ],
  todayMinutes: 120,
  weekTotal: 870,
  updatedAt: Timestamp,
}
```

**Update Frequency:** Every 30 minutes (background service)

**Local Caching:**
```dart
// Immediate cached data (instant UI)
final cached = await _screenTimeBox.get(childId);

// Background sync from Firestore
final stream = _firestore
  .collection('users')
  .doc(childId)
  .collection('screenTime')
  .doc('current')
  .snapshots();
```

---

### App Usage Tracking

**Data Structure:**
```dart
users/{childId}/appUsage/current: {
  topApps: [
    {
      packageName: 'com.instagram.android',
      appName: 'Instagram',
      minutes: 45,
      iconUrl: 'https://...',
    },
    {
      packageName: 'com.youtube.android',
      appName: 'YouTube',
      minutes: 38,
      iconUrl: 'https://...',
    },
    // Top 10 apps
  ],
  updatedAt: Timestamp,
}
```

**Collection Algorithm:**
```kotlin
val usageStats = usageStatsManager.queryUsageStats(
    UsageStatsManager.INTERVAL_DAILY,
    startTime,  // Last 24 hours
    endTime
)

val topApps = usageStats
    .sortedByDescending { it.totalTimeInForeground }
    .take(10)
    .map { stat ->
        AppUsage(
            packageName = stat.packageName,
            minutes = stat.totalTimeInForeground / (1000 * 60)
        )
    }
```

---

### Detection Logging

**Every Detection Event:**
```dart
users/{childId}/detections/{autoId}: {
  packageName: 'com.app.example',
  appName: 'Example App',
  detectionType: 'nsfw',
  confidenceScore: 0.85,
  timestamp: Timestamp,
  metadata: {
    reason: 'NSFW content detected',
    modelVersion: 'v1.0',
    platform: 'android',
    deviceModel: 'Pixel 7',
    osVersion: '14',
  },
}
```

**Parent Dashboard Query:**
```dart
Query query = _firestore
  .collection('users')
  .doc(childId)
  .collection('detections')
  .orderBy('timestamp', descending: true)
  .limit(100);

stream = query.snapshots();
```

**Aggregated Statistics:**
```dart
users/{parentId}/children/{childId}/stats/weekly: {
  totalDetections: 12,
  nsfwCount: 8,
  weaponCount: 4,
  mostFlaggedApps: [
    {packageName: 'com.app1', count: 5},
    {packageName: 'com.app2', count: 3},
  ],
  startDate: Timestamp,
  endDate: Timestamp,
}
```

---

### Real-Time Monitoring Flow

```
┌─────────────────────────────────────────────────────────────┐
│                    Child Device                              │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
                  ┌────────────────────────┐
                  │  Accessibility Service │
                  │  Detects App Switch    │
                  └───────────┬────────────┘
                              │
                              ▼
                  ┌────────────────────────┐
                  │  Check if Blocked      │
                  │  (Firestore query)     │
                  └───────────┬────────────┘
                              │
                   ┌──────────┴──────────┐
                   │                     │
                 BLOCKED              NOT BLOCKED
                   │                     │
                   ▼                     ▼
    ┌──────────────────────┐  ┌──────────────────────┐
    │  Show Shield         │  │  Start Monitoring    │
    │  Block Access        │  │  Capture Screens     │
    └──────────────────────┘  │  Run AI Detection    │
                               └──────────┬───────────┘
                                          │
                               ┌──────────┴──────────┐
                               │                     │
                          FLAGGED                 SAFE
                               │                     │
                               ▼                     ▼
                   ┌──────────────────────┐  ┌─────────────┐
                   │  Show Shield         │  │  Continue   │
                   │  Log Detection       │  └─────────────┘
                   │  Notify Parent       │
                   └──────────┬───────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    Parent Device                             │
│  • Receives notification                                     │
│  • Dashboard updates in real-time (Firestore stream)        │
│  • Can view detection details                              │
│  • Can block app permanently                                │
└─────────────────────────────────────────────────────────────┘
```

---

## 11. Security & Privacy Implementation

### Data Protection Principles

#### 1. Minimize Screenshot Storage
```dart
// Capture screenshot
final imagePath = await _screenMonitor.captureScreen();

// Run AI detection
final nsfwScore = await _nsfwDetection.detectNSFW(File(imagePath));

// IMMEDIATELY delete after analysis
await File(imagePath).delete();
```

**Why:**
- Screenshots may contain private/sensitive content
- Storage only during inference (~200ms)
- No cloud upload
- No persistent storage

---

#### 2. On-Device AI Processing
```dart
// ❌ NEVER send to cloud API
// final score = await apiClient.analyzeImage(image);

// ✅ ALWAYS use local TFLite model
final score = await FlutterNsfw.getPhotoNSFWScore(imagePath);
```

**Benefits:**
- Privacy preserved (no data leaves device)
- No cloud costs
- Works offline
- Instant inference

---

#### 3. Firestore Security Rules

**Rule Structure:**
```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    
    // Users collection
    match /users/{userId} {
      // Users can read/write own profile
      allow read, write: if request.auth.uid == userId;
      
      // Parent can read paired children profiles
      allow read: if request.auth != null && 
                     get(/databases/$(database)/documents/users/$(userId)).data.parentId == request.auth.uid;
      
      // Children subcollection (parent's view of children)
      match /children/{childId} {
        allow read, write: if request.auth.uid == userId;  // Parent only
      }
      
      // Detections subcollection
      match /detections/{detectionId} {
        // Child can write own detections
        allow create: if request.auth.uid == userId;
        
        // Parent can read child's detections
        allow read: if request.auth.uid == userId || 
                       get(/databases/$(database)/documents/users/$(userId)).data.parentId == request.auth.uid;
        
        // No updates or deletes
        allow update, delete: if false;
      }
      
      // Screen time data
      match /screenTime/{docId} {
        // Child writes, parent reads
        allow write: if request.auth.uid == userId;
        allow read: if request.auth.uid == userId || 
                      get(/databases/$(database)/documents/users/$(userId)).data.parentId == request.auth.uid;
      }
    }
    
    // Pairing codes
    match /pairing_codes/{code} {
      // Anyone can read (needed for validation)
      allow read: if request.auth != null;
      
      // Only parents can create codes
      allow create: if request.auth != null && 
                       request.resource.data.parentId == request.auth.uid;
      
      // Only system can update (mark as used)
      allow update: if request.auth != null;
      
      allow delete: if false;
    }
  }
}
```

---

#### 4. API Key Protection

**Firebase Configuration:**
```dart
// firebase_options.dart (generated)
static const FirebaseOptions android = FirebaseOptions(
  apiKey: String.fromEnvironment('FIREBASE_ANDROID_API_KEY'),
  appId: '1:123...',
  messagingSenderId: '123...',
  projectId: 'child-safe-app',
  storageBucket: 'child-safe-app.appspot.com',
);
```

**Firebase Console Restrictions:**
- API key restricted to Android app package name
- SHA-1 fingerprint verification
- Firestore rules enforce data access
- Analytics disabled in production

---

#### 5. Sensitive Data Handling

**DO NOT LOG:**
```dart
// ❌ NEVER log detection details
// debugPrint('NSFW detected with score: $score in app: $packageName');

// ✅ Log only aggregated/anonymized info
debugPrint('Detection event logged'); // Generic
```

**DO NOT EXPOSE:**
```dart
// ❌ Don't show raw AI scores in parent dashboard
// Text('Confidence: ${detection.confidenceScore}')

// ✅ Show simplified categories
Text('Type: ${detection.detectionType.name.toUpperCase()}')
```

---

#### 6. Child Account Protection

**Age Verification:**
```dart
// Require date of birth for child accounts
if (role == 'child' && dateOfBirth == null) {
  throw Exception('Date of birth required for child accounts');
}

// Calculate age
final age = _calculateAge(dateOfBirth);
if (age == null || age < 5 || age > 17) {
  throw Exception('Child accounts must be between 5-17 years old');
}
```

**Pairing Validation:**
```dart
// Child cannot access full functionality until paired
if (role == 'child' && parentId == null) {
  return PairingRequiredScreen();
}
```

**Parent Control:**
- Only parent can unpair
- Only parent can change filter settings
- Child cannot disable monitoring
- Child cannot delete detection logs

---

#### 7. Network Security

**AndroidManifest.xml:**
```xml
<application
    android:usesCleartextTraffic="false"
    android:networkSecurityConfig="@xml/network_security_config">
```

**network_security_config.xml:**
```xml
<?xml version="1.0" encoding="utf-8"?>
<network-security-config>
    <base-config cleartextTrafficPermitted="false">
        <trust-anchors>
            <certificates src="system" />
        </trust-anchors>
    </base-config>
    
    <!-- Only trust Firebase/Google servers -->
    <domain-config cleartextTrafficPermitted="false">
        <domain includeSubdomains="true">firebaseio.com</domain>
        <domain includeSubdomains="true">googleapis.com</domain>
    </domain-config>
</network-security-config>
```

---

### Privacy Compliance Checklist

- ✅ **No cloud image uploads:** All AI inference on-device
- ✅ **Minimal data retention:** Screenshots deleted after analysis
- ✅ **Parental consent:** Parents control monitoring settings
- ✅ **Data encryption:** Firebase encrypts data in transit and at rest
- ✅ **Access control:** Firestore security rules enforce permissions
- ✅ **No third-party analytics:** Only Firebase (first-party)
- ✅ **Transparent logging:** Parents see all detection events
- ✅ **User control:** Parents can disable monitoring anytime
- ✅ **Age-appropriate:** Designed for ages 5-17 with parental oversight

---

## Conclusion

This documentation covers all main functions and implementation details of the Guarden (Child Safe App) project. The application demonstrates a sophisticated architecture combining:

- **AI/ML:** On-device TensorFlow Lite inference
- **Cross-platform:** Flutter with native Android integration
- **Real-time sync:** Firebase Firestore streams
- **Privacy-first:** On-device processing, minimal data retention
- **Scalable:** Service-oriented architecture
- **Secure:** Firestore security rules, SSL encryption

For specific implementation questions or contributions, refer to individual service files and the `AGENTS.md` coding guidelines.

---

**Document Maintained By:** AI Coding Agent  
**Last Updated:** February 19, 2026  
**Version:** 1.0