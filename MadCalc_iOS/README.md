# MadCalc iOS

Natywna aplikacja iOS w SwiftUI do optymalizacji cięcia sztang.

Aktualna poprawka iOS porządkuje metadane projektu, bundle identifier, testy i zgodność logiki z pozostałymi wersjami `MadCalc`.

## Co zawiera

- projekt Xcode generowany przez `xcodegen`
- działanie offline
- lokalny zapis danych przez `UserDefaults`
- przełączanie `cm / mm`
- obliczanie planu cięcia
- eksport raportu PDF przez systemowy share sheet
- testy jednostkowe dla optymalizacji i jednostek

## Jak otworzyć projekt

```bash
open /Users/kamilkasprzak/Documents/inne/MadCalc_iOS/MadCalc_iOS.xcodeproj
```

Projekt `.xcodeproj` jest już gotowy i został sprawdzony buildem pod iOS Simulator.

## Jak odświeżyć projekt

```bash
cd /Users/kamilkasprzak/Documents/inne/MadCalc_iOS
xcodegen generate
```

## Weryfikacja

```bash
cd /Users/kamilkasprzak/Documents/inne/MadCalc_iOS
xcodegen generate
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project MadCalc_iOS.xcodeproj -scheme MadCalc -destination 'platform=iOS Simulator,name=iPhone 16'
```
