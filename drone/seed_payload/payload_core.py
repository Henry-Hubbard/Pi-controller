"""Seed payload logic, kept free of ROS so it can be tested on any computer.

Every actuator has two positions:
  hold    = loaded / closed / attached
  release = dropped / open / released

An actuator is a servo on the PCA9685 (angle per position) or a digital pin on
the TCA9555 (on/off per position). The ROS node wires the two send functions to
the DEXI services; tests wire them to fakes.
"""

import time

CANS = ("can_1", "can_2", "can_3", "can_4")
ROWS = ("row_1", "row_2", "row_3")
RACK = "rack"
NAMES = CANS + ROWS + (RACK,)


class ConfigError(ValueError):
    pass


def _int(spec, key, lo, hi, name):
    v = spec.get(key)
    if not isinstance(v, int) or isinstance(v, bool) or not lo <= v <= hi:
        raise ConfigError(f"{name}: '{key}' must be a whole number from {lo} to {hi} (got {v!r})")
    return v


def parse_config(cfg):
    """Check the YAML config and return {name: actuator spec}."""
    if not isinstance(cfg, dict) or not isinstance(cfg.get("actuators"), dict):
        raise ConfigError("config needs an 'actuators:' section")
    acts = cfg["actuators"]
    missing = [n for n in NAMES if n not in acts]
    if missing:
        raise ConfigError("config is missing actuators: " + ", ".join(missing))
    unknown = [n for n in acts if n not in NAMES]
    if unknown:
        raise ConfigError("unknown actuators in config: " + ", ".join(unknown) + " (expected " + ", ".join(NAMES) + ")")
    out = {}
    used_channels, used_pins = {}, {}
    for name in NAMES:
        spec = acts[name] or {}
        kind = spec.get("type", "servo")
        if kind == "servo":
            ch = _int(spec, "channel", 0, 15, name)
            if ch in used_channels:
                raise ConfigError(f"{name}: servo channel {ch} is already used by {used_channels[ch]}")
            used_channels[ch] = name
            item = {
                "type": "servo",
                "channel": ch,
                "hold": _int(spec, "hold", 0, 180, name),
                "release": _int(spec, "release", 0, 180, name),
                "min_pw": _int(spec, "min_pw", 400, 1500, name) if "min_pw" in spec else 0,
                "max_pw": _int(spec, "max_pw", 1500, 2600, name) if "max_pw" in spec else 0,
            }
        elif kind == "gpio":
            pin = spec.get("pin")
            if pin not in (0, 1, 2, 3, 4, 14, 15):
                raise ConfigError(f"{name}: 'pin' must be one of 0-4, 14, 15 (got {pin!r})")
            if pin in used_pins:
                raise ConfigError(f"{name}: GPIO pin {pin} is already used by {used_pins[pin]}")
            used_pins[pin] = name
            item = {"type": "gpio", "pin": pin, "release_high": bool(spec.get("release_high", True))}
        else:
            raise ConfigError(f"{name}: 'type' must be servo or gpio (got {kind!r})")
        item["label"] = str(spec.get("label") or name)
        out[name] = item
    startup = cfg.get("startup", "hold")
    if startup not in ("hold", "none"):
        raise ConfigError("'startup' must be hold or none")
    return out, startup


class PayloadCore:
    def __init__(self, cfg, send_servo, send_gpio, on_change=None, clock=time.time):
        self.acts, self.startup_mode = parse_config(cfg)
        self.send_servo = send_servo  # (channel, angle, min_pw, max_pw, done(ok, msg))
        self.send_gpio = send_gpio    # (pin, value, done(ok, msg))
        self.on_change = on_change or (lambda: None)
        self.clock = clock
        self.seq = 0
        self._token = {}
        # released: None = unknown (never commanded since start)
        self.state = {n: {"released": None, "pending": False, "ok": True, "error": ""} for n in NAMES}

    # ---- commands ----
    def set(self, name, released):
        if name not in self.acts:
            return False, f"unknown actuator {name}"
        a, st = self.acts[name], self.state[name]
        self._token[name] = token = self._token.get(name, 0) + 1
        st.update(released=bool(released), pending=True)
        self._changed()

        def done(ok, msg=""):
            # Ignore a late reply if a newer command for this actuator has gone out since.
            if self._token[name] != token:
                return
            st.update(pending=False, ok=bool(ok), error="" if ok else (msg or "command failed"))
            self._changed()

        if a["type"] == "servo":
            angle = a["release"] if released else a["hold"]
            self.send_servo(a["channel"], angle, a["min_pw"], a["max_pw"], done)
        else:
            value = a["release_high"] if released else not a["release_high"]
            self.send_gpio(a["pin"], value, done)
        return True, ("release" if released else "hold") + " sent to " + a["label"]

    def grab_all(self, grab):
        """grab=True closes all four can grippers. grab=False opens all four."""
        for n in CANS:
            self.set(n, not grab)
        return True, ("closing" if grab else "opening") + " all four grippers"

    def startup(self):
        if self.startup_mode == "hold":
            for n in NAMES:
                self.set(n, False)

    # ---- state ----
    def _changed(self):
        self.seq += 1
        self.on_change()

    def snapshot(self):
        return {
            "seq": self.seq,
            "time": round(self.clock(), 3),
            "actuators": {
                n: {
                    "label": self.acts[n]["label"],
                    "released": self.state[n]["released"],
                    "pending": self.state[n]["pending"],
                    "ok": self.state[n]["ok"],
                    "error": self.state[n]["error"],
                }
                for n in NAMES
            },
        }
