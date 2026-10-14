# Buy form: variants and document photos

- RAM, Storage and Color still accept typed values and server-provided options.
  Their sheets now use the Indigo/Mint theme in both light and dark modes, show
  the current selection, and include an explicit close button.
- Document front and back have independent camera/gallery, replace, remove and
  zoom-preview controls. Either single side or both sides can be saved. Existing
  purchases without a photo are still supported.
- Compression happens on-device, off the UI isolate, before base64 encoding.
  Target: **100 KiB per JPEG photo** (the JSON/base64 representation adds ~33%).
  The app tries long-edge sizes 1800, 1500 and 1280px with JPEG quality 94–80,
  without upscaling small originals. Transparent backgrounds become white;
  camera orientation is applied and metadata is stripped.
- A size target is not a promise of lossless compression or automatic readability
  verification. Noisy/detailed images may remain above 100 KiB rather than fall
  below the resolution/quality floor. Actual size and a zoom preview are shown so
  the shop can check text before saving. Retake/crop tightly for the best result.
- Saving is disabled while a photo is being picked/compressed. Cancelling or a
  processing error preserves the previously selected photo.

## Rollout

Deploy the backend before distributing the updated app. Startup migrations add
nullable `phones.customer_id_photo_back` on both new and existing databases.
`customer_id_photo` remains the legacy single/front photo, so old data and clients
continue to work. Both fields are accepted by POST `/buy` and PUT `/phones/:id`,
returned by the authenticated shop-scoped detail endpoint, and omitted from
stock/history list responses. Empty or null clears only that side.

The existing 3 MiB per-side API limit is retained for compatibility. The JSON
body limit is 9 MiB so two maximum-size legacy images plus base64 overhead fit.
Normal new purchases should be much smaller.

## Verification

- `cd backend && npm test`
- `cd app && flutter pub get && flutter analyze --no-pub && flutter test --no-pub`
- The branch's Update goldens workflow regenerates the intentional UI snapshots,
  verifies the Flutter suite, and persists the generated dependency lock file.
- On an Android device, check camera/gallery permissions, portrait/landscape ID
  photos, small print at zoom, replacing/removing either side, cancelling the
  picker, saving one/two photos, and both app themes.
