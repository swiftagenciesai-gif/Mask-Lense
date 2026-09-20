# MaskLens

An iOS app (Swift/SwiftUI, iOS 18+, targeting a standard non-LiDAR iPhone
like the iPhone 17) that pairs over local WiFi with a wearable mask — an
ESP32-CAM for video, plus a second small ESP32 driving a transparent OLED
behind a loupe lens — and adds AI features via the Claude API.

```
┌─────────────────┐   MJPEG/HTTP    ┌───────────────────┐   UDP status   ┌──────────────────┐
│  ESP32-CAM       │ ───────────▶   │   iPhone (app)     │ ─────────────▶ │  ESP32 + OLED     │
│  (mask camera)   │   local WiFi    │   Vision + RealityKit│  local WiFi   │  (mask display)   │
└─────────────────┘                 │   + Claude API     │                └──────────────────┘
                                     └───────────────────┘
```

**Read this whole README before you start building.** This project has
several genuinely hard parts — hand tracking on a compressed WiFi video
feed, 3D reconstruction with no LiDAR, a $25-40 display path that is not
a real waveguide — and this document tries hard not to gloss over any of
them. The "Limitations" section near the end isn't boilerplate; it's the
list of things that will actually surprise you if you skip it.

## Why this is staged, and why you should build it in the same order

This is a large build spanning firmware, computer vision, 3D
reconstruction, and a paid cloud API. Trying to bring all of it up
against real hardware at once means that when something doesn't work,
you won't know which of five subsystems is at fault. Build and test in
this order — each stage only depends on the ones before it, and the app
itself is structured this way (see `MaskLens/Stages/`, one screen per
stage, independently testable):

1. **Mask → phone video streaming.** Flash the camera firmware, get a
   steady MJPEG feed into the app (`Stage1VideoView`). Don't move on
   until this is boring and reliable.
2. **Hand tracking on that stream.** `VNDetectHumanHandPoseRequest` +
   the gesture registry, watched via a debug HUD with no 3D model in the
   loop yet (`Stage2HandTrackingView`).
3. **Object Capture reconstruction.** Turntable photo capture from the
   mask's camera → `PhotogrammetrySession` → RealityKit viewer, with the
   Stage 2 gestures now driving the model (`Stage3ObjectCaptureView`).
4. **Claude API features.** Vision identification and voice Q&A, tested
   independently of Stages 2-3 (`Stage4AIView`).
5. **Phone → mask display feedback.** Send simplified state back to the
   OLED in sync with the model view (`Stage5DisplayFeedbackView`).

## Repository layout

```
MaskLens/                     iOS app source
  App/                        App entry, root tab view, Settings
  Networking/                 Bonjour discovery, MJPEG receiver, UDP display link
  Vision/                     Hand pose tracking + extensible gesture registry
  ObjectCapture/              Turntable capture UI + PhotogrammetrySession wrapper
  Rendering/                  RealityKit model viewer, mask display HUD renderer
  AI/                         Claude API client, vision ID, voice assistant, mesh QA
  Config/                     Settings + Keychain-backed API key storage
  Stages/                     One screen per build stage (see above)
MaskLensTests/                Unit tests for gesture logic (no hardware required)
Firmware/
  camera-esp32cam/            ESP32-CAM MJPEG streamer sketch
  display-esp32/              ESP32 + OLED UDP display sketch
  README.md                   Firmware-specific setup guide
project.yml                   XcodeGen project spec (see below — read this)
Config/Secrets.example.xcconfig  Optional dev-only API key convenience
```

## Building the Xcode project

**This repository does not include a checked-in `.xcodeproj`.** It was
built in a Linux environment with no Xcode/macOS toolchain available to
generate or validate one, and hand-writing a binary/plist project file
with no way to open or lint it is a good way to hand you a corrupted
project that won't open. Instead, the project is specified declaratively
via [XcodeGen](https://github.com/yonaskolb/XcodeGen)'s `project.yml`,
which is a normal, common way to check Xcode projects into source control
specifically because it avoids merge-conflict-prone `.pbxproj` files.

On a Mac, with Xcode installed:

```sh
brew install xcodegen
cd MaskLens   # repo root, where project.yml lives
xcodegen generate
open MaskLens.xcodeproj
```

That's a one-time step (re-run it if you add/remove source files outside
Xcode, or edit `project.yml`). From then on it behaves like any other
Xcode project — build and run onto a physical iPhone (the mask's camera
feed and hand tracking need a real device; the Simulator has no camera
input to speak of and no way to reach your LAN's mDNS traffic reliably
either).

