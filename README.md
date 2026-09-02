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
- **Shake Sensitivity**: slider from hair-trigger (right: 3 quick flicks)
  to deliberate (left: 7 vigorous strokes). At every level a shake means
  rapid, rhythmic, mostly horizontal reversals; slow or diagonal movement
  never counts, so ordinary mousing can't trigger a rescue.
- **Work Across Macs…**: enables raw HID monitoring (see Permissions)
- **Launch at Login**
- **Check for Updates…** / **Check Automatically**: a lightweight check
  against GitHub's latest release (no Sparkle, nothing auto-downloaded). If
  a newer version exists it points you at the brew command or the release
  page. The automatic check runs on launch at most once a day and can be
  turned off.

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

## Troubleshooting: "Work Across Macs" stops working after an update

macOS binds the Input Monitoring grant to an app's code-signature identity
(its *designated requirement*). Mousetrapped's released builds all share one
stable Developer ID identity, so the grant is meant to carry across updates.

Two things can still break it:

- **You granted permission to a differently-signed copy.** A build you
  compiled yourself with a different certificate (e.g. an Apple Development
  cert) has a different designated requirement than the released Developer
  ID build, even though the bundle identifier is the same. macOS then holds
  conflicting Input Monitoring state and the grant flaps on update. `build.sh`
  now prefers your Developer ID identity to avoid this; the released cask
  build is always Developer ID signed.
- **A TCC glitch after replacing the bundle.** macOS sometimes keeps showing
  the app as allowed while silently not delivering input. Mousetrapped
  detects this (input reaches the Mac, a mouse is attached, but the raw HID
  stream is dead) and offers to help.

Clean fix, after which updates should persist:

```bash
tccutil reset ListenEvent dev.mousetrapped.Mousetrapped
```

Then relaunch Mousetrapped and enable it once more under System Settings →
Privacy & Security → Input Monitoring.

## Trackpad vs. mouse across Macs

Shake and hotkey both rescue a lost cursor on the Mac they run on, trackpad
or mouse. Across Macs (Universal Control), there's one difference:

- **Hotkey (⌃⌥⌘M) always works**, trackpad or mouse — your hands are on the
  keyboard, so the reclaimed pointer is free to come home.
- **Shake works across Macs with a mouse, but not a trackpad.** A trackpad
  emits no raw pointer data (macOS synthesizes motion from multitouch), and
  the shake gesture is itself trackpad movement that keeps driving the
  pointer — so it can't pull the cursor back from another Mac. On a
  trackpad-only Mac, Mousetrapped points this out once and steers you to the
  hotkey for cross-Mac rescues.

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
- Trackpad only laptops with no mouse attacked controlling a remote mac via push through edge must use the keyboard hotkeys, as the touchpad eats the shake detection inputs for the host mac  

## License

[PolyForm Noncommercial 1.0.0](LICENSE.md): the source is free to use,
modify, and share, but **not for commercial use**. You can't sell it or ship
it inside a paid product.
