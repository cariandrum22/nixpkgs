# VPP uses nested blocks, bare flags and repeated directives, rather than INI.
{ lib }:
let
  inherit (lib) types;
  valueType = types.nullOr (
    types.oneOf [
      types.bool
      types.int
      types.float
      types.str
      types.path
      (types.attrsOf valueType)
      (types.listOf valueType)
    ]
  );
  render =
    indent: name: value:
    if value == null || value == false then
      ""
    else if name == "extraConfig" then
      lib.concatMapStringsSep "\n" (line: indent + line) (lib.splitString "\n" value) + "\n"
    else if builtins.isList value then
      lib.concatMapStrings (render indent name) value
    else if builtins.isAttrs value then
      "${indent}${name} {\n" + renderAttrs (indent + "  ") value + "${indent}}\n"
    else
      "${indent}${name}${lib.optionalString (value != true) " ${toString value}"}\n";
  renderAttrs =
    indent: attrs:
    lib.concatStrings (
      lib.mapAttrsToList (render indent) (builtins.removeAttrs attrs [ "extraConfig" ])
    )
    + render indent "extraConfig" (attrs.extraConfig or null);
  sectionType = types.nullOr (types.attrsOf valueType);
in
{
  inherit valueType sectionType;
  type = types.attrsOf sectionType;
  render = renderAttrs "";
}
