# GuardianLens (Child Safe App)

GuardianLens is an AI-powered parental control and digital safety platform built with Flutter. It helps parents proactively protect children from harmful content and risky digital behavior through on-device intelligence, real-time monitoring, and practical family controls.

## What This Project Does

GuardianLens combines live content detection, behavior monitoring, and parent action tools into one app experience:

- Detects unsafe visual content in near real time
- Flags potential grooming-risk text patterns in selected apps
- Tracks app usage, screen time, and child activity trends
- Lets parents apply controls instantly (block apps, set limits, add rewards)
- Continues protection with native Android background services

## AI Capabilities

### 1. On-Device NSFW Detection
- Uses a TensorFlow Lite model (`assets/nsfw.tflite`) through `flutter_nsfw`
- Performs local image inference for explicit-content risk scoring
- Lazily initializes and reuses model resources for performance

### 2. On-Device Weapon and Gore Detection
- Uses a dedicated TensorFlow Lite classifier (`assets/weapon+gore_v2.tflite`)
- Classifies content into `Blood`, `Weapon`, or `Safe`
- Applies confidence thresholding to reduce false unsafe alerts

### 3. Grooming-Risk Text Signal Detection
- Monitors selected apps for suspicious grooming-related text signals
- Includes duplicate-event suppression and cooldown windows to avoid alert spam
- Triggers safety notifications when grooming risk is detected

### 4. AI Parent Consultant
- Generates weekly child safety summaries from app usage, detections, and screen-time data
- Provides actionable recommendations for parents
- Supports structured action execution via chat (for example, set limits, block/unblock apps, add rewards)

## Core Features

### Parent Controls
- Parent/child account roles with secure Firebase authentication
- QR and pairing flow for linking child devices
- App blocking and unblock management
- Per-app daily time limits and total screen-time controls
- Reward and motivation system integration
- Child profile and protection status management

### Monitoring and Reporting
- Real-time detection event logging
- Screen-time and app-usage analytics
- Weekly trend context for AI safety summaries
- Activity and detection dashboards for parent review

### Background Protection (Android)
- Foreground MediaProjection service for persistent capture capability
- Accessibility-based app change monitoring
- Protection continuity when app is minimized or removed from recents

### Location and Device Awareness
- Child location tracking with periodic updates
- Battery optimization handling and background permission flows
- Device/app metadata support for monitoring insights

## Privacy and Safety Principles

- AI inference is designed to run on-device for sensitive content analysis
- Permission-gated monitoring flows and explicit runtime checks
- Defensive error handling to keep protection stable under failures
- Structured cloud storage and role-based data separation via Firebase

## Tech Stack

- **Frontend:** Flutter (Dart)
- **State Management:** Riverpod
- **AI/ML:** TensorFlow Lite (`flutter_nsfw`, `tflite_flutter`)
- **Backend:** Firebase Auth, Cloud Firestore, Cloud Functions, Firebase Storage
- **Local Data:** Hive
- **Platform Integrations:** Android MediaProjection, Accessibility, Location services

## Vision

GuardianLens is built to move parental controls beyond static rules into intelligent, adaptive family safety: prevention first, parent insight second, and child privacy respected throughout.
