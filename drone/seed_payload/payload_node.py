#!/usr/bin/env python3
"""seed_payload: ROS 2 node that owns the seeding rack and the four can grippers.

The controller (or any rosbridge client) talks to it with plain std_srvs/SetBool:

  /seed_payload/row_1 .. row_3   data=true drops that seed row, false resets the bar
  /seed_payload/rack             data=true releases the whole seeding rack
  /seed_payload/can_1 .. can_4   data=true opens that gripper (drops the can), false closes it
  /seed_payload/grab_all         data=true closes all four grippers, false opens all four

and reads /seed_payload/state (std_msgs/String, JSON) twice a second and on
every change. Each command is one position, so a lost radio link can never
leave something half done: whatever was last commanded stays put.

Servos go through DEXI's /dexi/servo_control, digital pins through
/dexi/gpio_writer_service/write_gpio. Positions are set in payload.yaml.
"""

import json
import os
import sys
from functools import partial

import rclpy
import yaml
from rclpy.node import Node
from std_msgs.msg import String
from std_srvs.srv import SetBool

from dexi_interfaces.srv import GPIOSend, ServoControl

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from payload_core import CANS, NAMES, ConfigError, PayloadCore  # noqa: E402

DEFAULT_CONFIG = os.path.join(os.path.dirname(os.path.abspath(__file__)), "payload.yaml")


class SeedPayload(Node):
    def __init__(self):
        super().__init__("seed_payload")
        path = self.declare_parameter("config_file", DEFAULT_CONFIG).value
        with open(path) as f:
            cfg = yaml.safe_load(f)
        self.servo_cli = self.create_client(ServoControl, "/dexi/servo_control")
        self.gpio_cli = self.create_client(GPIOSend, "/dexi/gpio_writer_service/write_gpio")
        self.core = PayloadCore(cfg, self.send_servo, self.send_gpio, on_change=self.publish)
        self.pub = self.create_publisher(String, "/seed_payload/state", 10)

        for name in NAMES:
            self.create_service(SetBool, f"/seed_payload/{name}", partial(self.on_set, name))
        self.create_service(SetBool, "/seed_payload/grab_all", self.on_grab_all)
        self.create_timer(0.5, self.publish)

        uses_servo = any(a["type"] == "servo" for a in self.core.acts.values())
        uses_gpio = any(a["type"] == "gpio" for a in self.core.acts.values())
        self.needs = [c for c, used in ((self.servo_cli, uses_servo), (self.gpio_cli, uses_gpio)) if used]
        self.startup_timer = self.create_timer(1.0, self.try_startup)
        self.startup_waited = 0
        self.get_logger().info(f"seed_payload ready, config {path}")

    # Command every actuator to its startup position once DEXI's servo/GPIO nodes are up.
    def try_startup(self):
        self.startup_waited += 1
        if all(c.service_is_ready() for c in self.needs) or self.startup_waited > 60:
            self.startup_timer.cancel()
            if self.startup_waited > 60:
                self.get_logger().warn("servo/GPIO service not up after 60 s; startup positions sent anyway")
            self.core.startup()

    # ---- service handlers ----
    def on_set(self, name, req, res):
        res.success, res.message = self.core.set(name, req.data)
        self.get_logger().info(f"{name} -> {'release' if req.data else 'hold'}")
        return res

    def on_grab_all(self, req, res):
        res.success, res.message = self.core.grab_all(req.data)
        self.get_logger().info(f"grab_all -> {req.data}")
        return res

    # ---- hardware ----
    def _call(self, client, req, what, done):
        if not client.service_is_ready():
            done(False, f"{what} is not running")
            return
        fut = client.call_async(req)

        def finished(f):
            try:
                r = f.result()
                done(bool(r.success), r.message)
            except Exception as e:  # noqa: BLE001
                done(False, str(e))

        fut.add_done_callback(finished)

    def send_servo(self, channel, angle, min_pw, max_pw, done):
        req = ServoControl.Request()
        req.pin, req.angle, req.min_pw, req.max_pw = int(channel), int(angle), int(min_pw), int(max_pw)
        self._call(self.servo_cli, req, "/dexi/servo_control", done)

    def send_gpio(self, pin, value, done):
        req = GPIOSend.Request()
        req.pin, req.state = int(pin), bool(value)
        self._call(self.gpio_cli, req, "/dexi/gpio_writer_service/write_gpio", done)

    def publish(self):
        if hasattr(self, "pub"):
            self.pub.publish(String(data=json.dumps(self.core.snapshot())))


def main():
    rclpy.init()
    try:
        node = SeedPayload()
    except (ConfigError, OSError, yaml.YAMLError) as e:
        print(f"seed_payload: bad config: {e}", file=sys.stderr)
        sys.exit(2)
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        node.destroy_node()
        rclpy.try_shutdown()


if __name__ == "__main__":
    main()
