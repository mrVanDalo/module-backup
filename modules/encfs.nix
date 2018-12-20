{ config, lib, pkgs, ... }:

with lib;

let

  cfg  = config.module.backup.services.encfs ;

  encfs      = "${pkgs.encfs}/bin/encfs";
  fusermount = "${pkgs.fuse}/bin/fusermount";

  active = filterAttrs (_: conf: conf.enable) cfg;

in {

  options.module.backup.services.encfs = mkOption {
    type    = with types; attrsOf (submodule ({ name, ... }: { options = {
      enable  = mkEnableOption "enable";

      decryptedFolder = mkOption {
        type = types.path;
        description = ''
          folder to encrypt on the machine
        '';
      };

      encryptedFolder = mkOption {
        type = types.path;
        description = ''
          folder to encrypt on the machine
        '';
      };

      keyFile = mkOption {
        type = types.path;
        description = ''
          path to the key (on the system);
        '';
      };

      requires = mkOption {
        type = with types; listOf str;
        default = [];
        description = ''
          services that need to run for store service to run.
        '';
      };

      requiredBy = mkOption {
        type = with types; listOf str;
        default = [];
        description = ''
          list of services which need this service to run
        '';
      };

      bootDelay = mkOption {
        type    = types.int;
        default = 4;
        description = ''
          delay of boot in seconds is the time the services wait to be started.
          It makes dependency management possible, otherwise the dependend service
          would start before the decrypted folder is mounted.
        '';
      };

      user = mkOption {
        type    = types.str;
        default = "root";
        description = ''
          User to mount the encfs folder with.
        '';
      };

      allowOthers = mkOption {
        type    = with types; bool;
        default = true;
        description = ''
          make folder visibile to other users
        '';
      };

      serviceName = mkOption {
        type    = with types; str;
        default = "encfs.${name}";
        description = ''
          name of the service providing the decrypted filesystem.
          if not set it will be <name>-storage
        '';
      };

    };}));
    default = {};
    description = ''
      Encrypted folder using encfs which can depend on another
      systemd service.
    '';
  };


  config = mkMerge [
    {
      systemd.services = flip mapAttrs' active (name: subConfig:

        nameValuePair
          subConfig.serviceName (
          let
            keyFolder = toString /run/keys.encfs;
            keyFile = "${keyFolder}/${subConfig.serviceName}.key";
          in {

            after = subConfig.requires;
            requires = subConfig.requires;
            before = subConfig.requiredBy;
            requiredBy = subConfig.requiredBy;

            wantedBy = [ "multi-user.target" ];

            unitConfig = {
              ConditionDirectoryNotEmpty = "!${subConfig.decryptedFolder}";
            };

            serviceConfig = {
              User = subConfig.user;

              # read file key file and put it somewhere
              # the user can see it (the + runs this command as root)
              ExecStartPre = let script = pkgs.writeDash "${subConfig.serviceName}-keyfile-gen" /* sh */ ''
                mkdir -p ${keyFolder}
                chmod 755 ${keyFolder}
                cat ${subConfig.keyFile} > ${keyFile}
                chown ${subConfig.user} ${keyFile}
                chmod 500 ${keyFile}
              '';
              in "+${script}";

              # this does not work for some reason, when we change the decryptedFolder
              ExecStop = let script = pkgs.writeDash "${subConfig.serviceName}-stop" /* sh */ ''
                set -x
                ${fusermount} -u ${subConfig.decryptedFolder}
              '';
              in "+${script}";

            };

            script = /* sh */ ''
              set -x
              mkdir -p ${subConfig.decryptedFolder}
              mkdir -p ${subConfig.encryptedFolder}
              ${encfs} -f \
                --standard \
                ${optionalString subConfig.allowOthers "-o allow_other"} \
                --extpass="cat ${keyFile}" ${subConfig.encryptedFolder} ${subConfig.decryptedFolder}
            '';

            # without this it is hard to depend on this task
            postStart = ''
              set -x
              sleep ${toString subConfig.bootDelay}
            '';

          })
      );
    }
    # enable fuse option allow_others
    ( let
        activeAndAllowdOthers = filterAttrs ( _: conf: conf.allowOthers ) active;
        enableFuseOptionAllowOthers = 0 < length ( attrNames  activeAndAllowdOthers );
      in
        mkIf enableFuseOptionAllowOthers {
          environment.etc."fuse.conf".text = ''
            user_allow_other
          '';
        }
    )
  ];

}
