#!/usr/bin/env python3
"""
norm_preproc.py - Fix PREPROC_BAD_INDENT and TOO_MANY_WS on preprocessor lines.

Norminette requires preprocessor directives inside #ifndef/#ifdef/#if blocks
to have spaces between '#' and the keyword, based on nesting depth:
  Level 0: #ifndef GUARD_H           (guard itself, no space)
  Level 1: # define GUARD_H          (inside guard, 1 space)
  Level 1: # include "foo.h"         (inside guard, 1 space)
  Level 1: # ifdef FOO               (nested conditional)
  Level 2: #  define BAR             (inside nested block, 2 spaces)
  Level 1: # endif                   (closes nested block)
  Level 0: #endif                    (closes guard)

Also fixes:
  - Windows line endings (\\r\\n -> \\n)
  - TOO_MANY_WS: extra whitespace on preprocessor lines

Usage: python3 norm_preproc.py [files...]  (default: all *.c *.h)
"""

import re
import sys
import os
import glob


def fix_preproc_indent(filepath):
    """Fix preprocessor indentation based on nesting depth."""
    with open(filepath, 'rb') as f:
        raw = f.read()

    # Fix Windows line endings
    had_crlf = b'\r\n' in raw
    content = raw.decode('utf-8', errors='replace')
    content = content.replace('\r\n', '\n').replace('\r', '\n')

    lines = content.split('\n')
    result = []
    depth = 0
    changed = False

    for line in lines:
        stripped = line.strip()

        # Only process preprocessor directives
        m = re.match(r'^#\s*(\w+)(.*)', stripped)
        if not m:
            result.append(line)
            continue

        directive = m.group(1)
        rest = m.group(2)

        # Normalize spacing: collapse multiple spaces after directive to one
        if rest:
            rest = ' ' + rest.lstrip()

        # Determine the correct depth for this directive
        if directive in ('endif',):
            # #endif closes a block -> print at depth-1, then decrement
            depth = max(0, depth - 1)
            print_depth = depth
        elif directive in ('else', 'elif'):
            # #else/#elif at same level as matching #if
            print_depth = max(0, depth - 1)
        elif directive in ('ifndef', 'ifdef', 'if'):
            # Conditional opens a block -> print at current depth, then inc
            print_depth = depth
            depth += 1
        else:
            # #define, #include, #undef, #pragma, #error, #warning
            print_depth = depth

        # Build the correctly indented line
        if print_depth == 0:
            new_line = '#' + directive + rest
        else:
            new_line = '#' + (' ' * print_depth) + directive + rest

        if new_line != line:
            changed = True

        result.append(new_line)

    final = '\n'.join(result)
    # Ensure single trailing newline
    final = final.rstrip('\n') + '\n'

    if changed or had_crlf:
        with open(filepath, 'w', newline='\n') as f:
            f.write(final)
        return True
    return False


def main():
    files = [a for a in sys.argv[1:] if not a.startswith('-')]
    if not files:
        files = sorted(glob.glob('*.c') + glob.glob('*.h'))

    modified = 0
    for f in files:
        if not os.path.isfile(f):
            continue
        if fix_preproc_indent(f):
            modified += 1
            print(f"Fixed: {f}")

    print(f"\nFixed preprocessor indent in {modified}/{len(files)} files")


if __name__ == '__main__':
    main()
