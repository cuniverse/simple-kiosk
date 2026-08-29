# Local Windows patches

This directory vendors `flutter_inappwebview_windows` 0.6.0 under its
BSD-3-Clause license.

The Windows implementation passes a valid `EventRegistrationToken` output
pointer when registering the internal `Fetch.requestPaused` DevTools event.
Passing `nullptr` causes WebView2 to return `E_INVALIDARG` (`0x80070057`) on
affected Windows/WebView2 versions.

Other plugin behavior remains based on upstream 0.6.0.
