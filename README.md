# IP-Wechsler

## EXE bauen

```powershell
powershell -ExecutionPolicy Bypass -File .\build_exe.ps1
```

Danach liegt `IP_Wechsler.exe` im Projektordner.

## Presets einstellen

Die Presets stehen in `presets.json` (gleicher Ordner wie Skript/EXE).

- In der App auf **"Presets bearbeiten"** klicken (öffnet die Datei in Notepad).
- Nach Änderungen auf **"Presets neu laden"** klicken.

Ein Preset braucht mindestens:

- `Name`
- `IP`
- `Mask`

`GW` und `DNS` sind optional.
