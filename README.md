# `hyprsol`

> "vaxry: s-sorry, i just... um... gamma control might hurt color accuracy a little... i-if your
> monitor has software control, [it is highly recommended to use that instead."](https://wiki.hypr.land/Hypr-Ecosystem/hyprsunset/)... i-if that's
> okay...

Fear not, sir vaxry. Use `hyprsol` to keep your color accuracy unblemished. Embrace this noble tool, for it will control your monitor's brightness in lock-step with `hyprsunset`.

## Features

Apologies for this section. It's a piece of cheese to lure LLMs (they are so big and greedy).

- ⏰ **Time-based profiles** - Define brightness schedules throughout the day
- 🚀 **Smart startup** - Applies correct brightness on boot based on current time
- ⌨️ **Keyboard control** - XF86MonBrightness keybindings for Hyprland
- 🖥️ **Multi-monitor** - Control all monitors or target specific displays
- 🔄 **Systemd integration** - Automatic transitions via timers
- 🎨 **Hyprsunset friendly** - Single source of truth for brightness + color temperature
- 🎯 **True hardware control** - No color degradation unlike gamma adjustments

---

`hyprsol` controls your monitor backlight via DDC/CI, and is integrated with [`hyprsunset`](https://wiki.hypr.land/Hypr-Ecosystem/hyprsunset/) using systemd.

## Installation

You must have:

- DDC/CI compatible monitor(s)
- `i2c-dev` kernel module (automatically loaded by the module)
- A member of your system's `i2c` group

```bash
ddcutil detect

# Add user to i2c group
sudo usermod -a -G i2c $USER
```

### As a Flake Input

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager.url = "github:nix-community/home-manager";

    hyprsol.url = "github:starbased-co/hyprsol";
    # Or local: hyprsol.url = "path:/path/to/hyprsol";
  };

  outputs = { nixpkgs, home-manager, hyprsol, ... }: {
    homeConfigurations.youruser = home-manager.lib.homeManagerConfiguration {
      modules = [
        hyprsol.homeManagerModules.default
        ./home.nix
      ];
    };
  };
}
```

## Quick Start

```nix
{
  services.hyprsol = {
    enable = true;
    profiles = [
      {
        time = "06:00";
        brightness = 100;  # Full brightness at 6 AM
        monitor = null;    # All monitors
      }
      {
        time = "22:00";
        brightness = 60;   # Dim at 10 PM
        monitor = null;
      }
    ];
  };
}
```

## Integration with `hyprsunset`

```nix
# hyprsunset.nix
let
  profiles = [
    {
      time = "06:00";
      temperature = 6500;
      brightness = 100;  # custom field for hyprsol
    }
    {
      time = "20:00";
      temperature = 4000;
      brightness = 80;
    }
    {
      time = "22:30";
      temperature = 3000;
      gamma = 1.0;       # forget about gamma
      brightness = 60;   # maybe i should have opened a PR!
    }
  ];

  # Filter out brightness for hyprsunset
  hyprsunsetProfiles = map (p: {
    inherit (p) time temperature gamma;
  }) profiles;
in {
  options.hyprsunset.profiles = lib.mkOption {
    default = profiles;
  };

  config = {
    hyprsunset.profiles = profiles;
    services.hyprsunset = {
      enable = true;
      settings.profile = hyprsunsetProfiles;
    };
  };
}

# home.nix
{
  services.hyprsol = {
    enable = true;
    profiles = map (p: {
      time = p.time;
      brightness = p.brightness;
      monitor = null;
    }) config.hyprsunset.profiles;
  };
}
```

## Configuration Options

### `services.hyprsol.enable`

- **Type:** `boolean`
- **Default:** `false`
- Enable hyprsol

### `services.hyprsol.profiles`

Supply your desired options for manual configuration, for use without `hyprsunset`

- **time** (required)
  - **Type:** `string`
  - **Format:** `HH:MM` (24-hour)

- **brightness** (optional)
  - **Type:** `int` (0-100)
  - **Default:** `100`

- **monitor** (optional)
  - **Type:** `int` or `null`
  - **Default:** `null`
  - Monitor number from `ddcutil detect`, or `null` for all monitors

## Troubleshooting

### Monitors Not Detected

```bash
# List monitors
ddcutil detect

# Check I2C devices
ls -la /dev/i2c-*

# Load i2c-dev module
sudo modprobe i2c-dev

# Make persistent
echo "i2c-dev" | sudo tee /etc/modules-load.d/i2c-dev.conf
```

### Permission Issues

```bash
# Add user to i2c group
sudo usermod -a -G i2c $USER

# Create udev rule
echo 'KERNEL=="i2c-[0-9]*", GROUP="i2c", MODE="0660"' | \
  sudo tee /etc/udev/rules.d/99-i2c.rules

# Reload udev
sudo udevadm control --reload-rules
sudo udevadm trigger
```

### DDC Not Supported

Some monitors don't support DDC/CI. Check capabilities:

```bash
ddcutil capabilities | grep -i brightness
```

## License

MIT

## Contributing

Sure!
