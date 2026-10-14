# DEXI Dash

An alternate DEXI dashboard. By default it runs on port 8000 next to the stock dashboard (port 80) and Node-RED (port 1880), which keep running unchanged. It has two views:

- **Monitor**: camera feed, attitude, battery, altitude, rangefinder, EKF state, flight controller messages, and the Pi's CPU, memory, temperature, disk and Wi-Fi.
- **Servos & GPIO**: five servo sliders (PCA9685 channels 0–4) plus an "All servos" slider, and the five TCA9555 GPIO pins (P0–P4) as on/off outputs or live inputs.

Built for the DroneBlocks Pi 5 hat, the only DEXI carrier with both chips.

## Install (from your laptop, joined to the drone's hotspot)

    ./deploy.sh                          # http://192.168.4.1:8000
    ./deploy.sh 10.0.0.42                # drone on your own Wi-Fi
    ./deploy.sh 192.168.4.1 8500         # a different port
    ./deploy.sh 192.168.4.1 --replace    # take over port 80 instead

SSH and sudo password: `dexi`.

No internet or Docker build needed: the dashboard has no dependencies and runs on the Node inside the stock `droneblocks/dexi-droneblocks` image, with `~/dexi-dash` mounted in, as its own container `dexi-dash`. It restarts with the drone. Ports DEXI already uses: 80, 1880, 8088, 9090, 9999.

To edit on the drone, change files in `~/dexi-dash/public` and refresh the browser. Changes to `server.js` need `docker restart dexi-dash`.

Remove DEXI Dash (and make sure the stock dashboard is on port 80): `sudo ~/dexi-dash/restore.sh`

## Try it without a drone

    PORT=8080 node server.js    # then open http://localhost:8080/?demo

Point a laptop copy at a real drone with `?host=192.168.4.1`.

## What it talks to

| Data | Source |
|---|---|
| Servos | service `/dexi/servo_control` (`dexi_interfaces/srv/ServoControl`) via rosbridge :9090 |
| GPIO out | service `/dexi/gpio_writer_service/write_gpio` (`dexi_interfaces/srv/GPIOSend`) |
| GPIO in | topics `/tca9555_controller/gpio_N_state` (`std_msgs/Bool`) |
| Camera | `/cam0/image_raw/compressed` |
| Flight telemetry | mavlink2rest :8088 |
| Pi health | `/api/system`, `/api/version` served by `server.js` |

GPIO direction is set when the GPIO node starts (`pin_N_mode` in `dexi_cpp/launch/tca9555_controller.launch.py`; default pins 0–2 output, 3–4 input). Match it under **Pin setup**.
