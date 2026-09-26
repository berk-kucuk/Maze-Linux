# Hardware Kill Switches

The **Maze Hardware** application can disable the camera, microphone,
Bluetooth, Wi-Fi and USB at the driver level.

These are not application permissions that a program can talk its way around —
the driver is blacklisted, so software cannot see the device at all.

## The camera switch is persistent

Turning the camera off **stays off across reboots**. The driver is blacklisted,
which means no application can see the camera until you turn it back on in
Maze Hardware.

This is the intended behaviour, and it is also the single most common source of
"my camera stopped working" reports.

## "My camera / microphone isn't working — what did I do?"

Run this first:

```bash
sudo maze-doctor
```

If a kill switch is enabled, Maze says so explicitly.

If it does **not** say so, the cause is not Maze. Check, in order:

1. A physical camera shutter — many ThinkPads and some other laptops have one
2. A BIOS/firmware setting disabling the device
3. A hardware fault

`maze-doctor` reports on these too, so its output is the right place to start
either way.

## USB protection

USB device blocking (USBGuard) is **off by default**, and switching it on is a
deliberate choice you make in Maze Hardware.

It is off by default on purpose: blocking new USB devices by default means a
newly plugged-in keyboard or mouse does not work, which for most people reads
as a broken computer rather than a security feature. Turn it on when you want
that protection and understand the trade-off.

See also: [Diagnostics](Diagnostics) · [Privacy Reference](Privacy)
