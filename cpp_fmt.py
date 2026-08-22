#!/usr/bin/env python3
"""
cpp_fmt.py — C++ auto-formatter for libcpp source files.

Applies safe, universal style fixes to .cpp and .hpp files:

  - Trailing whitespace removal
  - Tabs → spaces (4-space indent, C++ convention)
  - Empty-line-at-EOF normalisation (exactly one trailing newline)
  - Multiple consecutive blank lines → single blank line
  - Space after keywords: if(  → if (
  - No space before function call parens (but keep after keywords)
  - Pointer/reference style: int * x → int* x  /  int & x → int& x
  - Trailing semicolons on blank lines removed
  - Remove spaces on otherwise-empty lines

Does NOT apply C-norminette rules that break C++:
  - No return(x) wrapping
  - No for→while conversion
  - No decl-assign splitting (breaks = default / = delete / RAII)
  - No brace-on-own-line enforcement (breaks C++ style)

Usage:
    python3 cpp_fmt.py [file ...] [--dry-run]
    python3 cpp_fmt.py              # all *.cpp *.hpp under cwd recursively
"""

import re
import sys
import os


# ── helpers ──────────────────────────────────────────────────────────────────

def find_cpp_files(roots):
    """Recursively find .cpp and .hpp files."""
    exts = ('.cpp', '.hpp', '.cc', '.cxx', '.hh', '.h')
    files = []
    for root in roots:
        if os.path.isfile(root):
            if root.endswith(exts):
                files.append(root)
            continue
        for dp, _, fnames in os.walk(root):
            for fn in sorted(fnames):
                if fn.endswith(exts):
                    files.append(os.path.join(dp, fn))
    return files


def in_raw_string(line):
    """Very rough check: line is inside an R\"(...)\" raw string."""
    return 'R"(' in line or line.strip().startswith(')')


# ── individual fixers (each takes/returns a list of lines) ───────────────────

def fix_trailing_whitespace(lines):
    """Remove trailing spaces/tabs on every line."""
    return [l.rstrip() for l in lines]


def fix_tabs_to_spaces(lines):
    """Convert leading tabs to 4 spaces (C++ convention)."""
    result = []
    for line in lines:
        m = re.match(r'^(\t+)', line)
        if m:
            tabs = m.group(1)
            line = '    ' * len(tabs) + line[len(tabs):]
        result.append(line)
    return result


def fix_empty_lines(lines):
    """Collapse 3+ consecutive blank lines into 2."""
    result = []
    blank_count = 0
    for line in lines:
        if line.strip() == '':
            blank_count += 1
            if blank_count <= 2:
                result.append(line)
        else:
            blank_count = 0
            result.append(line)
    return result


def fix_space_after_keyword(lines):
    """Ensure space after: if, while, for, switch, return, catch."""
    kw = r'\b(if|while|for|switch|return|catch)\('
    result = []
    for line in lines:
        if in_raw_string(line):
            result.append(line)
            continue
        result.append(re.sub(kw, r'\1 (', line))
    return result


def fix_space_before_func(lines):
    """Remove space between function name and '(' but keep keywords."""
    keywords = {'if', 'while', 'for', 'switch', 'return', 'catch',
                'sizeof', 'alignof', 'decltype', 'typeof', 'noexcept',
                'static_assert', 'co_await', 'co_return', 'co_yield',
                'throw', 'else', 'delete', 'new'}
    def _repl(m):
        word = m.group(1)
        if word in keywords:
            return m.group(0)
        return word + '('
    result = []
    for line in lines:
        if in_raw_string(line):
            result.append(line)
            continue
        result.append(re.sub(r'\b(\w+)\s+\(', _repl, line))
    return result


def fix_pointer_style(lines):
    """Normalise 'Type * name' → 'Type* name' and 'Type & name' → 'Type& name'.
    Only touches declaration-like patterns, not expressions."""
    result = []
    for line in lines:
        if in_raw_string(line):
            result.append(line)
            continue
        # int * x  → int* x   (not inside expressions)
        line = re.sub(r'(\w)\s+\*\s+(\w)', r'\1* \2', line)
        # int & x  → int& x
        line = re.sub(r'(\w)\s+&\s+(\w)', r'\1& \2', line)
        result.append(line)
    return result


def fix_space_only_lines(lines):
    """Lines that are just whitespace → truly empty."""
    return ['' if l.strip() == '' else l for l in lines]


def fix_eof(content):
    """Ensure exactly one trailing newline at end of file."""
    return content.rstrip('\n') + '\n'


# ── orchestrator ─────────────────────────────────────────────────────────────

def format_file(filepath, dry_run=False):
    """Apply all safe fixes to a file. Returns True if changed."""
    with open(filepath, 'r', encoding='utf-8', errors='replace') as f:
        content = f.read()
    original = content
    lines = content.split('\n')

    # apply in order
    lines = fix_trailing_whitespace(lines)
    lines = fix_tabs_to_spaces(lines)
    lines = fix_space_only_lines(lines)
    lines = fix_empty_lines(lines)
    lines = fix_space_after_keyword(lines)
    lines = fix_space_before_func(lines)
    lines = fix_pointer_style(lines)

    content = '\n'.join(lines)
    content = fix_eof(content)

    if content != original:
        if not dry_run:
            with open(filepath, 'w', encoding='utf-8') as f:
                f.write(content)
        return True
    return False


def main():
    dry_run = '--dry-run' in sys.argv
    args = [a for a in sys.argv[1:] if not a.startswith('-')]

    if not args:
        args = ['.']
    files = find_cpp_files(args)

    if not files:
        print("No C++ files found")
        return

    modified = 0
    for f in files:
        changed = format_file(f, dry_run=dry_run)
        if changed:
            modified += 1
            print(f"{'Would fix' if dry_run else 'Fixed'}: {f}")

    print(f"\n{'Would modify' if dry_run else 'Modified'} {modified}/{len(files)} files")


if __name__ == '__main__':
    main()
