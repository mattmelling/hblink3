{
  inputs = {
    dmr-utils3 = {
      url = "github:mattmelling/dmr_utils3";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
  outputs = { self, nixpkgs, ... }@inputs: let
    python-env = pkgs: pkgs.python3.withPackages (pythonPackages: with pythonPackages; [
      twisted
      bitstring
      bitarray
      configparser

      inputs.dmr-utils3.packages.x86_64-linux.dmr-utils3
    ]);
    packages = {
      hblink3 = pkgs: pkgs.stdenv.mkDerivation {
        pname = "hblink3";
        version = "0.1";
        src = ./.;
        # a bit hacky as upstream doesn't expose entry points
        installPhase = let
          pyenv = "${python-env pkgs}/bin/python";
        in ''
          mkdir -p $out/{hblink,bin}
          cp -R ./* $out/hblink/
          makeWrapper ${pyenv} \
              $out/bin/hblink3-bridge \
              --add-flags $out/hblink/bridge.py
          makeWrapper ${pyenv} \
              $out/bin/hblink3-playback \
              --add-flags $out/hblink/playback.py
        '';
        nativeBuildInputs = with pkgs; [
          makeWrapper
        ];
      };
    };
  in {
    devShells.x86_64-linux.default = let
      pkgs = import nixpkgs { system = "x86_64-linux"; };
    in pkgs.mkShell {
      buildInputs = [
        (python-env pkgs)
      ];
    };
    packages.x86_64-linux = let
      pkgs = import nixpkgs { system = "x86_64-linux"; };
    in builtins.mapAttrs (name: pkg: pkg pkgs) packages;
    overlays.default = final: pkgs: builtins.mapAttrs (name: pkg: pkg pkgs) packages;
    nixosModules = rec {
      default = { pkgs, lib, config, ... }: let
        cfg = config.services.hblink3;
      in {
        options = with lib.types; {
          services.hblink3 = {
            bridge = {
              enable = lib.mkEnableOption "HBlink3 bridge server";
              config = lib.mkOption {
                type = str;
                default = "";
              };
              rules = lib.mkOption {
                type = str;
                default = "";
              };
            };
            playback = {
              enable = lib.mkEnableOption "HBlink3 playback server";
              config = lib.mkOption {
                type = str;
                default = "";
              };
            };
          };
        };
        config = let
          enable = cfg.bridge.enable || cfg.playback.enable;
        in {
          environment.etc = {
            "hblink3/bridge/bridge.cfg".text = cfg.bridge.config;
            "hblink3/bridge/rules.py".text = cfg.bridge.rules;
            "hblink3/playback/playback.cfg".text = cfg.playback.config;
          };
          systemd.tmpfiles.rules = lib.mkIf enable (let
            group = config.services.nginx.group;
          in [
            "d /var/lib/hblink3    0750 hblink hblink - -"
          ]);
          users = {
            users.hblink = {
              isSystemUser = true;
              group = "hblink";
            };
            groups.hblink = {};
          };
          systemd.services = {
            hblink3-bridge = lib.mkIf cfg.bridge.enable {
              enable = true;
              wantedBy = [ "network-online.target" ];
              script = ''
                #!${pkgs.stdenv.shell}
                cd /var/lib/hblink3
                ${pkgs.hblink3}/bin/hblink3-bridge \
                    -c /etc/hblink3/bridge/bridge.cfg \
                    -r /etc/hblink3/bridge/rules.py
              '';
              serviceConfig = {
                Restart = "always";
                WorkingDirectory = "/var/lib/hblink3/";
                User = "hblink";
              };
            };
            hblink3-playback = lib.mkIf cfg.playback.enable {
              enable = true;
              wantedBy = [ "network-online.target" ];
              script = ''
                #!${pkgs.stdenv.shell}
                cd /var/lib/hblink3
                ${pkgs.hblink3}/bin/hblink3-playback \
                    -c /etc/hblink3/playback/playback.cfg
              '';
              serviceConfig = {
                Restart = "always";
                WorkingDirectory = "/var/lib/hblink3/";
                User = "hblink";
              };
            };
          };
        };
      };
    };
  };
}
