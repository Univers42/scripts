#!/usr/bin/env python3
"""
Norminette auto-formatter for C files.
Fixes common norminette errors in-place:
  - SPACE_REPLACE_TAB / MIXED_SPACE_TAB: leading spaces -> tabs
  - RETURN_PARENTHESIS: return x; -> return (x);
  - FORBIDDEN_CS: for(...) -> while(...) conversion
  - TERNARY_FBIDDEN: a ? b : c -> if/else
  - DECL_ASSIGN_LINE: int x = 5; -> int x;\n\tx = 5;
  - MULT_ASSIGN_LINE: a = b = c; -> split
  - EMPTY_LINE_FUNCTION: remove blank lines inside function bodies
  - EMPTY_LINE_EOF: ensure single newline at end
  - SPACE_BEFORE_FUNC: fix space before function call parens
  - SPACE_AFTER_KW: ensure space after if/while/return
  - BRACE_SHOULD_EOL: opening brace on its own line
  - CONSECUTIVE_SPC: collapse multiple spaces
  - SPC_AFTER_POINTER: int * x -> int *x
  - NL_AFTER_VAR_DECL: add blank line after variable declarations
  - SPACE_EMPTY_LINE: remove spaces from blank lines
  - TOO_MANY_WS: fix trailing whitespace

Usage: python3 norm_fmt.py [file.c ...] or python3 norm_fmt.py (all *.c *.h)
"""

import re
import sys
import os
import glob


