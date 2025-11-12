{
  config,
  pkgs,
  lib,
  ...
}:

let
  # DDC brightness control script
  ddcBrightnessScript = pkgs.writeShellScript "ddc-brightness" ''
    #!/usr/bin/env bash
    set -euo pipefail

    BRIGHTNESS="''${1:-100}"
    MONITOR="''${2:-}"  # Optional: specify monitor by number or empty for all

    if [[ -z "$MONITOR" ]]; then
      # Set brightness on all detected monitors
      ${pkgs.ddcutil}/bin/ddcutil --brief setvcp 10 "$BRIGHTNESS"
    else
      # Set brightness on specific monitor
      ${pkgs.ddcutil}/bin/ddcutil --display "$MONITOR" --brief setvcp 10 "$BRIGHTNESS"
    fi
  '';

  # Script to apply current brightness profile based on time of day
  applyCurrentProfileScript = cfg: pkgs.writeShellScript "ddc-apply-current" ''
    #!/usr/bin/env bash
    set -euo pipefail

    # Get current time in HHMM format
    CURRENT_TIME=$(date +%H%M)

    # Profile times and brightness values (sorted by time)
    ${lib.concatMapStringsSep "\n" (profile:
      let
        timeNum = builtins.replaceStrings [":"] [""] profile.time;
      in
      "PROFILE_${timeNum}=${toString profile.brightness}"
    ) (lib.sort (a: b: a.time < b.time) cfg.profiles)}

    # Find the most recent profile that should be active
    BRIGHTNESS=100  # Default

    ${lib.concatMapStringsSep "\n" (profile:
      let
        timeNum = builtins.replaceStrings [":"] [""] profile.time;
      in
      ''
      if [[ "$CURRENT_TIME" -ge "${timeNum}" ]]; then
        BRIGHTNESS=$PROFILE_${timeNum}
      fi
      ''
    ) (lib.sort (a: b: a.time < b.time) cfg.profiles)}

    # Apply the brightness
    ${ddcBrightnessScript} "$BRIGHTNESS"
  '';

  # Time-based brightness profile service generator
  makeBrightnessService = profile: {
    Unit = {
      Description = "DDC Brightness Profile - ${profile.time}";
      After = [ "graphical-session.target" ];
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${ddcBrightnessScript} ${toString profile.brightness} ${
        if profile.monitor != null then toString profile.monitor else ""
      }";
      # Ensure i2c-dev module is loaded
      ExecStartPre = "${pkgs.kmod}/bin/modprobe i2c-dev";
    };
  };

  # Timer for each brightness profile
  makeBrightnessTimer = profile: {
    Unit = {
      Description = "DDC Brightness Timer - ${profile.time}";
    };
    Timer = {
      OnCalendar = profile.time;
      Persistent = true;
      Unit = "ddc-brightness-${builtins.replaceStrings [ ":" ] [ "-" ] profile.time}.service";
    };
    Install = {
      WantedBy = [ "timers.target" ];
    };
  };

  # Default profiles matching hyprsunset configuration
  defaultProfiles = [
    {
      time = "06:00";
      brightness = 100; # Full brightness during day
      monitor = null; # All monitors
    }
    {
      time = "20:00";
      brightness = 80; # Slightly dimmer evening
      monitor = null;
    }
    {
      time = "22:30";
      brightness = 60; # Night mode brightness
      monitor = null;
    }
  ];

  cfg = config.services.ddcBrightness;
in
{
  options.services.ddcBrightness = {
    enable = lib.mkEnableOption "DDC/CI monitor brightness control";

    profiles = lib.mkOption {
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            time = lib.mkOption {
              type = lib.types.str;
              description = "Time in HH:MM format (24-hour)";
              example = "22:30";
            };
            brightness = lib.mkOption {
              type = lib.types.ints.between 0 100;
              description = "Monitor brightness percentage (0-100)";
              default = 100;
            };
            monitor = lib.mkOption {
              type = lib.types.nullOr lib.types.int;
              description = "Monitor number (null for all monitors)";
              default = null;
            };
          };
        }
      );
      default = defaultProfiles;
      description = "Time-based brightness profiles";
    };
  };

  config = lib.mkIf cfg.enable {
    # Install ddcutil package and helper script
    home.packages =
      with pkgs;
      [
        ddcutil
        (pkgs.writeShellScriptBin "ddc-set-brightness" ''
          ${ddcBrightnessScript} "$@"
        '')
      ];

    # Create systemd services for each profile
    systemd.user.services = lib.mkMerge [
      # Individual timer services
      (lib.listToAttrs (
        map (profile: {
          name = "ddc-brightness-${builtins.replaceStrings [ ":" ] [ "-" ] profile.time}";
          value = makeBrightnessService profile;
        }) cfg.profiles
      ))

      # Startup service to apply current profile immediately
      {
        ddc-brightness-startup = {
          Unit = {
            Description = "Apply current DDC brightness profile on startup";
            After = [ "graphical-session.target" ];
          };
          Service = {
            Type = "oneshot";
            ExecStart = "${applyCurrentProfileScript cfg}";
            ExecStartPre = "${pkgs.kmod}/bin/modprobe i2c-dev";
          };
          Install = {
            WantedBy = [ "graphical-session.target" ];
          };
        };
      }
    ];

    # Create systemd timers for each profile
    systemd.user.timers = lib.listToAttrs (
      map (profile: {
        name = "ddc-brightness-${builtins.replaceStrings [ ":" ] [ "-" ] profile.time}";
        value = makeBrightnessTimer profile;
      }) cfg.profiles
    );

    # Hyprland keybindings for manual brightness control
    wayland.windowManager.hyprland.settings = {
      # Use XF86MonBrightness keys if available, or custom bindings
      bindel = [
        # Decrease brightness by 5%
        ",XF86MonBrightnessDown,exec,${ddcBrightnessScript} $(( $(${pkgs.ddcutil}/bin/ddcutil getvcp 10 --brief | ${pkgs.gawk}/bin/awk '{print $4}') - 5 ))"
        # Increase brightness by 5%
        ",XF86MonBrightnessUp,exec,${ddcBrightnessScript} $(( $(${pkgs.ddcutil}/bin/ddcutil getvcp 10 --brief | ${pkgs.gawk}/bin/awk '{print $4}') + 5 ))"
      ];
    };
  };
}
