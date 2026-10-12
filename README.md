# All Stops

A small native iPhone app for collecting NYC subway station visits. Built with SwiftUI and MapKit, for iOS 17 and later. No third-party dependencies, accounts, location access, photos, or visit dates.

## Run on your iPhone

1. Open `AllStops.xcodeproj` in Xcode.
2. Select the **AllStops** target → **Signing & Capabilities**, choose your Apple development team, and change the bundle identifier if needed.
3. Connect your iPhone, select it as the run destination, and press **Run**. Enable Developer Mode on the phone if Xcode requests it.

You can also select an installed iPhone simulator. If no simulator is available, install a runtime under Xcode → Settings → Components.

## Using the app

- **Map:** tap a station marker, then **Mark as visited**. Green checkmarks indicate visits; outlined markers indicate stations still to visit. Tap the button again to undo.
- **By line:** choose a line and swipe a station right-to-left. At 20% of the row width, the revealed action toggles visited/unvisited once and gives haptic feedback. Tap the small status circle to toggle directly; tapping the station text does nothing. Short swipes leave status unchanged. Swipe from the left screen edge to go back. The same station interaction works in search results. Lists are sorted naturally by station name, not in train travel order.
- Search by station name or borough. Filter to **All**, **To visit**, or **Visited**.
- Each connected station complex has one checkmark, shared across its lines and both views.
- The info button includes an optional Staten Island Railway toggle. Hiding SIR preserves its visits.

Progress is stored locally in UserDefaults as stable MTA complex IDs. The checklist works offline; MapKit background tiles may need connectivity. No cloud sync or export. Deleting the app can remove its progress.

## Gesture behavior

Station selection uses a single-finger map tap recognizer and reusable native MapKit annotation views. Cards appear without an entrance animation; highlights clear as dismissal begins, and visit feedback is triggered directly by the action. Pinch and pan remain with MapKit. The station card tracks the drag directly and finishes dismissal with a critically damped spring using release velocity; short canceled drags return to their starting position. Downward scrolling within long details does not initiate dismissal unless the content was already at the top. Reduce Motion uses a brief fade. Single-line lists use a dedicated back gesture beginning within 24 points of the left edge; the page tracks the finger and completes after halfway, or after a fast rightward release beyond 15%. Shorter drags return to the station list. System navigation gestures are restored when leaving the screen.

## Data

The bundled snapshot was retrieved October 7, 2026 from [MTA Subway Stations and Complexes](https://data.ny.gov/Transportation/MTA-Subway-Stations-and-Complexes/5f5g-n3cz): 424 subway complexes plus 21 Staten Island Railway stations. Service badges use the dataset’s daytime routes, not real-time operations. The MTA’s complex IDs and station naming determine transfer grouping. Separate subway platforms within a complex do not count as separate visits.

Refresh the snapshot with `python3 Scripts/update_stations.py`. Review dataset changes and update snapshot dates and count assertions when refreshing. The app only bundles names, IDs, boroughs, routes, and coordinates. Coordinates locate stations, not the user.

## Validation

Run `Scripts/test.sh` to verify dataset integrity, shared transfer visits, filtering, saved progress, undo, and SIR inclusion behavior. Tests use an isolated temporary preferences suite and never touch app progress.

Build without a signing account:

```sh
xcodebuild -project AllStops.xcodeproj -scheme AllStops -sdk iphonesimulator -configuration Debug -derivedDataPath /tmp/AllStopsDerivedData CODE_SIGNING_ALLOWED=NO build
```

The app is independent and is not affiliated with the MTA.
