# Landman Website - Flutter App

A responsive Flutter application implementing the Account Settings design from Figma.

## Features

- Responsive design that adapts to mobile, tablet, and desktop screens
- Account Settings page with Personal Details and Password sections
- Sidebar navigation with collapsible menu on mobile
- Clean, modern UI matching the Figma design

## Screen Sizes

- Desktop: 1440x1024 (original design)
- Tablet: 768px - 1024px
- Mobile: < 768px

## Getting Started

1. Make sure you have Flutter installed (SDK >= 3.0.0)
2. Install dependencies:
   ```bash
   flutter pub get
   ```
3. Run the app:
   ```bash
   flutter run
   ```

## Project Structure

```
lib/
  ├── main.dart
  ├── screens/
  │   └── account_settings_screen.dart
  └── widgets/
      ├── sidebar_navigation.dart
      ├── nav_link.dart
      ├── account_settings_content.dart
      ├── personal_details_card.dart
      └── password_card.dart
```

## Responsive Behavior

- **Desktop (>1024px)**: Fixed sidebar (252px) with main content area
- **Tablet (768-1024px)**: Sidebar and content side by side with adjusted padding
- **Mobile (<768px)**: Collapsible sidebar overlay with hamburger menu

