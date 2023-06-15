import re
import sys

def main():
    if len(sys.argv) < 3:
        print("Usage: python3 vyper_to_solidity_interface.py [input_vyper_file] [output_solidity_file]")
        sys.exit(1)

    input_vyper_file = sys.argv[1]
    output_solidity_file = sys.argv[2]

    with open(input_vyper_file, 'r') as f:
        vyper_code = f.read()

    solidity_interface = generate_solidity_interface(vyper_code)

    with open(output_solidity_file, 'w') as f:
        f.write(solidity_interface)

def convert_vyper_arg_to_solidity(arg):
    if ':' not in arg:
        return ''
    var_name, var_type = arg.split(':')
    return f"{var_type.strip()} {var_name.strip()}"


def generate_solidity_interface(vyper_code):
    function_regex = r"@(external|public|view|pure|payable)(?:\s|\n)+def\s+(\w+)\(([^)]*)\)(?:\s*->\s*([^:\n{]*)(?::\s*[^{]*)?)?"
    functions = re.findall(function_regex, vyper_code, re.MULTILINE)

    public_var_regex = r"(\w+)\s*:\s*public\((\w+)\)"
    public_vars = re.findall(public_var_regex, vyper_code, re.MULTILINE)

    const_var_regex = r"const\s+(\w+)\s*:\s*(\w+)"
    const_vars = re.findall(const_var_regex, vyper_code, re.MULTILINE)

    mapping_regex = r"(\w+):\s*public\((HashMap\[\w+,\s*[\w\[\]]+\])\)"
    mappings = re.findall(mapping_regex, vyper_code, re.MULTILINE)

    interface_lines = [
        "// SPDX-License-Identifier: MIT",
        "pragma solidity ^0.8.0;",
        "",
        "interface IVyperContract {",
    ]

    for modifier, func_name, args, return_type in functions:
        if func_name == "__init__":
            continue

        args = args.split(',')
        arg_str = ', '.join([convert_vyper_arg_to_solidity(arg) for arg in args if arg.strip()])
        return_type_str = return_type.strip()

        if return_type_str:
            return_type_str = f"returns ({return_type_str})"
        interface_lines.append(f"    function {func_name}({arg_str}) {modifier} {return_type_str};")

    for var_name, var_type in public_vars + const_vars:
        interface_lines.append(f"    function {var_name}() external view returns ({var_type});")

    for mapping_name, mapping_type in mappings:
        key_type, value_type = re.search(r"HashMap\[(\w+),\s*([\w\[\]]+)\]", mapping_type).groups()
        key_type_solidity = convert_vyper_arg_to_solidity(key_type)
        interface_lines.append(f"    function {mapping_name}({key_type_solidity}) external view returns ({value_type});")

    interface_lines.append("}")

    return '\n'.join(interface_lines)

if __name__ == '__main__':
    main()
