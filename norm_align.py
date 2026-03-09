#!/usr/bin/env python3
"""
norm_align.py - Fix MISALIGNED_VAR_DECL for norminette compliance.

Detects groups of consecutive variable declarations inside functions/structs
and aligns all variable names to the same tab-stop column using tab characters.

The target column = next tab stop after the longest type in the group.

Usage: python3 norm_align.py [files...]  (default: all *.c *.h in cwd)
"""

import re
import os
import sys
import glob

TAB_W = 4

# Words that can appear in a C type specifier
TYPE_WORDS = {
    'static', 'const', 'volatile', 'register', 'extern',
    'unsigned', 'signed', 'struct', 'enum', 'union',
    'int', 'char', 'float', 'double', 'void',
    'short', 'long', 'size_t', 'ssize_t', 'bool',
    'int8_t', 'int16_t', 'int32_t', 'int64_t',
    'uint8_t', 'uint16_t', 'uint32_t', 'uint64_t',
}


def is_type_word(w):
    """Check if a word is a C type keyword or 42-style typedef (t_xxx)."""
    if w in TYPE_WORDS:
        return True
    if re.match(r'^[tse]_\w+$', w):
        return True
    # Project-specific typedefs that don't follow t_ convention
    if w in ('ucvector', 'uivector'):
        return True
    return False


def visual_col(s):
    """Compute the visual column width of a string containing tabs."""
    col = 0
    for c in s:
        if c == '\t':
            col = ((col // TAB_W) + 1) * TAB_W
        else:
            col += 1
    return col


def next_tab_stop(col):
    """Return the next tab stop strictly after col."""
    return ((col // TAB_W) + 1) * TAB_W


def tabs_to_col(from_col, target_col):
    """Return tab characters needed to go from from_col to target_col."""
    n = 0
    col = from_col
    while col < target_col:
        col = next_tab_stop(col)
        n += 1
    return '\t' * max(n, 1)


def parse_var_decl(line):
    """Try to parse a variable declaration from a line.

    Returns (indent, type_text, var_text) or None.
    - indent: leading tab characters
    - type_text: the type part (e.g. 'unsigned int', 'const char')
    - var_text: everything after (e.g. '*ptr;', 'x;', 'arr[10];')
    """
    # Must start with tab indentation
    m = re.match(r'^(\t+)(.+)$', line)
    if not m:
        return None
    indent = m.group(1)
    body = m.group(2).rstrip()

    # Must end with ;
    if not body.endswith(';'):
        return None

    # Tokenize on whitespace (tabs or spaces)
    tokens = body.split()
    if len(tokens) < 2:
        return None

    # First token must be a type word
    if not is_type_word(tokens[0]):
        return None

    # Reject control flow keywords
    if tokens[0] in ('return', 'if', 'else', 'while', 'break', 'continue'):
        return None

    # Consume consecutive type words
    type_parts = []
    i = 0
    while i < len(tokens) and is_type_word(tokens[i]):
        type_parts.append(tokens[i])
        i += 1

    if i >= len(tokens):
        return None

    type_text = ' '.join(type_parts)
    var_text = ' '.join(tokens[i:])

    # Variable part must start with *, (, letter, or underscore
    if not re.match(r'^[(*_a-zA-Z]', var_text):
        return None

    # Extract just the variable name part (before any = assignment)
    var_name_part = var_text.split('=')[0].strip().rstrip(';').strip()

    # Reject function calls / prototypes (contain '(' in the name part)
    if '(' in var_name_part and not var_name_part.startswith('(*'):
        return None

    return (indent, type_text, var_text)


def align_group(group):
    """Given a list of (indent, type_text, var_text) tuples,
    return new lines with all variable names aligned to the same tab stop."""
    if not group:
        return []

    # Find the max visual column where type text ends
    max_type_end = 0
    for indent, type_text, _ in group:
        col = visual_col(indent + type_text)
        if col > max_type_end:
            max_type_end = col

    # Target column: next tab stop after the longest type
    target = next_tab_stop(max_type_end)

    # Rebuild each line
    result = []
    for indent, type_text, var_text in group:
        type_end = visual_col(indent + type_text)
        tabs = tabs_to_col(type_end, target)
        result.append(indent + type_text + tabs + var_text)
    return result


def fix_file(filepath):
    """Fix variable declaration alignment in a file. Returns True if changed."""
    with open(filepath, 'r') as f:
        lines = f.read().split('\n')

    result = []
    i = 0
    changed = False

    while i < len(lines):
        parsed = parse_var_decl(lines[i])
        if parsed:
            # Start collecting a group of consecutive declarations
            group = [parsed]
            originals = [lines[i]]
            j = i + 1
            while j < len(lines):
                p = parse_var_decl(lines[j])
                if p:
                    group.append(p)
                    originals.append(lines[j])
                    j += 1
                else:
                    break

            # Align the group
            aligned = align_group(group)
            for k, new_line in enumerate(aligned):
                if new_line != originals[k]:
                    changed = True
            result.extend(aligned)
            i = j
        else:
            result.append(lines[i])
            i += 1

    if changed:
        with open(filepath, 'w') as f:
            f.write('\n'.join(result))
    return changed


def main():
    files = [a for a in sys.argv[1:] if not a.startswith('-')]
    if not files:
        files = sorted(glob.glob('*.c') + glob.glob('*.h'))

    modified = 0
    for f in files:
        if not os.path.isfile(f):
            continue
        if fix_file(f):
            modified += 1
            print(f"Aligned: {f}")

    print(f"\nFixed alignment in {modified}/{len(files)} files")


if __name__ == '__main__':
    main()
