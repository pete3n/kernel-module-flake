{ stdenv, nukeReferences }:
{ kernel }:
{
  name,
  src,
  dontStrip ? false,
  buildPhase ? null,
}:
let
  optionalString = cond: str: if cond then str else "";
in
stdenv.mkDerivation {
  KERNEL = kernel.dev;
  KERNEL_VERSION = kernel.modDirVersion;
  buildInputs = [
    nukeReferences
    kernel.dev
  ];
  inherit name src dontStrip;

  buildPhase = optionalString (buildPhase != null) buildPhase;

  installPhase = ''
    mkdir -p $out/lib/modules/$KERNEL_VERSION/misc
    for x in $(find . -name '*.ko'); do
      nuke-refs $x
      cp $x $out/lib/modules/$KERNEL_VERSION/misc/
    done
  '';

  meta.platforms = [ "x86_64-linux" ];
}
