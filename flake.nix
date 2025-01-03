{
  description = "yukkop's nix utilities";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs";
  };

  outputs = { self, nixpkgs }:
  let
    lib = nixpkgs.lib;
    recursiveUpdate = lib.recursiveUpdate;

    supportedSystems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" ];

    forSpecSystemsWithPkgs = supportedSystems: pkgOverlays: f:
      builtins.foldl' (acc: system:
        let
          pkgs = import nixpkgs { 
            inherit system;
            overlays = pkgOverlays;
          };
          systemOutputs = f { system = system; pkgs = pkgs; };
        in
          recursiveUpdate acc systemOutputs
      ) {} supportedSystems;

    forAllSystemsWithPkgs = pkgOverlays: f: forSpecSystemsWithPkgs supportedSystems pkgOverlays f;

    envErrorMessage = varName: "Error: The ${varName} environment variable is not set.";

    parseEnv = file: let
      lines = builtins.filter (line: builtins.match "^var=.*" line != null) (builtins.readFile file);
      attributes = builtins.listToAttrs (builtins.map (line: let
        parts = builtins.split "=" line;
        key = builtins.substring 0 (builtins.stringLength parts[0] - 3) parts[0]; # Remove "var" prefix
        value = parts[1];
      in {
        name = key;
        value = value;
      }) lines);
    in attributes;

    dotEnv = builtins.getEnv "DOTENV";
    minorEnvironment = 
    if dotEnv != "" then 
      if builtins.pathExists dotEnv then
        parseEnv dotEnv
      else
        throw "${dotEnv} file not exist"
    else 
      if builtins.pathExists ./.env then
        parseEnv ./.env
      else
        {};
  in
  forAllSystemsWithPkgs [] ({ system, pkgs }:
  {
    packages.${system} = {
      # necessary to load every time .nvimrc
      # makes some magic to shading nvim but still uses nvim that shaded 
      nvim-alias = pkgs.writeShellScriptBin "nvim" ''
        # Source .env file
        if [ -f .env ]; then
            set -a
            . .env
            set +a
        fi

        # Get the directory of this script
        SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
        
        # Remove the script's directory from PATH to avoid recursion
        PATH=$(echo "$PATH" | tr ':' '\n' | grep -v "$SCRIPT_DIR" | paste -sd ':' -)
        
        # Find the system's nvim
        SYSTEM_NVIM=$(command -v nvim)
        
        if [ -z "$SYSTEM_NVIM" ]; then
          echo "Error: nvim not found in PATH" >&2
          exit 1
        fi

        # Execute the system's nvim with your custom arguments
        exec "$SYSTEM_NVIM" --cmd 'lua vim.o.exrc = true' "$@"
      '';
    };
  }) // {
    lib = {
      # -- For all systems --
      inherit forAllSystemsWithPkgs forSpecSystemsWithPkgs;

      # -- Env processing --
      getEnv = varName: let 
        var = builtins.getEnv varName;
      in 
      if var != "" then
        var
      else if minorEnvironment ? varName then
        minorEnvironment."${varName}"
      else
        throw (envErrorMessage varName);

      # -- Cargo.toml --
      cargo = src: (builtins.fromTOML (builtins.readFile "${src}/Cargo.toml"));
    };
  };
}
