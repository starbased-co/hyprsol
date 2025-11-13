# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

`hyprsol` is a Nix-based systemd service module for controlling monitor hardware brightness via DDC/CI on Hyprland. It complements `hyprsunset` (color temperature) by providing true hardware brightness control without gamma degradation.

**Core Architecture:**

```
flake.nix → module.nix → systemd services + timers
             ↓
          Shell scripts (hyprsolSet, hyprsolSetNow)
             ↓
          ddcutil (DDC/CI hardware control)
```

The module generates:
- **Per-profile systemd services**: Each time-based profile becomes a oneshot service
- **Systemd timers**: OnCalendar triggers for profile activation
- **Startup service**: `hyprsol.service` applies correct profile on boot based on current time
- **CLI wrapper**: `hyprsol-set` script for manual brightness control

## Key Design Patterns

### Time-Based Profile Resolution

`hyprsolSetNow` (module.nix:27-59) implements startup brightness logic:
1. Sorts profiles by time ascending
2. Iterates through profiles, setting brightness to most recent past profile
3. Defaults to 100% if no profiles match

This ensures correct brightness on boot regardless of when system starts.

### Nix String Interpolation for Shell Scripts

Shell scripts are generated via `pkgs.writeShellScript` with Nix variable interpolation:
- `${pkgs.ddcutil}/bin/ddcutil` - Ensures correct package path
- `${toString profile.brightness}` - Type-safe conversion to string
- `${lib.concatMapStringsSep}` - Generate conditional blocks from profile list

### Multi-Monitor Support

Two modes via optional `monitor` parameter:
- `null` → `ddcutil --brief setvcp 10 $BRIGHTNESS` (all monitors)
- `int` → `ddcutil --display $N --brief setvcp 10 $BRIGHTNESS` (specific monitor)

Monitor numbers correspond to `ddcutil detect` output.

## Module Structure

**flake.nix**: Minimal flake exposing `homeManagerModules` and `nixosModules`
**module.nix**: Single-file NixOS/home-manager module containing:
- Helper functions: `mkHyprsolService`, `mkHyprsolTimer`
- Script generators: `hyprsolSet`, `hyprsolSetNow`
- Module options: `services.hyprsol.{enable,profiles}`
- Systemd unit generation via `lib.listToAttrs` + `map`

## Development Commands

### Testing Changes

```bash
# Rebuild home-manager configuration (if using home-manager)
home-manager switch --flake .#youruser

# Check systemd services generated
systemctl --user list-units 'hyprsol*' --all

# Check timers
systemctl --user list-timers 'hyprsol*'

# Manually trigger a profile service
systemctl --user start hyprsol-22-30.service

# Check service logs
journalctl --user -u hyprsol.service -f
```

### Manual Testing

```bash
# Test hyprsol-set directly
hyprsol-set 50        # Set all monitors to 50%
hyprsol-set 75 1      # Set monitor 1 to 75%

# Verify DDC/CI access
ddcutil detect
ddcutil getvcp 10     # Read current brightness

# Check i2c-dev module loaded
lsmod | grep i2c_dev
```

### Nix Evaluation

```bash
# Check flake outputs
nix flake show

# Evaluate module options
nix eval .#homeManagerModules.default

# Build without installing
nix build .#homeManagerModules.default
```

## Configuration Integration Patterns

### Standalone Configuration

```nix
services.hyprsol = {
  enable = true;
  profiles = [
    { time = "06:00"; brightness = 100; monitor = null; }
    { time = "22:00"; brightness = 60; monitor = null; }
  ];
};
```

### Shared with hyprsunset

Define profiles once, filter for each service:

```nix
let
  profiles = [
    { time = "06:00"; temperature = 6500; brightness = 100; }
    { time = "22:00"; temperature = 3000; brightness = 60; }
  ];
in {
  services.hyprsunset.settings.profile = map (p: {
    inherit (p) time temperature;
  }) profiles;

  services.hyprsol.profiles = map (p: {
    inherit (p) time brightness;
    monitor = null;
  }) profiles;
}
```

## DDC/CI Requirements

**Prerequisites checked by module:**
- `i2c-dev` kernel module (loaded via `ExecStartPre` in services)
- User in `i2c` group (not enforced by module, user responsibility)
- DDC/CI compatible monitor

**Troubleshooting commands:**
```bash
# List i2c devices
ls -la /dev/i2c-*

# Check group membership
groups | grep i2c

# Test monitor capabilities
ddcutil capabilities | grep -i brightness
```

## Systemd Service Architecture

Each profile generates two units:

**Service** (`hyprsol-HH-MM.service`):
- `Type=oneshot` - Runs once and exits
- `ExecStartPre` - Ensures i2c-dev loaded
- `ExecStart` - Calls hyprsolSet with brightness + optional monitor

**Timer** (`hyprsol-HH-MM.timer`):
- `OnCalendar=HH:MM` - Triggers at specified time
- `Persistent=true` - Runs missed timers after boot
- `WantedBy=timers.target` - Auto-enabled

**Startup service** (`hyprsol.service`):
- `WantedBy=graphical-session.target` - Runs on login
- Executes `hyprsolSetNow` to apply current profile
- Critical for correct brightness on boot

## Common Development Tasks

### Adding New Profile Options

1. Add option to `lib.types.submodule` in `options.services.hyprsol.profiles` (module.nix:115-139)
2. Update `mkHyprsolService` to consume new option (module.nix:61-74)
3. Modify `hyprsolSet` script if new ddcutil flags needed (module.nix:10-24)

### Modifying Time Resolution Logic

Edit `hyprsolSetNow` function (module.nix:27-59):
- Profile sorting happens at Nix evaluation time: `lib.sort (a: b: a.time < b.time)`
- Profile selection happens at runtime in generated bash script

### Debugging systemd Integration

```bash
# Dry-run systemd unit generation
systemd-analyze verify ~/.config/systemd/user/hyprsol*.service

# Check if timers are active
systemctl --user is-active hyprsol-*.timer

# Force timer execution
systemctl --user start hyprsol-22-30.timer --no-block
```
