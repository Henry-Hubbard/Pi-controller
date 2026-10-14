# Seed Drop Controller OS

A Raspberry Pi 5 with a touchscreen that boots straight into one full-screen app: the seed-row,
rack and can controls, with the drone's camera beside them. It joins the drone's Wi-Fi by itself.

```
 Controller Pi 5 (this OS)                       DEXI drone
 ┌───────────────────────────┐   drone Wi-Fi    ┌─────────────────────────────────┐
 │ Chromium, full screen     │ ───────────────► │ rosbridge :9090                 │
 │   controller app ─────────┼── commands ─────►│   seed-payload service ──► servos│
 │   dashboard panel ────────┼── page ─────────►│ DEXI Dash :8000 (camera, flight) │
 └───────────────────────────┘                  └─────────────────────────────────┘
```

The controller only sends "drop red row" or "open can 2". The **drone** owns the positions, so
a dropped radio link can never leave anything half done: whatever was last commanded stays put.

| Folder | What it is | Where it goes |
|---|---|---|
| `drone/seed_payload` | The payload service: servo positions, the `/seed_payload/*` commands | On the drone |
| `drone/dexi-dash` | DEXI Dash, now with a compact `#embed` view for the controller | On the drone |
| `controller/` | The app, boot settings, kiosk service, `install.sh` | On the controller Pi |
| `build/` | Makes a flashable controller image | On your computer |

---

## 1. Drone setup (once)

