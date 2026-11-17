# LOKI – lokale KI für macOS

LOKI ist eine native macOS-App, die KI-Aufgaben vollständig lokal mit Open-Weight-Modellen erledigt –
ohne Abo, ohne Cloud-Zwang, auch offline. Diese Version ist die **0.1 Vorschau** (Meilensteine P1/P2 des Konzepts).

## Was LOKI 0.1 kann

- **Lokaler Chat mit MLX** (Apple Silicon): Antworten streamen, Token/s und Zeit bis zum ersten Wort werden gemessen.
- **AUTO MODE**: Aufgabenerkennung (kurze Frage, Text, Code, Analyse, langer Text), harte Filter (Fähigkeit,
  Kontextfenster, freier Speicher, Laufwerk verbunden, Lizenz), Bewertung nach Qualität je Aufgabenart, Tempo,
  Ladezeit und Speicherlast. Jede Wahl kommt mit einem Satz Begründung.
- **Modellwechsel mitten im Chat**: nur an Schrittgrenzen und nur bei mindestens 15 % Gewinn oder fehlender
  Fähigkeit. Die **Context Engine** übergibt den Verlauf modellunabhängig (letzte Schritte wörtlich, ältere als
  Zusammenfassung, höchstens 60 % des Kontextfensters). Jeder Wechsel erscheint als Zeile im Chat.
- **MANUELL**: Das gewählte Modell gilt für den ganzen Chat und wird nie heimlich ersetzt. Optional schlägt LOKI
  einen Wechsel vor – gewechselt wird nur auf Klick.
- **Modellverwaltung**: Startkatalog (Qwen, Gemma, Mistral, DeepSeek, gpt-oss, GLM, Llama, OLMo) mit Kennzeichnung
  Open Source / Open Weight und Lizenzklasse; beliebige MLX-Modelle per Hugging-Face-Kennung; Download direkt auf
  das Ziel-Laufwerk mit Fortsetzen nach Abbruch; Laden, Entladen, in den Papierkorb legen.
- **Externe SSD**: Speicherort frei wählbar, Laufwerke werden automatisch erkannt, freier Platz und gemessene
  Lesegeschwindigkeit werden angezeigt; abgezogene Laufwerke werden erkannt, Modelle danach ohne Neustart nutzbar.
- **Hardware-bewusst**: echtes Speicherbudget (frei + GPU-Arbeitsbereich), Entladen vor dem Laden, wenn es eng wird.
- **Offline**: alles außer Downloads funktioniert ohne Internet; Online-/Offline-Anzeige.
- **Liquid Glass** in Dunkel und Hell: schwebende Glas-Navigation, Eingabefeld, Aufgabenleiste.

## Bewusst noch nicht enthalten

Coding-Agent (M6), Projektanalyse (M7), Office und Creative (M8), externe Experten / Zweitmeinung (P6 – Knopf
ist sichtbar und erklärt), Bildeingabe für Vision-Modelle, Signierung und Notarisierung. Diese Bereiche zeigen
in der App „geplant“.

## Installation

DMG öffnen, LOKI in „Programme“ ziehen. Beim ersten Start einmal „Fertig“ klicken, dann
Systemeinstellungen → Datenschutz & Sicherheit → „Dennoch öffnen“ (die App ist ad-hoc signiert, nicht notarisiert).

## Bauen

```bash
brew install xcodegen
scripts/build.sh          # → build/LOKI.app
scripts/make_dmg.sh       # → dist/LOKI-0.1.0.dmg
swift test                # Kern-Tests (Router, Aufgabenerkennung, Context Engine)
```

Die CI (`.github/workflows/build.yml`) baut auf einem macOS-26-Rechner mit Xcode, erzeugt Vorschaubilder,
führt einen Selbsttest mit einem echten Modell aus und legt alle Ergebnisse im Zweig `ci-ergebnisse` ab.

## Aufbau

| Ort | Inhalt |
|---|---|
| `Sources/LokiCore` | Katalog, Aufgabenerkennung, AUTO-Router, Context Engine – ohne Abhängigkeiten, getestet |
| `Sources/LOKI/App` | App, zentrale Steuerung, Chats, Einstellungen |
| `Sources/LOKI/Services` | MLX-Laufzeit, Tokenizer, Downloads, Laufwerke, Hardware, Netz |
| `Sources/LOKI/Views` | Oberfläche (Home, Chat, Modelle, Einstellungen, Verlauf, geplante Bereiche) |
| `Sources/LOKI/Design` | Designsystem: Farben, Glas, Radien, Abstände, Bewegung |
| `Sources/LOKI/QA` | Prüfmodus für Vorschaubilder und Selbsttest (nur mit `LOKI_DATA_DIR`) |
