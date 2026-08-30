# Mousetrapped 🪤🖱️

A tiny, free, open-source macOS menu bar app that rescues your mouse cursor
when it gets trapped, hidden, or lost, including when Universal Control has
carried it off to another Mac.

```bash
brew install --cask uncSoft/mousetrapped/mousetrapped
```

Or grab the notarized build from the
[latest release](https://github.com/uncSoft/Mousetrapped/releases/latest).

## The bug it fixes

On macOS, when a nearby Mac has Universal Control / mouse sharing enabled
(made worse by remote-control tools like ScreenConnect), the cursor can get
"eaten": some window captures pointer focus, hides the cursor, and leaves you
in no-mouse limbo. Or the pointer crosses to the other Mac and something over
there swallows it.

Under the hood the cursor usually isn't gone. It has been *disassociated*
from the mouse (`CGAssociateMouseAndMouseCursorPosition(false)`), hidden by a
process that never restored it, or routed to another machine. Mousetrapped
forcibly undoes all of that.

## What it does

Press the hotkey (**⌃⌥⌘M** by default) or **shake the mouse** hard
left-right, and Mousetrapped will:

1. Re-associate the mouse with the on-screen cursor (undoes pointer capture)
2. Warp the cursor to the center of your chosen display (primary by default)
3. Post a synthetic mouse-move so the window server and frontmost app
   re-evaluate cursor visibility
4. Pulse a red locator ring at the destination so you can spot the cursor
5. **If the pointer is on another Mac** (Universal Control): restart the
   `UniversalControl` agent, which forces macOS to bring the pointer home,
   then warp it to your chosen display

Remote-pointer detection compares the raw HID device stream against the local
session's event counters. If the physical mouse is moving but the local
session sees nothing (or the cursor is parked at a screen edge, where
Universal Control leaves it), the pointer is on the other Mac.

<img width="230" alt="rescue_splash" src="https://github.com/user-attachments/assets/152236f5-8e70-445b-823e-c71df00c4e0a" />

## Menu bar controls

- **Rescue Cursor Now**: manual trigger
- **Rescue To**: primary display or any connected display
- **Shake Mouse to Rescue**: toggle shake detection
- **Shake Sensitivity**: slider from hair-trigger (right: 3 reversals of
  light flicks) to deliberate (left: 6 big sweeping arcs). Sensitivity
  scales how *long* you must shake and how *big* each stroke must be,
  never how fast.
- **Work Across Macs…**: enables raw HID monitoring (see Permissions)
- **Launch at Login**

## Install

With Homebrew:

```bash
brew install --cask uncSoft/mousetrapped/mousetrapped
```

Or download the notarized build from
[Releases](https://github.com/uncSoft/Mousetrapped/releases).

Or build from source (requires Xcode command line tools):

```bash
git clone https://github.com/uncSoft/Mousetrapped.git
cd Mousetrapped
./build.sh            # or ./build.sh --universal for arm64 + x86_64
cp -R dist/Mousetrapped.app /Applications/
open /Applications/Mousetrapped.app
```

`build.sh` signs with your first available Apple Development / Developer ID
identity (override with `CODESIGN_IDENTITY=...`), falling back to ad-hoc. A
stable identity matters: macOS ties the Input Monitoring grant to the code
signature, so ad-hoc builds lose the grant on every rebuild.

## Permissions

Mousetrapped runs at three privilege levels, using the lowest one that works:

- **No permissions**: the ⌃⌥⌘M hotkey (Carbon `RegisterEventHotKey`) and the
  menu bar button always work for local rescues.
- **No permissions (usually)**: shake detection via an NSEvent global
  monitor.
- **Input Monitoring** (opt-in via *Work Across Macs…*): raw HID monitoring
  with `IOHIDManager`. This watches the physical mouse and keyboard below
  the layer where Universal Control captures input, so shake and hotkey
  detection (and rescue) work even while the pointer is controlling
  another Mac. Grant it under System Settings → Privacy & Security → Input
  Monitoring, then relaunch the app.

## Configuration beyond the menu

The hotkey is stored in `UserDefaults` as a Carbon key code + modifier mask.
Example: set it to ⌃⌥⌘R (key code 15):

```bash
defaults write dev.mousetrapped.Mousetrapped hotKeyCode -int 15
defaults write dev.mousetrapped.Mousetrapped hotKeyModifiers -int 6400
killall Mousetrapped && open /Applications/Mousetrapped.app
```

Modifier mask is the sum of Carbon flags: ⌘ 256, ⇧ 512, ⌥ 2048, ⌃ 4096
(6400 = ⌘ + ⌥ + ⌃).

Debugging: the app logs events to the unified log (subsystem
`dev.mousetrapped.Mousetrapped`; view with `log stream --predicate
'subsystem == "dev.mousetrapped.Mousetrapped"' --level info`). To also
mirror to `~/Library/Logs/Mousetrapped.log`, and for per-stroke shake
diagnostics:

```bash
defaults write dev.mousetrapped.Mousetrapped debugLogging -bool true
defaults write dev.mousetrapped.Mousetrapped shakeDebug -bool true
```

## Limitations

- Restarting Universal Control to reclaim the pointer drops the
  Universal Control link for a moment; push through the screen edge to
  reconnect. That trade-off is the point: it's a panic button.
- If another process hid the cursor via `CGDisplayHideCursor` and is truly
  wedged, macOS scopes that hide to the offending process; the rescue
  restores control and shows you where the cursor is, but killing the wedged
  process is the final fix.
- VMs or remote sessions that grab the pointer at a lower level have to
  release it themselves.

## License

[PolyForm Noncommercial 1.0.0](LICENSE.md): the source is free to use,
modify, and share, but **not for commercial use**. You can't sell it or ship
it inside a paid product.
