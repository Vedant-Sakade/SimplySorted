# TidyUp

**One Mac app that tidies up your files.** Sort a messy Downloads folder into neat type folders with one click, then use a few everyday tools built in: image converter, PDF tools, text from screenshots, an app uninstaller and quick "move to" folders.

Free and open source. Runs entirely on your Mac. Nothing is uploaded anywhere, and the app has no network code.

![TidyUp](docs/screenshot.png)

## Install

1. Download **TidyUp.dmg** from the [latest release](https://github.com/Vedant-Sakade/TidyUp/releases/latest).
2. Open it and drag **TidyUp** onto the **Applications** folder.
3. Open **Applications**, **right-click TidyUp, choose Open**, then click **Open** again.

Step 3 is only needed the first time. macOS asks because TidyUp isn't from the App Store and isn't notarised by Apple. After that it opens like any other app.

If macOS still blocks it, go to System Settings > Privacy & Security and click **Open Anyway** next to TidyUp.

**Needs:** macOS 14 (Sonoma) or newer. Works on Apple Silicon and Intel Macs.

The first time it touches Downloads, Desktop or Documents, macOS asks for permission. Click Allow, or TidyUp can't see those folders.

## What is it for?

Downloads and Desktop fill up with screenshots, PDFs, installers, zips and files with no name you recognise. TidyUp puts each file in a folder for its type, shows you what it will do first, and lets you undo it. The extra tools cover small jobs that normally need several separate apps or websites, such as shrinking photos, merging PDFs or removing an app properly.

### Who it's useful for

- **Anyone with a messy Downloads or Desktop folder**, which is most people.
- **Students**: merge notes into one PDF, cut pages out of a scan, pull the text out of a slide screenshot.
- **Designers and creatives**: font folders, mockups and design source files are kept together instead of being scattered.
- **Photographers and content creators**: convert photos to JPEG, PNG or HEIC, shrink them for email and the web, and remove GPS location before sharing.
- **Office and freelance work**: sort invoices, spreadsheets and presentations, move files into client or project folders in one drag.
- **People who want to free up space**: remove apps along with the files they leave behind.
- **Privacy-minded users**: everything runs on your Mac, with no accounts, sign-ups or cloud.

## Features

### Sort

- **One-click sorting.** Switch on the folders you want tidied (Downloads and Desktop are the usual ones) and press **Sort now**. Files move into type folders: Images, Videos, Audio, Documents, Spreadsheets, Presentations, Design, Ebooks, Archives, Installers, Code, Fonts and Other.
- **Preview before anything moves.** A dial shows how many files are ready. A bar chart and a list show how many files go to each type, and you can expand a type to see the files.
- **Undo.** Put the last sort back exactly as it was.
- **Files with no extension.** Files saved without a name ending (some Instagram or app downloads) are opened and recognised as images, PDFs, videos, audio or archives, so they don't pile up in Other.
- **Group font and mockup folders (optional).** Folders of fonts go into Fonts, and mockup folders go into Mockups. Other folders stay where they are. Folders that hold design source files (for example Illustrator packages) are never mistaken for font folders.
- **Auto sort.** Run the sort daily or weekly at a time you choose. TidyUp can also open when you log in. Auto sort works while TidyUp is open, and it lives in the menu bar.
- **Menu bar.** Sort now, undo, switch between light and dark, or capture text from the screen without opening the window.

### Move to

- Save the folders you move files to most, like a client or project folder.
- Drag files onto a saved destination to move them there in one step.

### Images

- Convert to **JPEG, PNG or HEIC**.
- **Quality** slider up to 100%, so you pick the balance between file size and sharpness.
- **Resize** by longest side. Small images are never enlarged.
- **Remove location and camera info** (GPS and other hidden photo data) before you share a picture.
- Shows how much space you saved. Your original pictures are never replaced.

### PDF

- **Merge** several PDFs into one.
- **Split** a PDF into separate files.
- **Delete pages.** Pick pages by clicking their thumbnails or typing ranges like `1-3, 7`. TidyUp won't delete every page.
- **Compress** a large PDF. The smaller file is saved only if it really is smaller.
- The original PDF is never changed. Results are saved as new files next to it.

### Text from screen

- Drag over any part of the screen and TidyUp copies the text to your clipboard (OCR).
- Recognition happens on your Mac using Apple's built-in Vision framework.

### Uninstall apps

- Pick an app and see the leftover files it created, like settings and caches.
- Everything goes to the **Trash**, so you can get it back.
- Items found only by name start unticked, so you check them before removing.
- Apple's own apps and TidyUp itself can't be removed.

### Look and feel

- Calm sage-and-ink design with rounded cards and pill buttons.
- **Light and dark mode** with a switch in the header. TidyUp remembers your choice.

## Safe by design

TidyUp is built so a sort can't lose your work.

- **It never overwrites.** If a file with the same name already exists, the new one is renamed ("report 2.pdf").
- **It leaves some things alone:** folders (unless you turn on grouping), hidden files, partial downloads, and files changed in the last 30 seconds.
- **The file ending decides the type.** Contents are only checked when a file has no known ending.
- **Everything is undoable.** Each sort is logged so it can be reversed.
- **Removed apps go to the Trash**, not straight to deletion.
- **Private.** No network code, no account, no analytics.

## FAQ

**Is it free?** Yes, MIT licensed.

**macOS says "TidyUp can't be opened".** Right-click the app, choose Open, then click Open. This is needed once because the app isn't notarised by Apple.

**Where do sorted files go?** Into type folders inside the folder you sorted. For example, `Downloads/Images`.

**Can I undo a sort?** Yes. Use **Undo last sort** in the Sort tab or the menu bar. You can only undo the most recent sort.

**Does auto sort work when TidyUp is closed?** No. It runs while TidyUp is open. Turn on "Open TidyUp when I log in" and it stays in the menu bar.

**Does it work on Intel Macs?** Yes. The app is universal.

**Does it work on older macOS?** No. It needs macOS 14 or newer.

## Build it yourself

```bash
scripts/build_app.sh --open   # universal app in build/TidyUp.app
scripts/make_dmg.sh           # also packs build/TidyUp.dmg
scripts/make_icon.sh          # only after replacing Resources/IconSource.png
swift test                    # engine, app-model and real-click control tests
```

Requires macOS 14+ and Xcode (or its command-line tools). `TidyUp --render-preview <folder>` draws every screen to PNG for checking the design.

## Credits

Typeset in Geist Mono (SIL Open Font License, bundled in `Resources/Fonts`).

## Licence

MIT, see [LICENSE](LICENSE). The bundled Geist Mono font keeps its own SIL Open Font License (`Resources/Fonts/OFL.txt`).
