# host/ — the root-owned pieces the slider needs

The slider writes the kernel's `charge_control_end_threshold`. On a laptop that
already exposes one (ThinkPad, most ASUS, Framework) nothing in here is needed.
These files exist for the two problems gus has: a driver that will not bind to
its firmware, and an EC that forgets the ceiling on a cold boot.

These are copies of what is installed on gus, kept in the repo so a rebuild
does not have to re-derive them. They are **not** installed by deploying the
plugin.

## What each file is for

**`etc-modprobe.d-msi-ec.conf`** → `/etc/modprobe.d/msi-ec.conf`
`msi-ec` refuses EC firmware `2652EMS1.303`. This overrides it to
`182KIMS1.113`, the closest relative, whose `0xd7` charge register was verified
on this board rather than assumed.

**`etc-modules-load.d-msi-ec.conf`** → `/etc/modules-load.d/msi-ec.conf`
The module never autoloads, because its DMI alias only binds when the firmware
whitelist matches. Boot has to be told to load it explicitly.

**`etc-default-power-pulse-charge-limit`** → `/etc/default/power-pulse-charge-limit`
The saved ceiling. The slider rewrites it on every change, so boot restores
whatever was last chosen.

**`power-pulse-charge-limit-apply`** → `/usr/local/bin/`, mode 0755, root-owned
Applies the saved ceiling: waits up to 15 s for the driver's battery hook to
create the attribute, writes, then reads back and complains if the driver
disagrees. Exits 0 on a machine with no threshold, so a missing driver never
blocks a boot.

**`power-pulse-charge-limit.service`** → `/etc/systemd/system/`
A oneshot that runs the script after `systemd-modules-load.service`.

## Installing

```bash
sudo install -m 0644 -o root -g root etc-modprobe.d-msi-ec.conf           /etc/modprobe.d/msi-ec.conf
sudo install -m 0644 -o root -g root etc-modules-load.d-msi-ec.conf       /etc/modules-load.d/msi-ec.conf
sudo install -m 0644 -o root -g root etc-default-power-pulse-charge-limit /etc/default/power-pulse-charge-limit
sudo install -m 0755 -o root -g root power-pulse-charge-limit-apply       /usr/local/bin/
sudo install -m 0644 -o root -g root power-pulse-charge-limit.service     /etc/systemd/system/
sudo systemctl daemon-reload && sudo systemctl enable --now power-pulse-charge-limit.service
```

## Verifying the boot path without rebooting

Tear it down and let systemd rebuild it, in the order boot uses:

```bash
sudo systemctl stop power-pulse-charge-limit.service
sudo modprobe -r msi_ec                                   # threshold file disappears
sudo sed -i 's/^CHARGE_LIMIT=.*/CHARGE_LIMIT=85/' /etc/default/power-pulse-charge-limit
sudo systemctl restart systemd-modules-load.service       # module returns WITH the override
sudo systemctl start power-pulse-charge-limit.service
cat /sys/class/power_supply/BAT1/charge_control_end_threshold   # 85
```

## Two things to keep in mind

The script is deliberately root-owned in `/usr/local/bin` and is **not** run
from the plugin directory, because a root unit must never execute a script out
of a user-writable path.

Only the charge threshold is trusted from the borrowed msi-ec config. That
config's `fan_mode`, `shift_mode` and `cooler_boost` addresses are unverified
on this board, and a wrong EC address can wedge the controller.
