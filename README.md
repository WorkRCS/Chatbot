# AI Chat — Flutter Frontend

A responsive Flutter UI prototype based on the supplied design reference. This first phase intentionally contains frontend/UI only: mock chat responses, model switcher, chat history, image generation panel, search preview, PDF export, settings, and loading states. No backend/API keys are wired yet.

## Requirements

- Flutter stable with Dart SDK 3.4 or newer

## Run locally

Because this repository started empty and contains the app source rather than generated mobile platform files, create the Flutter platform scaffolding once:

```bash
flutter create . --platforms=android,ios,web
flutter pub get
flutter run -d chrome
```

For Android, connect a device or start an emulator, then run `flutter run`. You can also open the project in Android Studio or VS Code.

## Frontend scope

- Desktop: navigation sidebar, centered chat canvas, and an image-generation side panel.
- Tablet/mobile: adaptive navigation drawer and stacked image/PDF layouts.
- Transparent assistant responses, sample physics formatting, loading skeleton, model switcher, feedback controls, and PDF export.
- Image-generation UI with a local preview state.
- Light/dark theme and recent-chat navigation.
- Uses local mock data until backend integration is approved.

## Current limitation

Buttons and screens are present for UI testing, but Groq chat, live Tavily search, vision/image generation, image upload, persistent MongoDB memory, and actual generated-image downloads are not connected in this frontend-only phase. The PDF export control generates a local preview PDF from the current mock conversation. API secrets must never be placed in Flutter source or a client-side `.env` file.

## Next phase

The frontend should be reviewed first. Backend routes and provider integrations will be added separately after approval.