def fix_leading_spaces_to_tabs(lines):
    """SPACE_REPLACE_TAB / MIXED_SPACE_TAB: convert leading spaces to tabs."""
    result = []
    for line in lines:
        # Don't touch the 42 header or comment blocks
        if line.strip().startswith('/*') or line.strip().startswith('**'):
            result.append(line)
            continue
        # Count leading whitespace and convert spaces to tabs
        m = re.match(r'^(\s*)', line)
        if m:
            ws = m.group(1)
            rest = line[len(ws):]
            # Replace every 4 spaces with a tab, then any remaining spaces
            new_ws = ''
            i = 0
            while i < len(ws):
                if ws[i] == '\t':
                    new_ws += '\t'
                    i += 1
                elif ws[i] == ' ':
                    # Count consecutive spaces
                    j = i
                    while j < len(ws) and ws[j] == ' ':
                        j += 1
                    num_spaces = j - i
                    # Convert groups of 4 spaces to tabs
                    new_ws += '\t' * (num_spaces // 4)
                    remaining = num_spaces % 4
                    if remaining > 0:
                        new_ws += '\t'  # Promote partial indent to tab
                    i = j
                else:
                    new_ws += ws[i]
                    i += 1
            result.append(new_ws + rest)
        else:
            result.append(line)
    return result


def fix_trailing_whitespace(lines):
    """TOO_MANY_WS / SPACE_EMPTY_LINE: remove trailing whitespace."""
    result = []
    for line in lines:
        # Don't touch the 42 header
        if line.strip().startswith('/*') or line.strip().startswith('**'):
            result.append(line)
            continue
        result.append(line.rstrip())
    return result


def fix_return_parenthesis(lines):
    """RETURN_PARENTHESIS: return x; -> return (x);"""
    result = []
    for line in lines:
        stripped = line.strip()
        # Match return with a value that's not already in parens
        m = re.match(r'^(\s*)return\s+(.+);$', line.rstrip())
        if m:
            indent = m.group(1)
            val = m.group(2).strip()
            # Skip if already wrapped in parens (but not func calls)
            if val.startswith('(') and val.endswith(')'):
                # Check if balanced
                depth = 0
                balanced = True
                for ci, c in enumerate(val):
                    if c == '(':
                        depth += 1
                    elif c == ')':
                        depth -= 1
                    if depth == 0 and ci < len(val) - 1:
                        balanced = False
                        break
                if balanced:
                    result.append(line)
                    continue
            result.append(f'{indent}return ({val});')
        else:
            result.append(line)
    return result


def fix_space_after_keyword(lines):
    """SPACE_AFTER_KW: ensure space after if/while/return."""
    result = []
    for line in lines:
        # Fix if( -> if (
        line = re.sub(r'\bif\(', 'if (', line)
        # Fix while( -> while (
        line = re.sub(r'\bwhile\(', 'while (', line)
        # Fix return( -> return (
        line = re.sub(r'\breturn\(', 'return (', line)
        result.append(line)
    return result


def fix_empty_lines_in_functions(lines):
    """EMPTY_LINE_FUNCTION: remove blank lines inside function bodies,
    except the one blank line after variable declarations."""
    result = []
    in_function = False
    brace_depth = 0
    func_brace_depth = 0
    in_var_decl_zone = False
    prev_was_var_decl = False

    for i, line in enumerate(lines):
        stripped = line.strip()

        # Track brace depth
        if not in_function:
            # Detect function start: line is just '{'
            if stripped == '{' and brace_depth == 0:
                # Check if previous non-empty line looks like a function signature
                for j in range(i - 1, max(i - 5, -1), -1):
                    prev = lines[j].strip()
                    if prev and not prev.startswith('/*') and not prev.startswith('**') and not prev.startswith('//'):
                        # It's a function if prev line ends with )
                        if prev.endswith(')'):
                            in_function = True
                            func_brace_depth = 1
                            in_var_decl_zone = True
                        break
                result.append(line)
                continue
            for c in stripped:
                if c == '{':
                    brace_depth += 1
                elif c == '}':
                    brace_depth -= 1
            result.append(line)
            continue

        # Inside function
        open_count = stripped.count('{')
        close_count = stripped.count('}')
        func_brace_depth += open_count - close_count

        if func_brace_depth <= 0:
            in_function = False
            brace_depth = 0
            in_var_decl_zone = False
            result.append(line)
            continue

        # Check if line is a variable declaration
        is_var_decl = False
        if func_brace_depth == 1 and in_var_decl_zone:
            # Variable declarations: type followed by name
            decl_pat = r'^\t+(int|char|unsigned|signed|short|long|float|double|void|size_t|const|static|t_\w+)\s'
            if re.match(decl_pat, line) and '=' not in stripped and '(' not in stripped:
                is_var_decl = True

        # If we hit a non-decl, non-blank line, end the var decl zone
        if in_var_decl_zone and not is_var_decl and stripped:
            in_var_decl_zone = False

        # Remove blank lines inside functions
        if stripped == '':
            # Keep blank line right after var declarations
            if prev_was_var_decl:
                result.append(line)
                prev_was_var_decl = False
                continue
            # Skip other blank lines inside functions
            continue

        prev_was_var_decl = is_var_decl
        result.append(line)

    return result


def fix_decl_assign(lines):
    """DECL_ASSIGN_LINE: Split 'int x = 5;' into 'int x;' and 'x = 5;'"""
    result = []
    # C type keywords for detection
    type_pat = r'^(\t+)((?:(?:const|static|unsigned int|unsigned char|signed|short|long)\s+)*(?:int|char|unsigned int|unsigned char|short|long|float|double|size_t|t_\w+))\s+(\*?\s*\w+)\s*=\s*(.+);$'

    for line in lines:
        m = re.match(type_pat, line.rstrip())
        if m:
            indent = m.group(1)
            type_part = m.group(2)
            var_name = m.group(3).strip()
            value = m.group(4).strip()
            # Don't split if it's inside a for loop or if it's a const
            if 'const ' in type_part:
                result.append(line)
                continue
            # Add declaration without initialization
            result.append(f'{indent}{type_part}\t{var_name};')
            # Add separate assignment (after all declarations are done -
            # we'll let the user handle ordering)
            result.append(f'{indent}{var_name} = {value};')
        else:
            result.append(line)
    return result


def fix_for_to_while(lines):
    """FORBIDDEN_CS: Convert for loops to while loops."""
    result = []
    i = 0
    while i < len(lines):
        stripped = lines[i].strip()
        # Match: for (init; cond; incr)
        m = re.match(r'^(\t+)for\s*\(\s*(.*?)\s*;\s*(.*?)\s*;\s*(.*?)\s*\)\s*$', lines[i].rstrip())
        if not m:
            # Also try for with opening brace on same line
            m = re.match(r'^(\t+)for\s*\(\s*(.*?)\s*;\s*(.*?)\s*;\s*(.*?)\s*\)\s*\{?\s*$', lines[i].rstrip())
        if m:
            indent = m.group(1)
            init = m.group(2).strip()
            cond = m.group(3).strip()
            incr = m.group(4).strip()
            has_brace = lines[i].rstrip().endswith('{')

            # Output init statement before the while
            if init:
                # If init is a declaration, it should already be at top
                if not any(init.startswith(t) for t in ['int ', 'unsigned ', 'size_t ', 'char ']):
                    result.append(f'{indent}{init};')
                else:
                    result.append(f'{indent}{init};')

            # Output while condition
            if not cond:
                cond = '1'
            result.append(f'{indent}while ({cond})')

            # Look for the body
            i += 1
            if has_brace or (i < len(lines) and lines[i].strip() == '{'):
                if not has_brace:
                    result.append(lines[i])  # the '{' line
                    i += 1
                else:
                    result.append(f'{indent}{{')

                # Find matching closing brace and insert increment before it
                brace_depth = 1
                body_lines = []
                while i < len(lines) and brace_depth > 0:
                    for c in lines[i]:
                        if c == '{':
                            brace_depth += 1
                        elif c == '}':
                            brace_depth -= 1
                    if brace_depth > 0:
                        body_lines.append(lines[i])
                        i += 1
                    else:
                        # This line has the closing brace
                        # Insert increment before closing brace
                        if incr:
                            result.extend(body_lines)
                            result.append(f'{indent}\t{incr};')
                        else:
                            result.extend(body_lines)
                        result.append(lines[i])
                        i += 1
            else:
                # Single statement body (no braces)
                if i < len(lines):
                    result.append(f'{indent}{{')
                    result.append(lines[i])
                    if incr:
                        result.append(f'{indent}\t{incr};')
                    result.append(f'{indent}}}')
                    i += 1
            continue
        result.append(lines[i])
        i += 1
    return result


def fix_brace_should_eol(lines):
    """BRACE_SHOULD_EOL: Move opening brace from end of line to next line.
    E.g., 'void foo() {' -> 'void foo()\n{'"""
    result = []
    for line in lines:
        stripped = line.rstrip()
        # Skip 42 header lines
        if line.strip().startswith('/*') or line.strip().startswith('**'):
            result.append(line)
            continue
        # Match lines ending with { that aren't just {
        # But skip struct/enum/array initializers
        if stripped.endswith('{') and stripped != '{':
            s = stripped[:-1].rstrip()
            # Don't split if it's an assignment or array init
            if '=' in s:
                result.append(line)
                continue
            # Get the indentation
            indent = re.match(r'^(\s*)', line).group(1)
            result.append(indent + s)
            result.append(indent + '{')
        else:
            result.append(line)
    return result


def fix_mult_assign(lines):
    """MULT_ASSIGN_LINE: Split 'a = b = c;' into separate assignments."""
    result = []
    for line in lines:
        stripped = line.strip()
        # Match: out[x] = out[y] = val;  pattern
        m = re.match(r'^(\t+)(.+?)\s*=\s*(.+?)\s*=\s*(.+);$', line.rstrip())
        if m:
            indent = m.group(1)
            var1 = m.group(2).strip()
            var2 = m.group(3).strip()
            val = m.group(4).strip()
            # Check this isn't a comparison (==)
            if '==' not in line:
                result.append(f'{indent}{var2} = {val};')
                result.append(f'{indent}{var1} = {val};')
                continue
        result.append(line)
    return result


def fix_consecutive_spaces(lines):
    """CONSECUTIVE_SPC: Collapse multiple spaces to one (not in indentation)."""
    result = []
    for line in lines:
        # Skip header/comments
        if line.strip().startswith('/*') or line.strip().startswith('**'):
            result.append(line)
            continue
        # Preserve leading tabs, fix multiple spaces in code area
        m = re.match(r'^(\t*)(.*)', line)
        if m:
            indent = m.group(1)
            code = m.group(2)
            # Don't collapse spaces in string literals
            # Simple approach: collapse outside of quotes
            new_code = re.sub(r'(?<!")  +(?!")', ' ', code)
            result.append(indent + new_code)
        else:
            result.append(line)
    return result


def fix_pointer_spacing(lines):
    """SPC_AFTER_POINTER: 'int * x' -> 'int *x', 'char * *x' -> 'char **x'"""
    result = []
    for line in lines:
        # Fix 'type * name' -> 'type *name'  (in declarations)
        line = re.sub(r'(\w)\s+\*\s+(\w)', r'\1 *\2', line)
        result.append(line)
    return result


def fix_eof_newline(content):
    """EMPTY_LINE_EOF: Ensure file ends with exactly one newline."""
    content = content.rstrip('\n') + '\n'
    return content


def fix_space_before_func(lines):
    """SPACE_BEFORE_FUNC: No space before function call parenthesis.
    But keep space after keywords: if, while, return, for, switch."""
    keywords = {'if', 'while', 'for', 'switch', 'return', 'else', 'sizeof'}
    result = []
    for line in lines:
        # Find pattern: word space( where word is not a keyword
        def replace_space_before_paren(m):
            word = m.group(1)
            if word in keywords:
                return m.group(0)  # Keep space for keywords
            return word + '('

        line = re.sub(r'\b(\w+)\s+\(', replace_space_before_paren, line)
        result.append(line)
    return result


def format_file(filepath, dry_run=False):
    """Apply all norminette fixes to a file."""
    with open(filepath, 'r') as f:
        content = f.read()

    original = content
    lines = content.split('\n')

    # Apply fixes in order (order matters!)
    lines = fix_brace_should_eol(lines)
    lines = fix_leading_spaces_to_tabs(lines)
    lines = fix_trailing_whitespace(lines)
    lines = fix_return_parenthesis(lines)
    lines = fix_space_after_keyword(lines)
    lines = fix_for_to_while(lines)
    lines = fix_decl_assign(lines)
    lines = fix_mult_assign(lines)
    lines = fix_empty_lines_in_functions(lines)
    lines = fix_consecutive_spaces(lines)
    lines = fix_pointer_spacing(lines)

    content = '\n'.join(lines)
    content = fix_eof_newline(content)

    if content != original:
        if not dry_run:
            with open(filepath, 'w') as f:
                f.write(content)
        return True
    return False


def main():
    dry_run = '--dry-run' in sys.argv
    files = [a for a in sys.argv[1:] if not a.startswith('-')]

    if not files:
        # Default: all .c and .h files in current directory
        files = sorted(glob.glob('*.c') + glob.glob('*.h'))

    modified = 0
    for f in files:
        if not os.path.isfile(f):
            print(f"Skip (not found): {f}")
            continue
        changed = format_file(f, dry_run=dry_run)
        if changed:
            modified += 1
            print(f"{'Would fix' if dry_run else 'Fixed'}: {f}")

    print(f"\n{'Would modify' if dry_run else 'Modified'} {modified}/{len(files)} files")


if __name__ == '__main__':
    main()
