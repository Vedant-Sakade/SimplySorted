# TidyUp

One Mac app for tidying up: one-click file sorting plus a few everyday tools.

- **Sort**: preview, then sort loose files into type folders; undo
- **Sort** also reads inside files with no extension (e.g. Instagram saves) to tell images, PDFs, videos and audio apart, and can optionally group font-family and mockup folders
- **Schedule**: sort automatically daily or weekly
- **Move to…**: favourite destination folders, drag files onto them
- **Images**: convert / compress / resize, optional metadata removal
- **PDF**: merge, split, compress
- **Text from Screen**: copy text out of any screenshot (on-device OCR)
- **Uninstall Apps**: remove an app and its leftovers to the Trash

## Build

```bash
scripts/make_icon.sh   # only after changing the icon
scripts/build_app.sh --open
swift test
```

Requires macOS 14+ and Xcode. The app is ad-hoc signed and runs only on the Mac that built it.
