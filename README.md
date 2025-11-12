# hyprsol

> ☀️ *sol* - sun (Latin) - the source of all natural light changes

Hardware brightness control via DDC/CI following the sun's natural cycle.

Part of the Hypr ecosystem - pairs perfectly with [hyprsunset](https://github.com/hyprwm/hyprsunset) for complete monitor control throughout the day.

## Features

- ⏰ **Time-based profiles** - Define brightness schedules throughout the day
- 🚀 **Smart startup** - Applies correct brightness on boot based on current time
- ⌨️ **Keyboard control** - XF86MonBrightness keybindings for Hyprland
- 🖥️ **Multi-monitor** - Control all monitors or target specific displays
- 🔄 **Systemd integration** - Automatic transitions via timers
- 🎨 **Hyprsunset friendly** - Single source of truth for brightness + color temperature
- 🎯 **True hardware control** - No color degradation unlike gamma adjustments

## Why hyprsol?

Unlike gamma-based dimming (hyprsunset's `gamma` field), hyprsol controls **actual monitor backlight** via DDC/CI:

- ✅ Preserves color accuracy
- ✅ Reduces power consumption
- ✅ Not captured in screenshots/recordings
- ✅ Works with any monitor that supports DDC/CI

Perfect companion to hyprsunset: hyprsunset handles color temperature, hyprsol handles brightness.

## Installation

### As a Flake Input

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager.url = "github:nix-community/home-manager";

    hyprsol.url = "github:yourusername/hyprsol";
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

### Direct Import

```nix
{
  imports = [ /path/to/hyprsol/module.nix ];
}
```

## Quick Start

```nix
{
  services.ddcBrightness = {
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

## Integration with Hyprsunset

Use a single source of truth for both color temperature and brightness:

```nix
# hyprsunset.nix
let
  profiles = [
    {
      time = "06:00";
      temperature = 6500;
      gamma = 1.0;
      brightness = 100;  # Custom field for hyprsol
    }
    {
      time = "20:00";
      temperature = 4000;
      gamma = 1.0;
      brightness = 80;
    }
    {
      time = "22:30";
      temperature = 3000;
      gamma = 1.0;       # No color degradation!
      brightness = 60;   # Real brightness via hyprsol
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
  services.ddcBrightness = {
    enable = true;
    profiles = map (p: {
      time = p.time;
      brightness = p.brightness;
      monitor = null;
    }) config.hyprsunset.profiles;
  };
}
```

## Manual Control

```bash
# Set brightness to 75%
ddc-set-brightness 75

# Set brightness on monitor 1
ddc-set-brightness 50 1

# Get current brightness
ddcutil getvcp 10

# Manually trigger a profile
systemctl --user start ddc-brightness-22-00.service
```

## Requirements

- DDC/CI compatible monitor(s)
- `i2c-dev` kernel module (automatically loaded by the module)
- User access to I2C devices (add user to `i2c` group)

```bash
# Check DDC support
ddcutil detect

# Add user to i2c group
sudo usermod -a -G i2c $USER
```

## Configuration Options

### `services.ddcBrightness.enable`
- **Type:** `boolean`
- **Default:** `false`
- Enable DDC brightness control

### `services.ddcBrightness.profiles`
- **Type:** `list of submodules`
- **Default:** `[]`
- Define brightness profiles

#### Profile Submodule

- **time** (required)
  - **Type:** `string`
  - **Format:** `HH:MM` (24-hour)
  - Time to activate this profile

- **brightness** (optional)
  - **Type:** `int` (0-100)
  - **Default:** `100`
  - Brightness percentage

- **monitor** (optional)
  - **Type:** `int` or `null`
  - **Default:** `null`
  - Monitor number from `ddcutil detect`, or `null` for all monitors

## How It Works

1. **Startup Service** - Runs on boot, applies correct profile for current time
2. **Systemd Timers** - Trigger profile changes throughout the day
3. **DDC Protocol** - Uses `ddcutil` to send VCP commands to monitor hardware
4. **I2C Communication** - `i2c-dev` kernel module provides bus access

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

## Hypr Ecosystem

hyprsol is designed to complement the Hypr ecosystem:

- **[Hyprland](https://github.com/hyprwm/Hyprland)** - Dynamic tiling Wayland compositor
- **[hyprsunset](https://github.com/hyprwm/hyprsunset)** - Blue light filter (color temperature)
- **hyprsol** (this project) - Hardware brightness control

Together they provide complete monitor control without compromising color accuracy.

## License

MIT

## Contributing

Issues and PRs welcome! Built with ❤️ for the Hypr ecosystem.