**Deployment target is iOS 18.0**, chosen because RealityKit's SwiftUI
`RealityView` (used in `ModelViewerView.swift`) and the on-device Object
Capture (`PhotogrammetrySession`) pipeline both want a recent iOS/RealityKit
version. You'll need a matching Xcode version to build for it.

You will also need to set your own Team/bundle identifier for code
signing in Xcode's Signing & Capabilities tab (`project.yml` leaves
`DEVELOPMENT_TEAM` blank on purpose) — this isn't something a repo can
ship for you.

## Pairing with the mask hardware

1. Flash both ESP32 boards — full instructions in `Firmware/README.md`,
   including required libraries, wiring, and flashing quirks specific to
   each board.
2. Put the phone on the same WiFi network as both boards (or run the
   ESP32s in AP mode and join the phone to that network — either works;
   the app doesn't care, it just needs to reach both boards' IPs).
3. Open the app → **Stages** tab → **Stage 1: Video**. It tries mDNS
   discovery automatically; tap a discovered host to connect, or go to
   **Settings** → enable "Use manual IP addresses" and type in the IP
   each board printed over serial at boot.
4. Work through Stages 2-5 in order as described above.

mDNS/Bonjour discovery is convenient when it works, but plenty of home
routers — guest networks especially, and a lot of mesh WiFi systems with
client isolation enabled — silently block the multicast traffic it needs,
even though both devices are visibly on the same WiFi. If Stage 1 can't
find your camera board within a few seconds, don't assume something's
broken — switch to manual IP entry, which is the reliable path.

## Plugging in a Claude API key

