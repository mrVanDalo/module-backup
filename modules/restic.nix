{ config, lib, pkgs, ... }:

with lib;

let

  cfg = config.backup.services.restic;

  activeConfigs = filterAttrs (_: value: value.enable == true ) cfg;

in {

  options.backup.services.restic = mkOption {
    type = with types; attrsOf (submodule ({ name, ... }: {
      options = {
        enable = mkEnableOption "enable";
        passwordFile = mkOption {
          type = str;
          example = "/etc/nixos/restic-password";
          description = ''
            read the repository password from a file.
          '';
        };
        # todo distingish between folder and sftp here
        repo = mkOption {
          type = str;
          example = "sftp:backup@192.168.1.100:/backups/${name}";
          description = ''
            repository to backup to. (--repo argument)
          '';
        };
        dirs = mkOption {
          type = listOf str;
          default = [];
          example = [
            "/var/lib/postgresql"
            "/home/user/backup"
          ];
          description = ''
            which directories to backup.
          '';
        };
        timerConfig = mkOption {
          type = attrsOf str;
          default = {
            OnCalendar = "daily";
          };
          example = {
            OnCalendar = "00:05";
            RandomizedDelaySec = "5h";
          };
          description = ''
            When to run the backup. See man systemd.timer for details.
          '';
        };
        user = mkOption {
          type = str;
          default = "root";
          example = "postgresql";
          description = ''
            As which user the backup should run.
          '';
        };
        extraArguments = mkOption {
          type = listOf str;
          default = [];
          example = [
            "sftp.command='ssh backup@192.168.1.100 -i /home/user/.ssh/id_rsa -s sftp'"
          ];
          description = ''
            Extra arguments to append to the restic command.
            Will be prefixed with the --option argument
          '';
        };
        initialize = mkOption {
          type = bool;
          default = false;
          description = ''
            Create the repository if it doesn't exist.
          '';
        };
      };
    }));
    default = {};
  };

  config = {
    systemd.services =
      flip mapAttrs' activeConfigs (name: plan:
        let
          extraArguments = concatMapStringsSep " " (arg: "--option ${arg}") plan.extraArguments;
          resticCmd = "${pkgs.restic}/bin/restic ${extraArguments}";
        in nameValuePair "backup.${name}" {
          environment = {
            RESTIC_PASSWORD_FILE = plan.passwordFile;
            RESTIC_REPOSITORY = plan.repo;
          };
          path = with pkgs; [
            openssh
          ];
          restartIfChanged = false;
          script = /* sh */ ''
            ${resticCmd} backup ${concatStringsSep " " plan.dirs}
          '';
          preStart = /* sh */ mkIf plan.initialize ''
            # ${resticCmd} snapshots || ( mkdir -p "$(dirname '${toString plan.repo}')" && ${resticCmd} init )
            ${resticCmd} snapshots || ${resticCmd} init
          '';
          serviceConfig = {
            User = plan.user;
          };
        }
      );

    systemd.timers =
      flip mapAttrs' activeConfigs (name: plan: nameValuePair "backup.${name}" {
        wantedBy = [ "timers.target" ];
        timerConfig = plan.timerConfig;
      });

  };
}
