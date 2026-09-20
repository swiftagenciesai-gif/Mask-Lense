/*
 * MaskLens — camera board firmware (AI-Thinker ESP32-CAM)
 * ---------------------------------------------------------------
 * Serves an MJPEG stream at http://<board-ip>/stream and advertises
 * itself over mDNS as `_masklens-cam._tcp` so the iOS app can find it
 * without you typing an IP address (though see the README — mDNS is
 * unreliable enough on some routers that you should expect to need the
 * manual-IP fallback in the app's Settings screen at least once).
 *
 * Board: AI-Thinker ESP32-CAM (the ~$8-10 module, OV2640 camera). Pin
 * definitions below are specific to that board; a different ESP32-CAM
 * variant will need different CAMERA_MODEL_* pins from the esp32-camera
 * library's examples.
 *
 * Required libraries (install via Arduino Library Manager / board
 * manager, or PlatformIO):
 *   - "esp32" board package (Espressif) — provides esp_camera.h, WiFi.h
 *   - ESPmDNS (bundled with the esp32 board package)
 *
 * Flashing notes:
 *   - The ESP32-CAM has no onboard USB serial chip. You need a separate
 *     USB-to-serial adapter (FTDI/CP2102, 3.3V) wired to GND/5V/U0R/U0T.
 *   - Bridge GPIO0 to GND before power-on to enter flashing mode; remove
 *     the bridge and reset before running normally.
 *   - Board setting in Arduino IDE: "AI Thinker ESP32-CAM".
 *   - Brownout resets during flash/boot are extremely common on this
 *     board if powered from a USB adapter's 3.3V pin — use a supply that
 *     can source at least 500mA on 5V into the board's own regulator, not
 *     the adapter's 3.3V line.
 *
 * On first boot, open the Serial Monitor at 115200 baud — it prints the
 * IP address it got via DHCP. Use that as the manual fallback IP in the
 * app if mDNS discovery doesn't find it.
 */

#include "esp_camera.h"
#include <WiFi.h>
#include <WiFiClient.h>
#include <WiFiServer.h>
#include <ESPmDNS.h>

// ---- Fill in before flashing ----
const char *WIFI_SSID = "YOUR_WIFI_SSID";
const char *WIFI_PASSWORD = "YOUR_WIFI_PASSWORD";
// ----------------------------------

#define CAMERA_MODEL_AI_THINKER
#include "camera_pins.h" // see camera_pins.h in this folder

WiFiServer server(80);

static const char *STREAM_BOUNDARY = "masklensboundary";

void startCamera() {
  camera_config_t config;
  config.ledc_channel = LEDC_CHANNEL_0;
  config.ledc_timer = LEDC_TIMER_0;
  config.pin_d0 = Y2_GPIO_NUM;
  config.pin_d1 = Y3_GPIO_NUM;
  config.pin_d2 = Y4_GPIO_NUM;
  config.pin_d3 = Y5_GPIO_NUM;
  config.pin_d4 = Y6_GPIO_NUM;
  config.pin_d5 = Y7_GPIO_NUM;
  config.pin_d6 = Y8_GPIO_NUM;
  config.pin_d7 = Y9_GPIO_NUM;
  config.pin_xclk = XCLK_GPIO_NUM;
  config.pin_pclk = PCLK_GPIO_NUM;
  config.pin_vsync = VSYNC_GPIO_NUM;
  config.pin_href = HREF_GPIO_NUM;
  config.pin_sscb_sda = SIOD_GPIO_NUM;
  config.pin_sscb_scl = SIOC_GPIO_NUM;
  config.pin_pwdn = PWDN_GPIO_NUM;
  config.pin_reset = RESET_GPIO_NUM;
  config.xclk_freq_hz = 20000000;
  config.pixel_format = PIXFORMAT_JPEG;

  // VGA (640x480) is a practical sweet spot: high enough resolution for
  // Vision hand tracking to have something to work with, low enough that
  // WiFi + JPEG decode on the phone keep up. Bumping to SVGA/XGA will
  // look sharper on the mask display path but will directly cost you
  // frame rate — see the top-level README's latency/bandwidth notes
  // before turning this up.
  if (psramFound()) {
    config.frame_size = FRAMESIZE_VGA;
    config.jpeg_quality = 12; // lower number = higher quality = bigger frames
    config.fb_count = 2;
  } else {
    config.frame_size = FRAMESIZE_SVGA;
    config.jpeg_quality = 15;
    config.fb_count = 1;
  }

  esp_err_t err = esp_camera_init(&config);
  if (err != ESP_OK) {
    Serial.printf("Camera init failed with error 0x%x\n", err);
    delay(2000);
    ESP.restart();
  }
}

void handleStreamClient(WiFiClient &client) {
  client.println("HTTP/1.1 200 OK");
  client.print("Content-Type: multipart/x-mixed-replace; boundary=");
  client.println(STREAM_BOUNDARY);
  client.println();

  while (client.connected()) {
    camera_fb_t *fb = esp_camera_fb_get();
    if (!fb) {
      Serial.println("Camera capture failed");
      break;
    }

    client.print("--");
    client.println(STREAM_BOUNDARY);
    client.println("Content-Type: image/jpeg");
    client.print("Content-Length: ");
    client.println(fb->len);
    client.println();
    client.write(fb->buf, fb->len);
    client.println();

    esp_camera_fb_return(fb);

    if (!client.connected()) break;
    // No artificial delay here — frame rate is naturally limited by
    // sensor readout + JPEG encode + WiFi send time. Realistically expect
    // roughly 10-15fps at VGA on a typical AI-Thinker board and home
    // router; don't expect smartphone-camera smoothness.
  }
}

void setup() {
  Serial.begin(115200);
  Serial.setDebugOutput(false);

  startCamera();

  WiFi.mode(WIFI_STA);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  Serial.print("Connecting to WiFi");
  while (WiFi.status() != WL_CONNECTED) {
    delay(400);
    Serial.print(".");
  }
  Serial.println();
  Serial.print("Camera board IP: ");
  Serial.println(WiFi.localIP());

  if (MDNS.begin("masklens-cam")) {
    MDNS.addService("masklens-cam", "tcp", 80);
    Serial.println("mDNS responder started as masklens-cam.local");
  } else {
    Serial.println("mDNS setup failed — use the manual IP fallback in the app.");
  }

  server.begin();
}

void loop() {
  WiFiClient client = server.available();
  if (client) {
    String requestLine = client.readStringUntil('\r');
    client.readStringUntil('\n'); // discard rest of first line's \n
    // Drain remaining request headers.
    while (client.available()) {
      String line = client.readStringUntil('\n');
      if (line == "\r") break;
    }

    if (requestLine.indexOf("GET /stream") >= 0) {
      handleStreamClient(client);
    } else {
      client.println("HTTP/1.1 404 Not Found");
      client.println("Connection: close");
      client.println();
    }
    client.stop();
  }
}
