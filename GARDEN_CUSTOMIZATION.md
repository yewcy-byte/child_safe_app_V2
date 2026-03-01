# Garden Page Customization Guide

## Overview
The Garden tab has been successfully created and is now a dedicated tab in the child dashboard. The Rules tab has been removed as requested.

## What Changed

### Navigation Structure
- **Removed:** Rules tab
- **Added:** Garden tab (with plant icon 🌺)
- **Tab Order:** Status → Detections → Garden

### Code Changes
1. **Created:** `lib/ui/child/pages/garden_page.dart` - New dedicated garden page
2. **Modified:** `lib/ui/child/child_dashboard.dart` - Updated navigation tabs
3. **Modified:** `lib/ui/child/pages/status_page.dart` - Removed embedded gamified dashboard
4. **Modified:** `lib/ui/child/pages/pages.dart` - Updated exports

## Using a Custom Background

The Garden page supports custom background images. Here's how to use one:

### Step 1: Add Your Background Image
Place your background image in the assets folder:
```
assets/
  images/
    garden_bg.png    # Your custom background
```

### Step 2: Register in pubspec.yaml
Add your image to the assets section (if not already covered by wildcards):
```yaml
flutter:
  assets:
    - assets/images/
    - assets/images/garden_bg.png
```

### Step 3: Update child_dashboard.dart
In `lib/ui/child/child_dashboard.dart`, modify the GardenPage initialization:

Find this line (around line 59):
```dart
GardenPage(onProfileButtonPressed: _signOut),
```

Replace with:
```dart
GardenPage(
  onProfileButtonPressed: _signOut,
  backgroundImagePath: 'assets/images/garden_bg.png',  // Your image path
),
```

### Example Background Images
You can use any image format supported by Flutter:
- `.png` (recommended for transparency)
- `.jpg` / `.jpeg`
- `.webp`

### Background Fit Options
The background uses `BoxFit.cover` by default, which fills the entire screen. To change this, modify `garden_page.dart` line 45:

```dart
fit: BoxFit.cover,  // Options: fill, contain, cover, fitWidth, fitHeight, none, scaleDown
```

## UI Elements

The Garden page includes:
- **Water Bar:** Shows daily water points (max 24, +1/hour, -3 on violation)
- **Plant Model:** Interactive 3D-style plant (pan to rotate, tap to harvest)
- **Growth Bar:** Progress to next level (0-100 points)
- **Tomato Display:** Current tomato count
- **Exchange Button:** Trade 5 tomatoes for 15 minutes screen time

## Technical Details

### Background Implementation
- Uses `Container` with `BoxDecoration` and `DecorationImage`
- Placed behind the gamified dashboard content
- Supports transparency for Card widgets on top
- No performance impact (static asset)

### Card Transparency
If you want the garden card to blend with your background, adjust the Card's elevation or color in `gamified_dashboard_section.dart`.

## Tips for Best Results

1. **Image Resolution:** Use at least 1080x1920px for mobile screens
2. **File Size:** Keep under 500KB for fast loading
3. **Colors:** Use soft, nature-themed colors that don't clash with UI elements
4. **Contrast:** Ensure text remains readable against your background
5. **Theme Support:** Consider providing different backgrounds for light/dark themes

## Future Enhancements

Potential features you could add:
- User-selectable backgrounds (stored in Firestore)
- Dynamic backgrounds based on plant level
- Animated backgrounds
- Seasonal themes
- Upload custom images from gallery

---

**Note:** After adding a background image, run `flutter pub get` to ensure assets are recognized, then rebuild your app.
