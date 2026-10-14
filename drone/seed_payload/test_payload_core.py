"""Run with:  python3 -m pytest drone/seed_payload  (or plain python3 this_file.py)"""
import os
import sys

import yaml

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from payload_core import CANS, NAMES, ConfigError, PayloadCore, parse_config  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))


def load():
    with open(os.path.join(HERE, "payload.yaml")) as f:
        return yaml.safe_load(f)


class Fake:
    def __init__(self, auto=True):
        self.calls, self.pending, self.auto = [], [], auto

    def servo(self, ch, angle, lo, hi, done):
        self.calls.append(("servo", ch, angle))
        (done(True, "ok") if self.auto else self.pending.append(done))

    def gpio(self, pin, value, done):
        self.calls.append(("gpio", pin, value))
        (done(True, "ok") if self.auto else self.pending.append(done))


def test_shipped_config_is_valid():
    acts, startup = parse_config(load())
    assert set(acts) == set(NAMES) and startup == "hold"


def test_startup_holds_everything():
    f = Fake()
    core = PayloadCore(load(), f.servo, f.gpio)
    core.startup()
    acts = core.acts
    assert sorted(f.calls) == sorted(("servo", acts[n]["channel"], acts[n]["hold"]) for n in NAMES)
    snap = core.snapshot()["actuators"]
    assert all(s["released"] is False and s["ok"] and not s["pending"] for s in snap.values())


def test_drop_row_and_can():
    f = Fake()
    core = PayloadCore(load(), f.servo, f.gpio)
    core.set("row_2", True)
    core.set("can_3", True)
    assert f.calls == [("servo", 1, 0), ("servo", 6, 120)]
    snap = core.snapshot()["actuators"]
    assert snap["row_2"]["released"] is True and snap["can_3"]["released"] is True
    assert snap["row_1"]["released"] is None


def test_grab_all_and_open_all():
    f = Fake()
    core = PayloadCore(load(), f.servo, f.gpio)
    core.grab_all(True)
    assert [c[2] for c in f.calls] == [30, 30, 30, 30]
    assert all(core.state[n]["released"] is False for n in CANS)
    core.grab_all(False)
    assert all(core.state[n]["released"] is True for n in CANS)
    assert all(core.state[n]["released"] is None for n in NAMES if n not in CANS)


def test_failure_is_reported_and_stale_reply_ignored():
    f = Fake(auto=False)
    core = PayloadCore(load(), f.servo, f.gpio)
    core.set("rack", True)
    core.set("rack", False)          # newer command before the first reply
    first, second = f.pending
    first(False, "late failure")     # reply for the superseded command: ignored
    assert core.state["rack"]["ok"] and core.state["rack"]["pending"]
    second(False, "PCA9685 PWM set failed")
    st = core.state["rack"]
    assert st["released"] is False and not st["pending"] and not st["ok"] and "PCA9685" in st["error"]


def test_gpio_actuator():
    cfg = load()
    cfg["actuators"]["rack"] = {"type": "gpio", "pin": 1, "release_high": True}
    f = Fake()
    core = PayloadCore(cfg, f.servo, f.gpio)
    core.set("rack", True)
    core.set("rack", False)
    assert f.calls == [("gpio", 1, True), ("gpio", 1, False)]


def test_config_errors():
    cfg = load()
    cfg["actuators"]["can_2"]["channel"] = 4   # same as can_1
    for bad, msg in [
        (cfg, "already used"),
        ({"actuators": {}}, "missing"),
        ({**load(), "startup": "open"}, "startup"),
    ]:
        try:
            parse_config(bad)
        except ConfigError as e:
            assert msg in str(e), e
        else:
            raise AssertionError("expected ConfigError for " + msg)


if __name__ == "__main__":
    for name, fn in list(globals().items()):
        if name.startswith("test_"):
            fn()
            print("ok", name)
