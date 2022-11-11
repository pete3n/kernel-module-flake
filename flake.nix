{
  description = "A very basic flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    neovim-flake.url = "github:jordanisaacs/neovim-flake";
    nixos-generators = {
      url = "github:nix-community/nixos-generators";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    self,
    nixpkgs,
    neovim-flake,
    nixos-generators,
  }: let
    system = "x86_64-linux";

    pkgs = let
      kernelArgs = with pkgs; rec {
        version = "6.0.8";
        # branchVersion needs to be x.y
        extraMeta.branch = lib.versions.majorMinor version;
        src = fetchurl {
          url = "mirror://kernel/linux/kernel/v6.x/linux-${version}.tar.xz";
          sha256 = "0mx2bxgnxm3vz688268939xw90jqci7xn992kfpny74mjqwzir0d";
        };

        localVersion = "-dev";
        modDirVersion = version + localVersion;

        structuredExtraConfig = with pkgs.lib.kernel; {
          DEBUG_INFO = yes;
          DEBUG_FS = yes;
          DEBUG_KERNEL = yes;
          DEBUG_MISC = yes;
          DEBUG_BUGVERBOSE = yes;
          DEBUG_BOOT_PARAMS = yes;
          DEBUG_STACK_USAGE = yes;
          DEBUG_SHIRQ = yes;
          DEBUG_ATOMIC_SLEEP = yes;

          IKCONFIG = yes;
          IKCONFIG_PROC = yes;

          SLUB_DEBUG = yes;
          DEBUG_MEMORY_INIT = yes;
          KASAN = yes;

          MAGIC_SYSRQ = yes;

          LOCALVERSION = freeform localVersion;

          LOCK_STAT = yes;
          PROVE_LOCKING = yes;

          FTRACE = yes;
          STACKTRACE = yes;
          IRQSOFF_TRACER = yes;

          KGDB = yes;
          UBSAN = yes;
          BUG_ON_DATA_CORRUPTION = yes;
          SCHED_STACK_END_CHECK = yes;
          UNWINDER_FRAME_POINTER = yes;
          "64BIT" = yes;

          # initramfs/initrd support
          BLK_DEV_INITRD = yes;

          PRINTK = yes;
          EARLY_PRINTK = yes;

          # Support elf and #! scripts
          BINFMT_ELF = yes;
          BINFMT_SCRIPT = yes;

          # Create a tmpfs/ramfs early at bootup.
          DEVTMPFS = yes;
          DEVTMPFS_MOUNT = yes;

          TTY = yes;
          SERIAL_8250 = yes;
          SERIAL_8250_CONSOLE = yes;

          PROC_FS = yes;
          SYSFS = yes;

          MODULES = yes;
          MODULE_UNLOAD = yes;
          # FW_LOADER = yes;
        };

        # Flags that get passed to generate-config.pl
        generateConfigFlags = {
          # Ignores any config errors (eg unused config options)
          ignoreConfigErrors = true;
          # Build every available module
          autoModules = false;
          preferBuiltin = false;
        };
      };

      # Config file derivation
      configfile = with pkgs;
        stdenv.mkDerivation {
          kernelArch = stdenv.hostPlatform.linuxArch;
          extraMakeFlags = [];

          inherit (kernel) src patches version;
          pname = "linux-config";

          inherit (kernelArgs.generateConfigFlags) autoModules preferBuiltin ignoreConfigErrors;
          generateConfig = "${nixpkgs}/pkgs/os-specific/linux/kernel/generate-config.pl";

          kernelConfig = configfile.moduleStructuredConfig.intermediateNixConfig;
          passAsFile = ["kernelConfig"];

          depsBuildBuild = [buildPackages.stdenv.cc];
          nativeBuildInputs = [perl gmp libmpc mpfr bison flex pahole];

          platformName = stdenv.hostPlatform.linux-kernel.name;
          # e.g. "bzImage"
          kernelTarget = stdenv.hostPlatform.linux-kernel.target;

          makeFlags =
            lib.optionals (stdenv.hostPlatform.linux-kernel ? makeFlags) stdenv.hostPlatform.linux-kernel.makeFlags;

          postPatch =
            kernel.postPatch
            + ''
              # Patch kconfig to print "###" after every question so that
              # generate-config.pl from the generic builder can answer them.
              sed -e '/fflush(stdout);/i\printf("###");' -i scripts/kconfig/conf.c
            '';

          preUnpack = kernel.preUnpack or "";

          buildPhase = ''
            export buildRoot="''${buildRoot:-build}"
            export HOSTCC=$CC_FOR_BUILD
            export HOSTCXX=$CXX_FOR_BUILD
            export HOSTAR=$AR_FOR_BUILD
            export HOSTLD=$LD_FOR_BUILD
            # Get a basic config file for later refinement with $generateConfig.
            ls
            make $makeFlags \
              -C . O="$buildRoot" allnoconfig \
              HOSTCC=$HOSTCC HOSTCXX=$HOSTCXX HOSTAR=$HOSTAR HOSTLD=$HOSTLD \
              CC=$CC OBJCOPY=$OBJCOPY OBJDUMP=$OBJDUMP READELF=$READELF \
              $makeFlags

            # Create the config file.
            echo "generating kernel configuration..."
            ln -s "$kernelConfigPath" "$buildRoot/kernel-config"
            DEBUG=1 ARCH=$kernelArch KERNEL_CONFIG="$buildRoot/kernel-config" AUTO_MODULES=$autoModules \
              PREFER_BUILTIN=$preferBuiltin BUILD_ROOT="$buildRoot" SRC=. MAKE_FLAGS="$makeFlags" \
              perl -w $generateConfig
          '';

          installPhase = "mv $buildRoot/.config $out";

          enableParallelBuilding = true;

          passthru = rec {
            module = import "${nixpkgs}/nixos/modules/system/boot/kernel_config.nix";
            # used also in apache
            # { modules = [ { options = res.options; config = svc.config or svc; } ];
            #   check = false;
            # The result is a set of two attributes
            moduleStructuredConfig =
              (lib.evalModules {
                modules = [
                  module
                  {
                    settings = kernelArgs.structuredExtraConfig;
                    _file = "structuredExtraConfig";
                  }
                ];
              })
              .config;

            structuredConfig = moduleStructuredConfig.settings;
          };
        };

      kernel = (pkgs.callPackage "${nixpkgs}/pkgs/os-specific/linux/kernel/manual-config.nix" {}) {
        inherit (kernelArgs) src modDirVersion version;
        inherit (pkgs) lib stdenv;
        inherit configfile;

        # Because allowedImportFromDerivation is not enabled,
        # the function cannot set anything based on the configfile. These settings do not
        # actually change the .config but let the kernel derivation know what can be built.
        # See manual-config.nix for other options
        config = {
          # Enables the dev build
          CONFIG_MODULES = "y";
        };
      };

      kernelPassthru = with pkgs; {
        inherit (kernelArgs) structuredExtraConfig modDirVersion configfile;
        passthru = kernel.passthru // (removeAttrs kernelPassthru ["passthru"]);
      };

      finalKernel = pkgs.lib.extendDerivation true kernelPassthru kernel;
    in
      import nixpkgs {
        inherit system;
        overlays = [
          neovim-flake.overlays.default
          (self: super: {
            linuxDev = self.linuxPackagesFor kernel;
            busybox = super.busybox.override {
              enableStatic = true;
            };
            neovimConfig = self.neovimBuilder {
              config = {
                vim.lsp = {
                  enable = true;
                  lightbulb.enable = true;
                  lspSignature.enable = true;
                  trouble.enable = true;
                  nvimCodeActionMenu.enable = true;
                  formatOnSave = true;
                  clang = {
                    enable = true;
                    c_header = true;
                  };
                  nix = true;
                };
                vim.statusline.lualine = {
                  enable = true;
                  theme = "onedark";
                };
                vim.visuals = {
                  enable = true;
                  nvimWebDevicons.enable = true;
                  lspkind.enable = true;
                  indentBlankline = {
                    enable = true;
                    fillChar = "";
                    eolChar = "";
                    showCurrContext = true;
                  };
                  cursorWordline = {
                    enable = true;
                    lineTimeout = 0;
                  };
                };
                vim.theme = {
                  enable = true;
                  name = "onedark";
                  style = "darker";
                };
                vim.autopairs.enable = true;
                vim.autocomplete = {
                  enable = true;
                  type = "nvim-cmp";
                };
                vim.filetree.nvimTreeLua.enable = true;
                vim.tabline.nvimBufferline.enable = true;
                vim.telescope = {
                  enable = true;
                };
                vim.markdown = {
                  enable = true;
                  glow.enable = true;
                };
                vim.treesitter = {
                  enable = true;
                  context.enable = true;
                };
                vim.keys = {
                  enable = true;
                  whichKey.enable = true;
                };
                vim.git = {
                  enable = true;
                  gitsigns.enable = true;
                };
                vim.tabWidth = 8;
              };
            };
          })
        ];
      };
  in (let
    linuxPackages = pkgs.linuxDev;
    kernel = linuxPackages.kernel;

    # config = {
    #   config,
    #   lib,
    #   pkgs,
    #   ...
    # }: {
    #   boot.kernelPackages = linuxPackages;
    #   system.stateVersion = "21.11";
    #   users.users.root = {
    #     password = "hello";
    #     # openssh.authorizedKeys.keys = [(builtins.readFile "/home/jd/.ssh/id_ed25519.pub")];
    #   };
    #   networking.firewall.enable = false;
    #   services.openssh = {
    #     enable = true;
    #     # permitRootLogin = "prohibit-password";
    #     # Allow password login, otherwise add an authorized keys
    #     permitRootLogin = "yes";
    #   };
    # };
    # sshQemu = pkgs.writeScriptBin "sshvm" ''
    #   ssh root@127.0.0.1 -p $QSSH
    # '';
    # runQemu = pkgs.writeScriptBin "runvm" ''
    #   sudo qemu-system-x86_64 \
    #     -enable-kvm \
    #     -m 2048 \
    #     -nic user,model=virtio,hostfwd=tcp::''${QSSH}-:22 \
    #     -drive file=nixos.qcow2,media=disk,if=virtio \
    #     -monitor tcp:127.0.0.1:''${QMON},server,nowait \
    #     -snapshot \
    #     -display none \
    #     -daemonize
    # '';
    # killQemu = pkgs.writeScriptBin "killvm" "echo 'system_powerdown' | nc 127.0.0.1 $QMON";
    # scpMod = pkgs.writeScriptBin "scpmod" ''
    #   nix build .#$1
    #   cd $SRC_DIR/result
    #   for x in $(find . -name '*.ko'); do
    #     echo "Copying $x to VM"
    #     scp -P $QSSH $x root@localhost:~/
    #   done
    # '';

    runQemuV2 = pkgs.writeScriptBin "runvm" ''
      sudo qemu-system-x86_64 \
        -enable-kvm \
        -kernel ${kernel}/bzImage \
        -initrd ${initramfs}/initrd.gz \
        -nographic -append "console=ttyS0"
    '';

    buildInputs = with pkgs; [
      nukeReferences
      kernel.dev
    ];

    nativeBuildInputs = with pkgs;
      [
        bear # for compile_commands.json, use bear -- make
        runQemuV2
        git
        neovimConfig
        gdb
        qemu
      ]
      ++ buildInputs;

    helloworld =
      pkgs.stdenv.mkDerivation
      {
        KERNEL = kernel.dev;
        KERNEL_VERSION = kernel.modDirVersion;
        name = "helloworld";
        inherit buildInputs;
        src = ./helloworld;

        installPhase = ''
          mkdir -p $out/lib/modules/$KERNEL_VERSION/misc
          for x in $(find . -name '*.ko'); do
            nuke-refs $x
            cp $x $out/lib/modules/$KERNEL_VERSION/misc/
          done
        '';

        meta.platforms = ["x86_64-linux"];
      };

    initramfs = let
      initrdBinEnv = pkgs.buildEnv {
        name = "initrd-emergency-env";
        paths = map pkgs.lib.getBin initrdBin;
        pathsToLink = ["/bin" "/sbin"];
      };

      config = {
        "/bin" = "${initrdBinEnv}/bin";
        "/sbin" = "${initrdBinEnv}/sbin";
        "/init" = init;
        "/modules" = "${helloworld}/lib/modules/${kernel.modDirVersion}/misc";
      };

      initrdBin = [pkgs.bash pkgs.busybox pkgs.kmod];

      storePaths = []; #["/proc" "/sys"];

      initialRamdisk = pkgs.makeInitrdNG {
        compressor = "gzip";
        strip = false;
        contents =
          map (path: {
            object = path;
            symlink = "";
          })
          storePaths
          ++ pkgs.lib.mapAttrsToList (n: v: {
            object = v;
            symlink = n;
          })
          config;
      };
      init = pkgs.writeScript "init" ''
        #!/bin/sh

        export PATH=/bin/

        mkdir /proc
        mkdir /sys
        mount -t proc none /proc
        mount -t sysfs none /sys

        cat <<!

        Boot took $(cut -d' ' -f1 /proc/uptime) seconds

                _       _     __ _
          /\/\ (_)_ __ (_)   / /(_)_ __  _   ___  __
         /    \| | '_ \| |  / / | | '_ \| | | \ \/ /
        / /\/\ \ | | | | | / /__| | | | | |_| |>  <
        \/    \/_|_| |_|_| \____/_|_| |_|\__,_/_/\_\

        Welcome to mini_linux


        !
        exec /bin/sh
      '';
    in
      initialRamdisk;
  in {
    packages.${system} = {
      inherit initramfs kernel helloworld;

      # qemu = nixos-generators.nixosGenerate {
      #   system = "x86_64-linux";
      #   modules = [
      #     config
      #   ];
      #   format = "qcow";
      # };
    };

    devShells.${system} = {
      default = pkgs.mkShell {
        inherit nativeBuildInputs;
        # QMON = 7777;
        # QSSH = 3333;
        # SRC_DIR = ./.;
        # KERNEL = kernel.dev;
        # KERNEL_VERSION = kernel.modDirVersion;
        # shellHook = ''
        #   if [ ! -e nixos.qcow2 ]
        #   then
        #     nix build --impure .#qemu
        #     cp ./result/nixos.qcow2 ./
        #   fi
        #   export SRC_DIR=$(pwd)
        # '';
      };
    };
  });
}
