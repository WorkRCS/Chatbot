# AI Chat — Flutter Frontend

A responsive Flutter UI prototype based on the supplied design reference. This first phase intentionally contains frontend/UI only: mock chat responses, model switcher, chat history, image generation panel, search results preview, PDF export preview, settings, responsive layouts, and loading states. No backend/API keys are wired yet.

## Requirements

- Flutter stable (Dart SDK 3.4+)

## Run locally

```bash
flutter pub get
flutter run -d chrome
```

If this repository does not yet contain platform scaffolding, generate it once with:

```bash
flutter create . --platforms=android,ios,web
```

Then run the app using your desired target.

## Frontend scope

- Desktop: navigation sidebar, chat canvas, optional image-generation side panel.
- Tablet/mobile: adaptive drawer/navigation and stacked content.
- Transparent assistant responses, loading/skeleton state, model selector, feedback controls, and PDF/image UI previews.
- Uses local mock data until backend integration is approved.

## Next phase

Backend routes and provider integrations will be added separately after the frontend is reviewed. Do not put API secrets in Flutter source or client-side `.env` files.