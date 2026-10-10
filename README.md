# OLED Curtain

An adjustable, click-through black overlay for Windows 11. It dims your desktop, background windows, and non-essential app toolbars, featuring a soft "flashlight" that follows your mouse or keyboard focus. Designed to protect OLED displays from static interface brightness, while also eliminating visual distractions and boosting deep focus on any monitor type.

## Key Features

* **Smart Multi-Window Management:** Your primary active window and its workspace remain fully bright while background apps are dimmed. If you work with multiple windows side-by-side, secondary windows remain unmasked as long as their total obstruction by higher windows stays below a configurable threshold (default max 10%). This enables clean multi-window workflows without background clutter.

* **Active Text Field Unmasking:** Automatically keeps active, editable text fields (like browser address bars or form inputs) bright and clear, even when the flashlight fades out.

* **Taskbar & Fullscreen Compatibility:** Manages the Windows taskbar and full-screen application detection automatically.

## Installation

1. Unzip the archive into a single folder.

2. Run **`START-OLED-Curtain.cmd`** (the first run requires a brief, automatic C# compilation).

3. Click the hamburger menu (three gray lines on the right edge of the screen) or press **`Ctrl+Alt+M`** to open settings.

*No admin rights or extra modules required. It uses standard Windows PowerShell 5.1 and .NET Framework.*

### PowerShell Command Line Options

You can type them manually in PowerShell or setup Task Scheduler to start the script at logon.

```
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\OLED-Curtain.ps1
```

* Add `-StartPaused` to launch with the overlay disabled.

## Controls & Shortcuts

| Action | Default Shortcut | 
| ----- | ----- | 
| **Pause / Resume** | `Ctrl+Alt+Space` | 
| **Open Settings** | `Ctrl+Alt+M` | 
| **Quit** | `Ctrl+Alt+Q` | 
| **Increase current app top curtain** | `Ctrl+Alt+↑` | 
| **Decrease current app top curtain** | `Ctrl+Alt+↓` | 

* **Hamburger Menu:** Left-click opens settings; right-click toggles pause. The hamburger icon auto-moves along the edge to avoid blocking content and screen deterioration, and it hides during fullscreen/system UI interactions.

* **Customization:** Shortcuts can be modified under **Advanced** settings in the app.

## Settings & Profiles

* **Curtain Opacity:** Default 15% transparency (85% black coverage).

* **Toolbar Opacity:** Default 50%.

* **Flashlight Size:** \~16.7% of the monitor width.

* **Inactivity Timeout:** 60 seconds, followed by a gentle 0.7-second fade.

### Adjusting App Profiles

Initial profiles for apps like Word, Foxit, Inkscape, and Brave are approximations. To fine-tune:

1. Activate the target application.

2. Open **OLED Curtain** settings.

3. Click **Profile for last active program**.

4. Adjust top/bottom margins so the curtain ends right beneath the app's toolbars.

Settings are saved in `%LOCALAPPDATA%\OLED-Curtain\settings.json`.

## Details for Nerds

### Technical Implementation

* **UI Automation (UIAutomation):** Text field tracking runs in a background thread. Responds to clicks and keyboard navigation immediately; otherwise polls every \~0.5s. Unconfirmed bounding rectangles expire after 2s if apps stop responding. Uses `ValuePattern` and `TextPattern` interfaces.

* **Taskbar & Shell Integration (`NonRudeHWND`):** Implements `NonRudeHWND = 1` before windows are first shown to prevent Windows from treating the overlay like an exclusive full-screen app, bypassing taskbar auto-hide conflicts.

* **Window Geometries & Rules:** Overlap percentages are calculated strictly using window rectangles. Excludes transparent areas and ignores overlays during Alt+Tab, Start Menu, task views, or detected full-screen windows (e.g., F11).

* **Validation & Testing Commands:**

  * Local compilation test:

    ```
    powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\OLED-Curtain.ps1 -ValidateOnly
    ```

  * Logic self-tests:

    ```
    powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\OLED-Curtain.ps1 -SelfTest
    ```

* Error logs are written to `errors.log` next to the settings file.

## About and Licensing
OLED Curtain was mainly AI coded by GPT-6 Astra, directed and corrected by Dariusz Zen Żukowski as a product owner (c) 2026. It is free for private use until it changes. Any licensing changes will be posted here. 