1. Get a key from the [Anthropic Console](https://console.anthropic.com/).
2. In the app: **Settings** tab → **Claude API Key** → paste it → **Save
   Key**.
3. That's it — the key is stored in the iOS **Keychain**
   (`MaskLens/Config/APIKeyStore.swift`), not in source, not in a plist,
   not in `UserDefaults`. It never touches git.

There's also `Config/Secrets.example.xcconfig`, a documented, git-ignored
dev convenience for advanced use (e.g. scripting Simulator runs). It is
not wired into the build by default and is not the recommended path —
read the comments in that file before using it, and never ship a build
with a key baked in that way.

### This calls a paid API on every vision/voice request

Every tap of "What am I looking at?" and every voice question sends a
request to `api.anthropic.com` and costs money. There is no caching,
batching, or free tier built into this app. Concretely:

- **Vision identification** sends one downscaled JPEG (≤1024px on the
  long edge) plus a short prompt per request.
- **Voice Q&A** sends the transcribed text (transcription itself is free
  and on-device via Apple's Speech framework — only the Claude call
  costs anything) plus a short system prompt per request.
- The optional Stage 3 "capture quality" pass sends one more image per
  completed 3D capture, only if you have an API key configured.

None of this is metered or capped by the app — check current pricing on
Anthropic's site and set your own usage expectations. Your AT&T unlimited
data plan means mobile data itself isn't a limiting factor here; API
spend is the actual constraint, and it scales directly with how often you
tap those buttons, not with how long the app runs.

## Running the tests

`MaskLensTests/` covers the gesture recognition and manipulation-state
logic — pinch-to-scale locking without drift, arm/disarm debouncing,
rotation gating — entirely with synthetic hand-pose data, no camera or
network required. Run via `xcodegen generate` → open in Xcode → Cmd-U, or
`xcodebuild test` from the command line once the project is generated.
Everything else (video streaming, live hand tracking accuracy, Object
Capture quality, the Claude integrations) fundamentally needs real
hardware and a live network to validate — there's no meaningful way to
unit-test "does this look right through the loupe lens."

## Limitations — read this before you're surprised by it

**WiFi range and latency between mask and phone.** Both links are plain
local WiFi, not a purpose-built low-latency radio protocol. Expect
noticeably reduced range and reliability compared to, say, Bluetooth
earbuds — WiFi's range depends heavily on your router, walls, and 2.4 vs
5GHz band, and the ESP32-CAM in particular has a fairly weak transmitter
and antenna compared to a phone. Realistically expect solid performance
within the same room as your router and degrading badly beyond ~10-15m
or through multiple walls. There is no fallback to a direct
phone-to-ESP32 ad hoc link in this build — both boards need a WiFi
network they and the phone can all reach (a home network, or the boards'
own AP mode with the phone joined to it).

**Phone battery drain.** This app simultaneously receives continuous
video over WiFi, decodes JPEG frames, runs Vision framework hand-pose
detection per frame, and (in Stage 5) sends UDP packets back out — before
any Claude API calls, which add their own network activity. This is a
meaningfully heavier combined load than typical camera-app usage. Expect
noticeably faster battery drain than normal phone use, especially with
Stages 2 and 5 both active; there's no specific mitigation built in
beyond throttling the display feedback rate (`AppSettings.displayFeedbackFPS`,
default 8fps) and dropping (not queueing) Vision frames when processing
falls behind, both of which help but don't eliminate the load.

**Object Capture processing time and robustness without LiDAR.** This
app uses `PhotogrammetrySession` directly rather than Apple's higher-level
`ObjectCaptureSession`/`ObjectCaptureView`, because those are built
around the *phone's own* camera and don't accept externally-sourced
frames — and the mask's camera is external by design. That means:
  - No LiDAR-assisted depth, so reconstruction is feature-matching from
    2D photos alone. Expect it to struggle more than a LiDAR-equipped Pro
    device would with plain/textureless surfaces, reflective or
    transparent materials, and thin structures — all cases where feature
    matching has little to grab onto.
  - No automatic per-shot coverage/blur feedback or object masking (both
    things `ObjectCaptureSession` gives you against local camera input
    for free). The turntable capture flow here is manual-shutter with a
    simple shot-count target; see `PhotogrammetryCoordinator.swift` and
    `TurntableCaptureViewModel.swift` for the full reasoning.
  - Processing itself is genuinely slow: expect low-to-mid single-digit
    minutes for a few dozen photos at the on-device `.reduced` detail
    level, longer for more shots or trickier objects. Keep the phone
    plugged in and awake while it runs. There's no way around this —
    photogrammetry is compute-heavy, full stop.

**Hand-tracking accuracy on a streamed vs. locally captured feed.**
`VNDetectHumanHandPoseRequest` is tuned against Apple's expectations for
local `AVCaptureSession` input — sharp, evenly-timed, uncompressed
frames. This app instead feeds it JPEG-compressed frames arriving over
WiFi from a small, mediocre-in-low-light camera sensor, at a lower and
less even frame rate than local capture. Expect: more frames where a hand
is visible but confidence is too low to use (worse in dim light, motion
blur, or JPEG block artifacts near fingertips); a fast pinch occasionally
being missed entirely if two frames land close together and Vision
processing falls behind (frames are dropped, not queued, to keep latency
bounded — see `HandPoseTracker.swift`); and generally a less silky-smooth
feel than Apple's own hand-tracking demo videos, which are shot under
much friendlier conditions. The thresholds in `BuiltInGestures.swift`
(pinch engage/disengage distance, palm-open/fist spread ratios) are
starting points — plan to tune them against your actual mask camera and
lighting, not just what feels right in the simulator (which can't
exercise this path at all, since there's no live stream to test there).

**The display path is a budget compromise, not a waveguide.** A 0.96"
transparent OLED behind a $5-15 loupe lens (~$25-40 total) is not a
substitute for a real waveguide AR combiner costing 50-100x as much.
Expect a small, lens-position-sensitive focus sweet spot that needs
manual tuning per build (see `Firmware/README.md`'s lens-tuning section —
do this before gluing anything down), a narrower eye-box than a waveguide
would give you, and visibly more edge distortion and less daylight
contrast. It's a genuinely usable low-cost HUD for simple status
(armed/disarmed, scale, a rotation indicator — which is deliberately all
`MaskFrameRenderer.swift` tries to show), not a full-fidelity mirror of
the RealityKit render.

## What's intentionally out of scope / stretch-only

- **Mesh cleanup via Claude** (`MeshCleanupService.swift`) sends a couple
  of the capture photos to Claude for a plain-language "here's what might
  be wrong with your capture coverage" note. Claude's vision API takes
  images, not 3D geometry — it cannot edit the mesh, fill holes, or
  decimate it. Treat this as capture-quality advice, not mesh repair.
- **Wake-word / always-listening voice control** is not implemented —
  the voice assistant is push-to-talk on purpose. See the comment at the
  top of `VoiceAssistantController.swift` for the battery/privacy
  reasoning; wiring a real wake word later is a reasonable follow-up but
  a materially bigger battery cost than what's here.
