from subprocess import check_output
import sys
from pycparser import c_ast
from pycparser.c_lexer import CLexer
from pycparser.c_parser import CParser

def toCamel(st: str) -> str:
    ret = []
    has_underline = False
    for x in st:
        if x == '_':
            has_underline = True
        else:
            if has_underline:
                x = x.upper()
            ret.append(x)
            has_underline = False

    return ''.join(ret)

def zigtypename(type: c_ast.Node) -> str:
    if isinstance(type, c_ast.PtrDecl):
        return '*' + zigtypename(type.type)
    if isinstance(type, c_ast.TypeDecl):
        return ' '.join(type.quals + [type.type.names[0]])

    raise Exception('Not dealt with yet.')

def getname(type: c_ast.Node) -> str:
    if isinstance(type, c_ast.FuncDecl) or isinstance(type, c_ast.PtrDecl):
        return getname(type.type)
    if isinstance(type, c_ast.TypeDecl):
        return type.declname
    else:
        print(type)

    raise Exception('Not dealt with yet.')

# A simple visitor for FuncDef nodes that prints the names and
# locations of function definitions.
class FuncDefVisitor(c_ast.NodeVisitor):
    def visit_FuncDecl(self, node):
        fnname = getname(node)
        rettype = zigtypename(node.type)
        def args():
            args = node.args
            if args == None:
                return []
            else:
                return args.params

        argszig = []
        for x in args():
            parname = x.name
            argszig.append('{}: {}'.format(parname, zigtypename(x.type)))

        argscall = []
        for x in args():
            parname = x.name
            argscall.append(parname)


        argszig = ', '.join(['self: Self'] + argszig[1:])
        argscall = ', '.join(['self.raw'] + argscall[1:])
        zigfnname = fnname.strip('g_').strip('gi_')
        zigfnname = toCamel(zigfnname);
        print(f'pub fn {zigfnname}({argszig}) {rettype} {{\n\treturn C.{fnname}({argscall});\n}}')

class AllEncompassingLexer(CLexer):
    pass

def show_func_defs(string):
    ast = CParser().parse(string)

    v = FuncDefVisitor()
    v.visit(ast)

def collect_defs(string, pkg) -> str:
    import tempfile
    import os
    flags = check_output(f'pkg-config --cflags {pkg}'.split()).decode().split()
    fd, name = tempfile.mkstemp()
    with os.fdopen(fd, 'w') as file:
        file.write(string)
        file.flush()
        expanded = check_output(['cpp'] + flags + [name])
        with open("expanded.c", 'wb') as f:
            f.write(expanded)
        os.remove(name)
    return expanded.decode()
    

if __name__ == "__main__":
    if len(sys.argv) > 1:
        string  = sys.argv[1]
    else:
        string = sys.stdin.read(-1)

    string = collect_defs(string, 'gobject-introspection-1.0')
    print('\n'.join(['// '+x for x in ('input: \n' + string).splitlines() ]))

    show_func_defs(string)
