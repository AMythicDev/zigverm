{
  description = "Version Manager for the Zig Programming Language";

  inputs.flake-utils.url = "github:numtide/flake-utils";

  outputs = { self, nixpkgs, flake-utils }:
      flake-utils.lib.eachDefaultSystem (system: {
      packages.zigverm = 
        with import nixpkgs { inherit system; };
        stdenv.mkDerivation(finalAttrs: {
          name = "zigverm";
          version = "0.7.1";

          src = fetchFromGitHub {
            owner = "AMythicDev";
            repo = "zigverm";
            rev = "v${finalAttrs.version}";
            hash =  "sha256-RcvDzA4gpyzRxsJQgxOpZT9MAkD9kndov0r6QQyr/DY=";
          };

          nativeBuildInputs = [
            zig_0_13.hook
          ];
        });
        defaultPackage = self.packages.${system}.zigverm;
      }
  );
}
