# MaskLens Firmware

Two independent ESP32 boards, two independent sketches. Neither talks to
the other — both talk to the iOS app over the local WiFi network.

```
[ESP32-CAM]  --MJPEG over HTTP-->  [iPhone]  --UDP status frames-->  [ESP32 + OLED]
   camera                        app brain                        loupe display
```

## 1. Camera board — `camera-esp32cam/`

**Hardware:** AI-Thinker ESP32-CAM module (~$8-10), the cheapest and most
common ESP32-CAM board. It has an OV2640 camera and a microSD slot you
don't need for this project.

**Libraries:** the `esp32` board package from Espressif (Boards Manager
in Arduino IDE, or `platform = espressif32` in PlatformIO). Everything
used (`esp_camera.h`, `WiFi.h`, `ESPmDNS.h`) ships with that package —
no separate camera library to install.

**Flashing:** the AI-Thinker board has **no onboard USB-serial chip**.
You need a separate 3.3V USB-to-serial adapter (FTDI, CP2102, etc.):

| Adapter | ESP32-CAM |
|---|---|
| 5V | 5V |
| GND | GND |
| TX | U0R (RX) |
| RX | U0T (TX) |

Bridge **GPIO0 to GND** before powering on to enter flash mode. Flash,
then remove the bridge and press reset (or power-cycle) to run normally.

Brownout resets during flashing/boot are extremely common with this board
— they're almost always a power problem, not a firmware bug. Power from
the adapter's 5V pin into the board's own onboard regulator (not the
adapter's 3.3V pin directly), and use an adapter/supply that can source
at least 500mA.

Edit `WIFI_SSID` / `WIFI_PASSWORD` at the top of `camera_esp32cam.ino`
before flashing.

**Finding it on the network:** it advertises itself via mDNS as
`_masklens-cam._tcp` (service name `masklens-cam`), which the app tries
to discover automatically. Also open the Serial Monitor at 115200 baud
right after boot — it prints the DHCP-assigned IP address, which you can
type into the app's Settings screen manually if mDNS discovery doesn't
find it (see the top-level README for why that happens more than you'd
expect).

**Stream:** `http://<ip>/stream`, `multipart/x-mixed-replace` MJPEG,
matching what `CameraStreamReceiver.swift` parses.

**Realistic frame rate:** roughly 10-15fps at VGA (640x480) on a typical
home router and a clean 2.4GHz channel. Expect it to drop under WiFi
congestion, at range, or if you push the resolution up in
`camera_esp32cam.ino`'s `frame_size` setting — that's a direct tradeoff
against both frame rate and the phone's decode/Vision-processing load.

## 2. Display board — `display-esp32/`

**Hardware:** any generic ESP32 dev board (most have a built-in
USB-serial chip, so flashing is simpler than the camera board) driving a
Waveshare 0.96" transparent OLED (SSD1312 family controller), mounted
behind a small magnifier/loupe lens.

**Libraries:** the `esp32` board package, plus **U8g2** (by olikraus) —
install via Library Manager. `SPI.h` ships with the board package.

**Verify your exact panel before wiring:** "SSD1312" names a controller
family; Waveshare sells more than one 0.96" transparent OLED SKU, and
they aren't guaranteed to share a resolution or interface. Check U8g2's
supported-constructor list against your specific module's datasheet.
`display_esp32.ino` uses an SSD1306-compatible constructor as a
starting template (this controller family is close enough to SSD1306
timing in many cases that it works, but that is "try it," not a
guarantee) — if your panel needs a different constructor or wiring,
swap it in; the rest of the sketch (UDP parsing, drawing calls) doesn't
change.

**Wiring (SPI, matching the pin `#define`s at the top of the sketch —
change both to match your actual wiring):**

| OLED pin | ESP32 pin |
|---|---|
| CS | GPIO5 |
| DC | GPIO16 |
| RST | GPIO17 |
| CLK/SCK | GPIO18 |
| MOSI/DIN | GPIO23 |
| VCC | 3.3V |
| GND | GND |

Edit `WIFI_SSID` / `WIFI_PASSWORD` before flashing.

**Finding it on the network:** advertises as `_masklens-disp._tcp`
(service name `masklens-disp`); same manual-IP fallback via Serial
Monitor applies as above. It listens for UDP packets on port **4210** —
see `MaskLens/Networking/DisplayLinkSender.swift` for the exact wire
format it expects (a 1-bpp bitmap packet or a short text-status packet).

### Tuning the lens — do this before gluing anything

This is the budget display path (~$25-40 for display + lens), not a real
waveguide AR module, and it shows: the sweet spot where the image is in
focus is small, and it's specific to your exact lens-to-panel distance,
which varies by lens and by how you've mounted the panel.

Before permanently mounting anything: power the display board, put a
static test pattern on it (the sketch's default "Waiting for phone..."
text works fine), hold the lens in front of your eye, and slide it back
and forth relative to the panel until the text is sharp. Only once
you've found that distance should you fix the lens and panel in place —
plan for an adjustable mount (even something as crude as a lens that
slides in a tube and gets friction-fit or hot-glued at the end) rather
than committing to a fixed distance up front.

Compared to a real waveguide combiner, expect: a narrower eye-box (small
head movements can lose the image entirely), more visible distortion
toward the edges of the panel, and less brightness/contrast in daylight
— the "transparent OLED behind a lens" approach is genuinely a budget
compromise, not a lookalike for hardware costing 50-100x more.

## Battery life (both boards)

Rough, not measured on your specific LiPo/regulator combo — treat these
as starting expectations, not promises:

- **ESP32-CAM streaming continuously over WiFi:** WiFi TX is the biggest
  draw on this board. On a small 500mAh LiPo, expect on the order of
  **1-2 hours** of continuous streaming. A 1000-2000mAh pack (still small
  enough to be wearable) roughly scales that up proportionally, so
  2.5-4+ hours is realistic with a 2000mAh pack, hardware/losses
  permitting.
- **Display board:** lighter load (small OLED, occasional UDP receive,
  no camera/JPEG encode), so a given battery size will noticeably
  outlast the camera board — but it's still WiFi-connected the whole
  time, which dominates over the display's own tiny power draw.
- Both numbers assume a basic LiPo + a simple boost/charge circuit (e.g.
  a common TP4056 + boost module) with the efficiency losses that
  implies, not a hand-tuned power design. Deep-sleep between frames isn't
  compatible with "continuous live stream," so there's no free win there
  for the camera board specifically.

## Both sketches: things worth double-checking on your specific boards

- ESP32-CAM module *variants* (not just AI-Thinker) use different GPIO
  pinouts for the camera interface — if you bought a different variant,
  swap `camera_pins.h` for the matching block from Espressif's own
  `CameraWebServer` example rather than assuming the AI-Thinker pinout
  in this repo is universal.
- WiFi credentials are hardcoded in both `.ino` files for simplicity.
  That's fine for a personal build; if you'll be reflashing often or
  sharing this code, consider `WiFiManager` or similar for runtime
  configuration instead.
