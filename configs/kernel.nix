{
  pkgs,
  lib ? pkgs.lib,
  enableRust,
  enableBPF,
  enableGdb,
  useRustForLinux,
}:
let
  version = "5.10.120";
  localVersion = "-development";
in
{
  kernelArgs = {
    inherit enableRust enableGdb;

    inherit version;
    src =
      if useRustForLinux then
        builtins.fetchurl {
          url = "https://github.com/Rust-for-Linux/linux/archive/bd123471269354fdd504b65b1f1fe5167cb555fc.tar.gz";
          sha256 = "sha256-BcTrK9tiGgCsmYaKpS/Xnj/nsCVGA2Aoa1AktHBgbB0=";
        }
      else
        pkgs.fetchurl {
          url = "mirror://kernel/linux/kernel/v5.x/linux-${version}.tar.xz";
          sha256 = "sha256-W3p1YAQVjs4vXkF5W6Uj7CAXQ6c240zkHL4JF399Dos=";
        };

    # Add kernel patches here
    kernelPatches =
      let
        fetchSet = lib.imap1 (
          i: hash: {
            # name = " "kbuild-v${builtins.toString i}";
            patch = pkgs.fetchpatch { inherit hash; };
          }
        );

        patches = fetchSet [ ];
      in
      patches;

    inherit localVersion;
    modDirVersion =
      let
        appendV = if useRustForLinux then ".0-rc1" else "";
      in
      version + appendV + localVersion;
  };

  kernelConfig = {
    inherit enableRust;

    # See https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/system/boot/kernel_config.nix
    structuredExtraConfig =
      with lib.kernel;
      {

        DEBUG_FS = yes;
        DEBUG_KERNEL = yes;
        DEBUG_MISC = yes;
        #DEBUG_BUGVERBOSE = yes;
        DEBUG_BOOT_PARAMS = yes;
        DEBUG_STACK_USAGE = yes;
        DEBUG_SHIRQ = yes;
        DEBUG_ATOMIC_SLEEP = yes;

        # Config options for NXP WLAN driver build
        MMC = yes;
        #MMC_BLOCK = module;
        PCI = yes;
        NET = yes;
        INET = yes;
        NETDEVICES = yes;
        WIRELESS = yes;
        CFG80211 = yes;
        CFG80211_WEXT = yes;
        HOSTAP = yes;
        MAC80211 = yes;
        IPV6 = module;

        BT = yes;
        BT_RFCOMM = yes;
        BT_RFCOMM_TTY = yes;
        BT_BNEP = yes;
        BT_BNEP_MC_FILTER = yes;
        BT_BNEP_PROTO_FILTER = yes;
        BT_HIDP = yes;

        IKCONFIG = yes;
        IKCONFIG_PROC = yes;
        # Compile with headers
        IKHEADERS = yes;

        SLUB_DEBUG = yes;
        DEBUG_MEMORY_INIT = yes;
        KASAN = yes;

        # FRAME_WARN - warn at build time for stack frames larger tahn this.

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

        # initramfs/initrd ssupport
        BLK_DEV_INITRD = yes;

        PRINTK = yes;
        PRINTK_TIME = yes;
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
      }
      // lib.optionalAttrs enableBPF {
        BPF_SYSCALL = yes;
        # Enable kprobes and kallsyms: https://www.kernel.org/doc/html/latest/trace/kprobes.html#configuring-kprobes
        # Debug FS is be enabled (done above) to show registered kprobes in /sys/kernel/debug: https://www.kernel.org/doc/html/latest/trace/kprobes.html#the-kprobes-debugfs-interface
        KPROBES = yes;
        KALLSYMS_ALL = yes;
      }
      // lib.optionalAttrs enableRust {
        GCC_PLUGINS = no;
        RUST = yes;
        RUST_OVERFLOW_CHECKS = yes;
        RUST_DEBUG_ASSERTIONS = yes;
      }
      // lib.optionalAttrs enableGdb {
        DEBUG_INFO_DWARF_TOOLCHAIN_DEFAULT = yes;
        GDB_SCRIPTS = yes;
      };

    # Flags that get passed to generate-config.pl
    generateConfigFlags = {
      # Ignores any config errors (eg unused config options)
      ignoreConfigErrors = false;
      # Build every available module
      autoModules = false;
      preferBuiltin = false;
    };
  };
}