Use VS Code on the drone (http://192.168.4.1:9999): drag the `drone` folder in, then open
**Terminal → New Terminal**.

```bash
cd ~/drone/dexi-dash && chmod +x *.sh && sudo ./install.sh          # dashboard on :8000
cd ~/drone/seed_payload && chmod +x *.sh && sudo ./install-drone.sh  # payload service
```

**Set the servo positions before flying.** The angles in `payload.yaml` are placeholders.

1. Open DEXI Dash (http://192.168.4.1:8000) → **Servos & GPIO** and find each servo's
   loaded and dropped angle with its slider.
2. Write them into `/home/dexi/seed_payload/payload.yaml` (`hold` = loaded/closed,
   `release` = dropped/open). Row labels set here are the names on the controller.
3. `sudo systemctl restart seed-payload`

Default wiring (change it in `payload.yaml`):

| Output | Rows | Rack | Cans |
|---|---|---|---|
| PCA9685 channel | 0 red, 1 green, 2 blue | 3 | 4, 5, 6, 7 |

> **Eight outputs are needed.** The Pi 5 hat's labelled servo headers cover channels 0–4. Cans 2–4
> on channels 5–7 need those channels broken out, a second board, or moving some
> actuators to GPIO pins (`type: gpio`, for a solenoid or relay).

Check it: `journalctl -u seed-payload -f` shows each command as you flip switches.

## 2. Controller setup

### Option A: install onto Raspberry Pi OS (simplest)

This kit does not contain an OS image, so copying it onto an SD card will not boot.

1. Flash **Raspberry Pi OS Lite (64-bit)** with Raspberry Pi Imager. In its settings, set a
   username and password, and the Wi-Fi of a network **with internet** (the install downloads
   Chromium). Turn on SSH if you want it.
2. Before ejecting the card, copy the `controller` folder onto the card's **bootfs** drive.
3. Boot the Pi, log in, and run:
   ```bash
   cp -r /boot/firmware/controller ~/ && cd ~/controller && sudo bash install.sh
   sudo nano /boot/firmware/seedctl.conf     # set DRONE_SSID
   sudo reboot
   ```

### Option B: build a ready-to-flash image

On a Linux machine with root, or with Docker on a Mac or Windows:

```bash
sudo ./build/build-image.sh        # Linux
./build/docker-build.sh            # Docker
```

This downloads Pi OS Lite, installs the controller inside it, and writes `out/seedctl-os.img`.
Flash it with Raspberry Pi Imager (**Choose OS → Use custom**). Admin login for SSH or a keyboard:
`seedadmin` / `seedctl` (set `ADMIN_USER` / `ADMIN_PASSWORD` when building, or run `passwd`).

## 3. Settings: `seedctl.conf` on the SD card

The file is on the card's boot partition (the drive called **bootfs** when the card is in a
laptop), so you can change drones without a keyboard. It applies at the next power-on.

| Setting | Meaning |
|---|---|
| `DRONE_SSID` | The drone's hotspot, e.g. `dexi-a41f`. **Required.** |
| `DRONE_PASSWORD` | Hotspot password, `droneblocks` by default |
| `WIFI_COUNTRY` | Two-letter code. Wi-Fi stays off without it. |
| `DRONE_IP` | `192.168.4.1` on the DEXI hotspot |
| `DASHBOARD_URL` | Right-hand panel. `http://{ip}:8000/#embed` is DEXI Dash's compact view. |
| `ROW_COLORS` | Colors of the three rows on screen |
| `DISPLAY_ROTATION` | `0`, `90`, `180` or `270` |

## Using it

Order on screen, left to right in the step bar: **Drop seed rows → Release rack → Grab cans → Drop cans**.

- Every switch shows what the **drone** reports, not just what you tapped. A spinner in the knob
  means the servo is moving; a red **Error** pill means the drone could not move it.
- Two switches ask first, because they can't be undone in the air: **releasing the rack**, and
  **opening all four grippers** while they hold cans.
- On boot the drone moves everything to its hold position (`startup: hold`), so the rack stays
  latched and cans stay held if the drone reboots mid-flight.
- Top right: **Connected**, **Searching for drone** (no Wi-Fi link), or **Payload service not
  running** (drone found, but `seed-payload` is down). Controls grey out unless connected.
- The dashboard panel's expand button makes it full screen; tap it again to come back.

## If it doesn't start

- **The screen app keeps failing:** after 4 tries in 2 minutes it stops and shows a login
  prompt instead of looping. Each time it stops, it saves **`seedctl-log.txt`** to the SD card's
  boot partition. Put the card in a laptop, open the **bootfs** drive, and read that file.
- **Boot to a login prompt on purpose:** put an empty file named **`seedctl-off`** on the boot
  partition. Delete it to bring the app back.
- **The whole Pi restarts** (rainbow screen or Raspberry Pi logo again and again): that is power or
  the operating system, not the app. A Pi 5 with a screen needs the official 27 W (5 V 5 A) USB-C
  supply. After logging in, `vcgencmd get_throttled` should say `throttled=0x0`.

## Maintenance

- **SSH:** `ssh <admin>@<controller-ip>`. The controller is on the drone's network, so connect your
  laptop to the same hotspot.
- **Keyboard:** Ctrl+Alt+F2 for a text console.
- **Logs:** `journalctl -u seedctl-kiosk -u seedctl-setup -b`
- **Update the app:** copy a new `controller` folder over and run `sudo ./install.sh` again.
  Your `seedctl.conf` is kept.
- **Optional read-only card** (survives pulling the power at any moment):
  `sudo raspi-config nonint enable_overlayfs` then reboot. Undo with `disable_overlayfs`.
  Settings on the boot partition still apply each boot.
- **Try the app on a laptop:** open `controller/app/index.html?demo` in a browser.

## What has and hasn't been tested

Tested here: the payload logic (unit tests in `drone/seed_payload`), the full controller app
against a stand-in drone running the same payload logic, the boot settings script, and DEXI Dash's
embed view. Not yet run on hardware: the image build, the kiosk on a real Pi 5 and touchscreen,
and the ROS node on the drone. Things most likely to need a tweak on first boot:

- **Screen rotation.** For a portrait-native panel turned sideways (e.g. Touch Display 2), check
  that touches land in the right place after setting `DISPLAY_ROTATION`.
- **The display itself.** If the screen stays black, add your display's line to `config.txt` on
  the boot partition (from its setup guide).
- **Wi-Fi range.** The Pi's built-in Wi-Fi to the drone's hotspot is short-range. A USB Wi-Fi
  adapter with an external antenna on the controller is the first upgrade to try.
