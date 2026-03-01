# AGENTS.md
## AI Coding Agent Guidelines

This document defines the **rules, standards, and constraints** for all AI coding agents contributing to this project.

The goal is to ensure:
- Maintainable, scalable, and secure code
- Consistent architecture and UI behavior
- Zero anti-patterns or shortcut implementations
- Safe handling of child-related and sensitive data
- Do not remove old workable functions, ask before removing

---

## 1. Project Overview

**App Type:** AI-powered parental control & content safety app  
**Primary Function:**  
- Real-time on-device AI detection of NSFW and violent content via screen scanning
- Parent-controlled filtering, reporting, and alerts

---

## 2. Tech Stack (DO NOT DEVIATE)

### Frontend
- **Framework:** Flutter
- **Language:** Dart (SDK ^3.10.8)
- **Design System:** Material Design (Flutter Material 3 where applicable)

### Backend / Services
- **Firebase Core:** ^3.8.1
- **Firebase Authentication:** ^5.3.3
- **Cloud Firestore:** ^5.5.2
- **Google Sign-In:** ^6.2.2

### AI & Content Safety
- **flutter_nsfw:** ^0.0.7
- **Model:** TensorFlow Lite (`nsfw.tflite`)
- **Inference:** On-device only (no cloud inference)

### Device & Utilities
- **Screen Capture:** media_projection_creator ^1.0.0
- **File Storage:** path_provider ^2.1.5
- **Date/Time Formatting:** intl ^0.19.0

---

## 3. General Coding Standards

### Language & Style
- Follow **Effective Dart** guidelines
- Use **strong typing** at all times
- Avoid `dynamic` unless strictly unavoidable
- No unused imports, variables, or dead code

### Architecture
- Prefer **feature-based folder structure**
- Separate concerns clearly:
  - UI
  - Business logic
  - Services
  - Models
- No UI logic inside service or data layers
- AVOID repetitive coding and redundancies
- Object-orientated coding
- DO NOT use deprecated code, replace automatically with up-to-date code

### State Management
- Use a **single, consistent state management approach**
- Avoid mixing patterns in the same feature
- State must be predictable and testable

---

## 4. UI & Theming Rules (STRICT)

### ❌ NEVER DO THE FOLLOWING
- **DO NOT hard-code colors**
- **DO NOT hard-code font sizes**
- **DO NOT hard-code padding or spacing**
- **DO NOT hard-code text styles**
- **DO NOT hard-code light/dark values**

### ✅ REQUIRED PRACTICES
- All colors must come from:
  - `ThemeData`
  - `ColorScheme`
- All text must use:
  - `Theme.of(context).textTheme`
- Spacing must use:
  - Shared spacing constants or layout helpers
- Support **light and dark mode by default**

---

## 5. AI & Screen Scanning Rules

### AI Model Usage
- Load `nsfw.tflite` lazily
- Reuse model instance when possible
- Dispose model properly on shutdown

### Screen Capture
- Never capture screens without explicit user consent
- Handle permission denial gracefully
- Avoid continuous capture if filter is disabled

### Performance
- AI inference must not block UI thread
- Use isolates or background processing where appropriate
- Monitor CPU and memory usage

---

## 6. Security & Privacy (CRITICAL)

### Child Safety & Data Protection
- **DO NOT store raw screenshots permanently**
- **DO NOT upload sensitive images without explicit parent consent**
- **DO NOT log detected content details**
- **DO NOT expose internal AI scores to UI**

### Firebase
- Enforce Firestore security rules
- Validate all reads/writes
- Never trust client-side role checks alone

---

## 7. Firebase & Networking Rules

- All Firestore calls must:
  - Handle errors explicitly
  - Implement timeouts
- No business logic inside Firebase service classes
- Avoid deeply nested async chains

---

## 8. Logging & Debugging

### Logging
- Use structured logging
- No `print()` in production code
- Remove debug logs before release builds

### Error Handling
- Fail gracefully
- Never crash on AI inference failure
- Show user-friendly error messages

---

## 9. Testing Expectations

- All business logic must be testable
- UI components should be widget-test friendly
- Avoid tightly coupled code that cannot be mocked

---

## 10. Forbidden Patterns (ABSOLUTE NO)

🚫 Hard-coded UI values (colors, fonts, spacing)  
🚫 Direct access to Firebase from UI widgets  
🚫 AI inference on main thread  
🚫 Storing sensitive child content unnecessarily  
🚫 Bypassing permissions or user consent  
🚫 One-off hacks or temporary solutions  

---

## 11. Code Review Checklist (For Agents)

Before submitting any change:
- [ ] No hard-coded UI values
- [ ] Uses theme and shared constants
- [ ] Follows architecture conventions
- [ ] Handles errors and edge cases
- [ ] Does not introduce privacy or security risks
- [ ] Code is readable and documented where needed

---

## 12. Final Rule

> **If unsure, do NOT guess.**  
> Ask for clarification or follow existing patterns.

Clean code is mandatory.  
Safety and privacy come first.
