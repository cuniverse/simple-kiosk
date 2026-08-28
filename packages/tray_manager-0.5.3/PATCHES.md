# Local Windows patches

This directory vendors `tray_manager` 0.5.3 under its MIT license.

The Windows implementation adds:

- native 32-bit green and gray status bitmaps for the `status-connected` and
  `status-disconnected` menu icon tokens;
- explicit bitmap handle cleanup when the dynamic menu is rebuilt;
- the recommended `WM_NULL` message after `TrackPopupMenu` returns.

Other plugin behavior remains based on upstream 0.5.3.
