/*
 * MaskLens — display board firmware (generic ESP32 dev board + Waveshare
 * 0.96" transparent SSD1312 OLED)
 * ---------------------------------------------------------------
 * Listens for UDP packets from the iOS app (see
 * MaskLens/Networking/DisplayLinkSender.swift for the exact wire format)
 * and draws either a 1-bpp bitmap or a short text status string to the
 * OLED.
 *
 * Required libraries:
 *   - "esp32" board package (Espressif)
 *   - U8g2 (by olikraus) — https://github.com/olikraus/u8g2
 *
 * IMPORTANT — verify your controller/constructor before wiring this up:
 * "SSD1312" is a controller family, and different Waveshare SKUs of
 * "0.96 inch transparent OLED" pair it with different resolutions and
 * interfaces (SPI vs I2C, 128x64 vs other panel sizes). U8g2 may not have
 * an exact `u8g2_Setup_ssd1312_...` constructor for your specific module —
 * check U8g2's supported-controller list against your board's datasheet,
 * or fall back to whatever demo code Waveshare ships for that exact SKU.
 * The constructor and pin wiring below are a *template* for a common SPI
 * wiring, not a guarantee it matches the module you bought.
 *
 * Flashing: standard ESP32 dev board flashing (this one usually has a
 * built-in USB-serial chip, unlike the ESP32-CAM) — just select the right
 * board in Arduino IDE / PlatformIO and upload.
 *
 * On first boot, check the Serial Monitor at 115200 baud for the IP
 * address to use as the manual fallback in the app's Settings screen.
 */

#include <WiFi.h>
#include <WiFiUdp.h>
#include <ESPmDNS.h>
#include <U8g2lib.h>
#include <SPI.h>

// ---- Fill in before flashing ----
const char *WIFI_SSID = "YOUR_WIFI_SSID";
const char *WIFI_PASSWORD = "YOUR_WIFI_PASSWORD";
// ----------------------------------

// SPI pin template — adjust to match your wiring / board.
#define OLED_CS   5
#define OLED_DC   16
#define OLED_RST  17
#define OLED_CLK  18
#define OLED_MOSI 23

// Placeholder constructor. Confirm the actual constructor name for your
// panel against U8g2's "full_buffer" constructor list — if SSD1312 isn't
// directly listed, panels in this family are frequently close enough to
// SSD1306/SH1106 timing that the SSD1306-compatible constructor works, but
// that is a "try it and see," not a guarantee.
U8G2_SSD1306_128X64_NONAME_F_4W_HW_SPI display(U8G2_R0, OLED_CS, OLED_DC, OLED_RST);

WiFiUDP udp;
const uint16_t UDP_PORT = 4210;

const int DISPLAY_WIDTH = 128;
const int DISPLAY_HEIGHT = 64;

uint8_t packetBuffer[2048];

void drawBitmapPacket(uint8_t *payload, size_t length) {
  if (length < 5) return;
  uint16_t width = payload[1] | (payload[2] << 8);
  uint16_t height = payload[3] | (payload[4] << 8);
  size_t expectedBytes = ((size_t)(width + 7) / 8) * height;

  if (length - 5 < expectedBytes || width != DISPLAY_WIDTH || height != DISPLAY_HEIGHT) {
    Serial.println("Bitmap packet size/resolution mismatch — dropping frame");
    return;
  }

  display.clearBuffer();
  display.drawXBM(0, 0, width, height, payload + 5);
  display.sendBuffer();
}

void drawTextPacket(uint8_t *payload, size_t length) {
  char text[65];
  size_t textLen = min(length - 1, sizeof(text) - 1);
  memcpy(text, payload + 1, textLen);
  text[textLen] = '\0';

  display.clearBuffer();
  display.setFont(u8g2_font_6x10_tf);
  display.drawStr(2, 12, text);
  display.sendBuffer();
}

void setup() {
  Serial.begin(115200);

  display.begin();
  display.clearBuffer();
  display.setFont(u8g2_font_6x10_tf);
  display.drawStr(2, 12, "MaskLens display");
  display.drawStr(2, 26, "Connecting WiFi...");
  display.sendBuffer();

  WiFi.mode(WIFI_STA);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  Serial.print("Connecting to WiFi");
  while (WiFi.status() != WL_CONNECTED) {
    delay(400);
    Serial.print(".");
  }
  Serial.println();
  Serial.print("Display board IP: ");
  Serial.println(WiFi.localIP());

  if (MDNS.begin("masklens-disp")) {
    MDNS.addService("masklens-disp", "tcp", UDP_PORT);
    Serial.println("mDNS responder started as masklens-disp.local");
  } else {
    Serial.println("mDNS setup failed — use the manual IP fallback in the app.");
  }

  udp.begin(UDP_PORT);

  display.clearBuffer();
  display.drawStr(2, 12, "Waiting for phone...");
  display.drawStr(2, 26, WiFi.localIP().toString().c_str());
  display.sendBuffer();
}

void loop() {
  int packetSize = udp.parsePacket();
  if (packetSize > 0 && packetSize <= (int)sizeof(packetBuffer)) {
    int len = udp.read(packetBuffer, sizeof(packetBuffer));
    if (len > 0) {
      uint8_t packetType = packetBuffer[0];
      if (packetType == 0x01) {
        drawBitmapPacket(packetBuffer, len);
      } else if (packetType == 0x02) {
        drawTextPacket(packetBuffer, len);
      }
    }
  }
}
