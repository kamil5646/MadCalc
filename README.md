# MadCalc

MadCalc to lokalny kalkulator optymalizacji cięcia sztang. Projekt działa offline i składa się z dwóch aplikacji:

- `MadCalc_iOS` - natywna aplikacja iOS w SwiftUI
- `madcalc_desktop` - aplikacja desktopowa Flutter dla macOS i Windows

## Co potrafi

- dodawanie elementów `długość + ilość`
- wybór jednostek `cm` lub `mm`
- ustawienie długości sztangi i grubości piły
- generowanie planu cięcia z liczbą sztang, odpadem i wykorzystaniem materiału
- własne nazwy dla każdej sztangi
- zapis raportu PDF lokalnie na dysku
- zapis stanu aplikacji lokalnie, bez backendu

## Struktura repo

```text
MadCalc_iOS/       Natywna aplikacja iOS
madcalc_desktop/   Flutter desktop dla macOS i Windows
```

## Uruchamianie

### iOS

Otwórz projekt:

```bash
open MadCalc_iOS/MadCalc_iOS.xcodeproj
```

### macOS

```bash
cd madcalc_desktop
flutter run -d macos
```

### Windows

Projekt Windows jest gotowy w katalogu `madcalc_desktop/windows`. Build należy wykonać na maszynie z Windowsem:

```bash
cd madcalc_desktop
flutter build windows
```
