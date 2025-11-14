{
  config,
  pkgs,
  lib,
  ...
}:

let
  # Set brightness
  hyprsolSet = pkgs.writeShellScript "hyprsol-set" ''
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

  # Sets profile based on time of day
  hyprsolSetNow =
    cfg:
    pkgs.writeShellScript "hyprsol-set-now" ''
      #!/usr/bin/env bash
      set -euo pipefail

      CURRENT_TIME=$(date +%H%M)

      ${lib.concatMapStringsSep "\n" (
        profile:
        let
          timeNum = builtins.replaceStrings [ ":" ] [ "" ] profile.time;
        in
        "PROFILE_${timeNum}=${toString profile.brightness}"
      ) (lib.sort (a: b: a.time < b.time) cfg.profiles)}

      BRIGHTNESS=100  # Default value for when no hyprsunset profiles are configured

      ${lib.concatMapStringsSep "\n" (
        profile:
        let
          timeNum = builtins.replaceStrings [ ":" ] [ "" ] profile.time;
        in
        ''
          if [[ "$CURRENT_TIME" -ge "${timeNum}" ]]; then
            BRIGHTNESS=$PROFILE_${timeNum}
          fi
        ''
      ) (lib.sort (a: b: a.time < b.time) cfg.profiles)}

      # apply
      ${hyprsolSet} "$BRIGHTNESS"
    '';

  # Monitor wake listener - restores brightness when monitors wake from DPMS
  hyprsolWake =
    cfg:
    pkgs.writeShellScript "hyprsol-wake" ''
      #!/usr/bin/env bash
      set -euo pipefail

      SOCKET="$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock"

      if [[ ! -S "$SOCKET" ]]; then
        echo "Error: Hyprland event socket not found at $SOCKET" >&2
        exit 1
      fi

      echo "hyprsol-wake: Listening for DPMS events..."

      ${pkgs.socat}/bin/socat -U - "UNIX-CONNECT:$SOCKET" | while read -r line; do
        # Parse events: monitoradded>>MONITOR or dpms>>MONITOR,STATE
        if [[ "$line" =~ ^monitoradded ]] || [[ "$line" =~ ^dpms.*,1$ ]]; then
          echo "hyprsol-wake: Monitor wake detected, restoring brightness..."
          ${hyprsolSetNow cfg} || echo "hyprsol-wake: Failed to restore brightness" >&2
        fi
      done
    '';

  mkHyprsolService = profile: {
    Unit = {
      Description = "hyprsol - ${profile.time}";
      After = [ "graphical-session.target" ];
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${hyprsolSet} ${toString profile.brightness} ${
        if profile.monitor != null then toString profile.monitor else ""
      }";
      # Ensure i2c-dev module is loaded
      ExecStartPre = "${pkgs.kmod}/bin/modprobe i2c-dev";
    };
  };

  mkHyprsolTimer = profile: {
    Unit = {
      Description = "hyprsol timer - ${profile.time}";
    };
    Timer = {
      OnCalendar = profile.time;
      Persistent = true;
      Unit = "hyprsol-${builtins.replaceStrings [ ":" ] [ "-" ] profile.time}.service";
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

  cfg = config.services.hyprsol;
in
{
  options.services.hyprsol = {
    enable = lib.mkEnableOption "hyprsol - DDC/CI monitor brightness for Hyprland with hyprsunset support";

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

    restoreOnWake = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Restore brightness when monitors wake from DPMS";
    };
  };

  config = lib.mkIf cfg.enable {
    # Install ddcutil package and helper script
    home.packages = with pkgs; [
      ddcutil
      (pkgs.writeShellScriptBin "hyprsol-set" ''
        ${hyprsolSet} "$@"
      '')
    ];

    # Create systemd services for each profile
    systemd.user.services = lib.mkMerge [
      # Individual timer services
      (lib.listToAttrs (
        map (profile: {
          name = "hyprsol-${builtins.replaceStrings [ ":" ] [ "-" ] profile.time}";
          value = mkHyprsolService profile;
        }) cfg.profiles
      ))

      # Startup service to apply current profile immediately
      {
        hyprsol = {
          Unit = {
            Description = "Startup service for hyprsol";
            After = [ "graphical-session.target" ];
          };
          Service = {
            Type = "oneshot";
            ExecStart = "${hyprsolSetNow cfg}";
            ExecStartPre = "${pkgs.kmod}/bin/modprobe i2c-dev";
          };
          Install = {
            WantedBy = [ "graphical-session.target" ];
          };
        };
      }

      # Monitor wake listener service
      (lib.mkIf cfg.restoreOnWake {
        hyprsol-wake = {
          Unit = {
            Description = "hyprsol monitor wake listener";
            After = [ "graphical-session.target" ];
            PartOf = [ "graphical-session.target" ];
          };
          Service = {
            Type = "simple";
            ExecStart = "${hyprsolWake cfg}";
            Restart = "on-failure";
            RestartSec = 5;
          };
          Install = {
            WantedBy = [ "graphical-session.target" ];
          };
        };
      })
    ];

    # Create systemd timers for each profile
    systemd.user.timers = lib.listToAttrs (
      map (profile: {
        name = "hyprsol-${builtins.replaceStrings [ ":" ] [ "-" ] profile.time}";
        value = mkHyprsolTimer profile;
      }) cfg.profiles
    );
  };
}
