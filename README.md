# 🐭 SociaLyze

*A cross-platform desktop app for analyzing three-chamber social interaction & novelty tests in neuroscience research.*

---

## ✨ Features

* **Drag & drop video playback** (AVI, MP4, etc.) with speed control
* **Keyboard shortcuts (numpad)** to log mouse chamber entries in real time
* **Multi-mouse support** (track up to 3 mice simultaneously)
* **Automatic dwell time & switch count summaries**
* **Export to CSV** for downstream analysis in Excel or R
* **Local SQLite database** (via Drift) to persist sessions and re-load past experiments

---

## 📦 Tech Stack

* **Flutter (Dart)** – cross-platform UI (Windows, macOS, Linux)
* **media\_kit** – efficient native video playback
* **Drift + SQLite** – lightweight local data persistence
* **Riverpod** – state management
* **CSV** – export summaries for external analysis

---

## 🚀 Getting Started

### Prerequisites

* [Flutter SDK](https://docs.flutter.dev/get-started/install) (3.19+ recommended)
* Enable desktop support:

  ```bash
  flutter config --enable-windows-desktop --enable-macos-desktop --enable-linux-desktop
  ```

### Clone & install

```bash
git clone https://github.com/<your-username>/socialyze.git
cd socialyze
flutter pub get
```

### Run (example: Windows)

```bash
flutter run -d windows
```

### Build a release binary

```bash
flutter build windows   # or macos / linux
```

The resulting binaries will be inside `build/<platform>/`.

---

## ⌨️ Hotkey Mapping

| Protocol           | Mouse A (7/4/1)                  | Mouse B (8/5/2)                  | Mouse C (9/6/3)                  |
| ------------------ | -------------------------------- | -------------------------------- | -------------------------------- |
| Social Interaction | Empty / Middle / Stranger        | Empty / Middle / Stranger        | Empty / Middle / Stranger        |
| Social Novelty     | New Stranger / Middle / Stranger | New Stranger / Middle / Stranger | New Stranger / Middle / Stranger |

---

## 📊 Output Format

CSV export includes:

* **Summary rows** – dwell time per chamber & switch counts
* **Event rows** – timestamped log of each chamber entry

---

## 🤝 Contributing

1. Fork the repo
2. Create a feature branch (`git checkout -b feature/xyz`)
3. Commit changes (`git commit -m "Add xyz"`)
4. Push to your branch and open a PR

---

## 📜 License

MIT License – free to use and adapt for research or educational purposes.

---

## 🧠 About

SociaLyze was created as a **personal passion project** to streamline behavioral research by reducing manual annotation errors and improving experimental throughput.
