{
  description = "minimalbase + lidarr service";
  inputs = {
    nixpkgs.follows = "minimalbase/nixpkgs";
    minimalbase.url = "github:nonrootdocker/minimalbase";
    lidarr-src = {
      url = "https://lidarr.servarr.com/v1/update/master/updatefile?os=linux&runtime=netcore&arch=x64";
      flake = false;
    };
  };
  outputs = { self, nixpkgs, minimalbase, lidarr-src }:
  let
    system = "x86_64-linux";
    pkgs = import nixpkgs {
      inherit system;
      config = {
        allowUnfree = true;
      };
    };
    opensslLib = pkgs.openssl.out;
    sqliteLib = pkgs.sqlite.out;
    # ----------------------------
    # Lidarr package
    # ----------------------------
    lidarr = pkgs.stdenv.mkDerivation {
      pname = "lidarr";
      version = "latest";
      src = lidarr-src;
      nativeBuildInputs = [
        pkgs.autoPatchelfHook
      ];
      buildInputs = [
        pkgs.icu
        pkgs.curl
        pkgs.sqlite
        opensslLib
        pkgs.zlib
        pkgs.lttng-ust_2_12
        pkgs.stdenv.cc.cc.lib
        pkgs.libmediainfo
      ];
      unpackPhase = ''
        tar -xzf $src
      '';
      installPhase = ''
        mkdir -p $out/app
        cp -r . $out/app/
      '';
    };
    # ----------------------------
    # User database configuration (/etc/passwd)
    # ----------------------------
    passwdFile = pkgs.writeTextDir "etc/passwd" ''
      root:x:0:0:root:/root:/bin/sh
      lidarr:x:1000:1000:lidarr:/data:/bin/sh
    '';
    # ----------------------------
    # ABI generator (Points directly to Nix Store)
    # ----------------------------
    lidarrAbi = pkgs.writeTextFile {
      name = "lidarr-abi.json";
      text = builtins.toJSON {
        version = 2;
        process = {
          exec = "${lidarr}/app/Lidarr/Lidarr";
          args = [
            "-nobrowser"
            "-data=/data"
          ];
        };
      };
      destination = "/app/main";
    };
  in {
    packages.${system} = {
      default = self.packages.${system}.lidarr-image;
      lidarr-image = pkgs.dockerTools.buildImage {
        name = "minimalbase";
        tag = "latest";
        fromImage = minimalbase.packages.${system}.base-image;
        copyToRoot = pkgs.buildEnv {
          name = "root";
          paths = [
            pkgs.coreutils
            pkgs.tzdata
            pkgs.cacert
            pkgs.chromaprint
            pkgs.mediainfo
            lidarr
            lidarrAbi
            passwdFile
          ];
        };
        config = {
          Entrypoint = [ "${minimalbase.packages.${system}.container-init}/bin/container-init" ];
          User = "1000:1000";
          Env = [
            "PATH=/bin"
            "TZ=UTC"
            "LANG=en_US.UTF-8"
            "LD_LIBRARY_PATH=${pkgs.icu}/lib:${opensslLib}/lib:${pkgs.zlib}/lib:${pkgs.lttng-ust_2_12}/lib:${sqliteLib}/lib:${pkgs.libmediainfo}/lib"
          ];
        };
      };
    };
  };
}
