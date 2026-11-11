# AppSweeper

A small macOS app that uninstalls applications together with their leftovers
(caches, preferences, containers, launch agents, logs, installer receipts).

- Lists apps from `/Applications` and `~/Applications`; you can also drop an `.app` onto the window.
- Finds leftovers by bundle identifier and app name, including embedded helpers and extensions.
- Moves everything to the Trash, so removals are recoverable. Root-owned items are deleted
  permanently only after a separate administrator prompt.
- Requires **Full Disk Access** and shows an error until it is granted.

## Build

Requires the Xcode command line tools (Swift 5.9+), macOS 13 or later.

```bash
./build.sh            # builds AppSweeper.app next to the script
./build.sh install    # builds and copies it into /Applications
```

The app is ad-hoc signed, so macOS asks for Full Disk Access again after every rebuild.

Review the list before uninstalling: name-based matches can include large shared folders.
