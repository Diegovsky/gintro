#!/usr/bin/env python3
# Stuff used to generate some structures that fall out of the scope of gintro.
import sys

typeinfo = """GI_INFO_TYPE_INVALID
GI_INFO_TYPE_FUNCTION
GI_INFO_TYPE_CALLBACK
GI_INFO_TYPE_STRUCT
GI_INFO_TYPE_BOXED
GI_INFO_TYPE_ENUM
GI_INFO_TYPE_FLAGS
GI_INFO_TYPE_OBJECT
GI_INFO_TYPE_INTERFACE
GI_INFO_TYPE_CONSTANT
GI_INFO_TYPE_UNION
GI_INFO_TYPE_VALUE
GI_INFO_TYPE_SIGNAL
GI_INFO_TYPE_VFUNC
GI_INFO_TYPE_PROPERTY
GI_INFO_TYPE_FIELD
GI_INFO_TYPE_ARG
GI_INFO_TYPE_TYPE
GI_INFO_TYPE_UNRESOLVED""".split("\n")


def die(text=""):
    sys.stderr.write(text+"\n")
    sys.exit(-1)


def generateEnum(name: str, prefix: str, variants: list[str]) -> list:
    out = []
    indent = 4
    out.append("const {} = enum(c_int) {{\n".format(name))
    for var in variants:
        if not var.startswith(prefix):
            die("Variant '{}' of '{}' doesn't start with '{}'".format(var, name, prefix))

        # Yes, this could be a one-liner but I like readability.
        variant = var[len(prefix):]
        variant = variant.split("_")
        variant = map(str.capitalize, variant)
        variant = ''.join(variant)
        out.append(' '*indent + "{} = {},\n".format(variant, var))

    out.append("};\n")
    return out


if __name__ == '__main__':
    sys.stdout.writelines(generateEnum("TypeInfo", "GI_INFO_TYPE", typeinfo))
