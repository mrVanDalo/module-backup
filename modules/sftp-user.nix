{ config, lib, pkgs, ... }:

with lib;

let

  cfg = config.module.backup.sftpUser;

  allEnabled = flip filterAttrs cfg (_: value: value.enable == true);

in {

  options.module.backup.sftpUser = mkOption {
      type    = with types; attrsOf ( submodule ( { name, ... }: {
        options = {
          enable = mkEnableOption "enable this user";
          home = mkOption {
            type    = with types; path;
            default = "/srv/sftp/${name}";
            description = ''
              path of the home folder (which is the only folder visible to the this user)
            '';
          };
          authorizedKeys.keyFiles = mkOption {
            type    = with types; listOf path;
            default = [];
            description = ''
              authorized keys like openssh.authorizedKeys.keyFiles
            '';
          };
          initialize = mkOption {
            type    = with types; bool;
            default = false;
            description = ''
              make sure the home folder is setup properly so sfp will work
            '';
          };
        };
      }));
      description = ''
        sftp-users are users that can only be accessed by via ssh.
        They are forbidden to have a terminal, so they are only good
        for backups with tools like restic or borg-backup.
      '';
      default = {};
  };

  config = {

    users.users = flip mapAttrs' allEnabled (name: value:

      nameValuePair name {
        createHome = value.initialize;
        description = "User that is only allowed to receive sftp to its home folder";
        home = value.home;
        openssh.authorizedKeys.keyFiles = value.authorizedKeys.keyFiles;
      }
    );

    services.openssh = {
      enable = true;
      allowSFTP = true;
      extraConfig = let allUserConfigs = flip mapAttrsToList allEnabled (user: value:
        ''
          # following rules should match alle users again
          Match User ${user}

          # forces the SSH server to run the SFTP server upon login,
          # disallowing shell access.
          ForceCommand internal-sftp

          # ensures that the user will not be allowed access to
          # anything beyond the ${value.home} directory.
          ChrootDirectory ${dirOf value.home}

          # disables port forwarding, tunneling and X11 forwarding for
          # this user
          AllowAgentForwarding no
          AllowTcpForwarding no
          X11Forwarding no
        ''
      );
      in ''
        ############################################################
        #                    sftp only user                        #
        ############################################################
        ${concatStringsSep "\n" allUserConfigs}
        Match all
      '';
    };

    systemd.services."sftp-user.setup" = {
      wantedBy = [ "sshd.service" ];
      description = ''
        setup rights for home folder for sftp-users to make the chroot work
      '';
      restartIfChanged = true;
      serviceConfig = {
        Type = "oneshot";
      };
      script = let
        allToInitalize = flip filterAttrs allEnabled (_: value: value.initialize );
        toInitalize = flip mapAttrsToList allToInitalize (user: value: let
          parentFolder = dirOf value.home;
        in ''
          echo 'fixing ${user}'
          [ -d ${parentFolder} ] || mkdir -p ${parentFolder}
          chmod a+rx ${parentFolder}
          if [ ! -d ${value.home} ]
          then
            mkdir -p ${value.home}
            chown -R ${user} ${value.home}
            chmod -R 700 ${value.home}
          fi
        ''
      );
      in ''
        ${concatStringsSep "\n" toInitalize}
      '';
    };

  };
}
