#!/usr/bin/env -S python3
import sys, os, subprocess, shutil
from typing import List, Tuple
import difflib

# ANSI color codes
class Colors:
    RESET = '\033[0m'
    BOLD = '\033[1m'
    DIM = '\033[2m'
    
    # Colors
    RED = '\033[91m'
    GREEN = '\033[92m'
    YELLOW = '\033[93m'
    BLUE = '\033[94m'
    MAGENTA = '\033[95m'
    CYAN = '\033[96m'
    WHITE = '\033[97m'
    GRAY = '\033[90m'
    
    @staticmethod
    def disable():
        """Disable colors for non-TTY environments"""
        for attr in dir(Colors):
            if not attr.startswith('_') and attr.isupper() and attr not in ['disable']:
                setattr(Colors, attr, '')

# Disable colors if not outputting to a terminal
if not sys.stdout.isatty():
    Colors.disable()

# Modern Unicode icons
ICON_SUCCESS = f"{Colors.GREEN}●{Colors.RESET}"
ICON_ERROR = f"{Colors.RED}●{Colors.RESET}"
ICON_WARNING = f"{Colors.YELLOW}●{Colors.RESET}"
ICON_SKIP = f"{Colors.GRAY}○{Colors.RESET}"
ICON_SCAN = f"{Colors.CYAN}⊙{Colors.RESET}"

# Parse command line arguments
args = sys.argv[1:]
if '--' in args:
    idx = args.index('--')
    ROOTS = args[:idx] or ['.']
    EXTRA_FLAGS = args[idx+1:]
else:
    ROOTS = args or ['.']
    EXTRA_FLAGS = []

def which(name):
    return shutil.which(name)

def run(cmd):
    p = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    return p.returncode, p.stdout + p.stderr

def print_header():
    """Print a minimal, modern header"""
    print(f"\n{Colors.BOLD}{Colors.CYAN}C/C++ Code Quality{Colors.RESET} {Colors.DIM}({len(find_sources(ROOTS))} files){Colors.RESET}")

def print_section(tool_name: str):
    """Print a clean section header for each tool"""
    # Pad tool name to align results
    padded = f"{tool_name:<15}"
    print(f"  {Colors.DIM}{padded}{Colors.RESET}", end=" ")

def print_success():
    """Print inline success indicator"""
    print(f"{ICON_SUCCESS}")

def print_error(count: int):
    """Print inline error indicator with count"""
    print(f"{ICON_ERROR} {Colors.RED}{count} issue{'s' if count != 1 else ''}{Colors.RESET}")

def print_skip():
    """Print inline skip indicator"""
    print(f"{ICON_SKIP} {Colors.DIM}skipped{Colors.RESET}")

def print_file_issue(filename: str, details: str):
    """Print file-specific issues with minimal formatting"""
    print(f"\n  {Colors.DIM}├─{Colors.RESET} {Colors.WHITE}{filename}{Colors.RESET}")
    for line in details.split('\n'):
        if line.strip():
            print(f"  {Colors.DIM}│{Colors.RESET}  {Colors.DIM}{line}{Colors.RESET}")
    print(f"  {Colors.DIM}╰─{Colors.RESET}")

def print_summary(total_checks: int, passed: int, failed: int, skipped: int):
    """Print a compact summary"""
    status = f"{Colors.GREEN}{passed}{Colors.RESET}"
    if failed > 0:
        status += f" {Colors.DIM}/{Colors.RESET} {Colors.RED}{failed}{Colors.RESET}"
    if skipped > 0:
        status += f" {Colors.DIM}/{Colors.RESET} {Colors.GRAY}{skipped}{Colors.RESET}"
    print(f"{status} {Colors.DIM}passed/failed/skipped{Colors.RESET}\n")

def find_sources(roots: List[str]) -> List[str]:
    """Find C/C++ source files in the given roots"""
    exts = ('.c', '.cpp', '.cc', '.cxx', '.h', '.hpp', '.hh')
    files = []
    for root in roots:
        if os.path.isfile(root):
            if root.lower().endswith(exts):
                files.append(root)
            continue
        for dp, _, fnames in os.walk(root):
            for f in fnames:
                if f.lower().endswith(exts):
                    files.append(os.path.join(dp, f))
    return files

def check_clang_format(files: List[str]) -> Tuple[int, int]:
    """Check code formatting with clang-format"""
    print_section("clang-format")
    
    if not which('clang-format'):
        print_skip()
        return 0, 1
    
    issues = []
    for f in files:
        rc, out = run(['clang-format', '--output-replacements-xml', f])
        if '<replacement ' in out:
            issues.append(f)
    
    if issues:
        print_error(len(issues))
        for f in issues:
            # produce a unified diff between original and clang-format output
            try:
                with open(f, 'r', encoding='utf-8', errors='replace') as fh:
                    original = fh.read().splitlines()
            except Exception as e:
                print_file_issue(f, f"Could not read file: {e}")
                continue
            rc2, formatted = run(['clang-format', f])
            formatted_lines = formatted.splitlines()
            diff_lines = list(difflib.unified_diff(original, formatted_lines,
                                                   fromfile=f,
                                                   tofile=f + " (formatted)",
                                                   lineterm=''))
            if diff_lines:
                print_file_issue(f, "\n".join(diff_lines[:20]))  # Limit diff output
        return 1, 0
    
    print_success()
    return 0, 0

def check_clang_tidy(files: List[str]) -> Tuple[int, int]:
    """Check code with clang-tidy"""
    print_section("clang-tidy")
    
    if not which('clang-tidy'):
        print_skip()
        return 0, 1
    
    msgs = []
    flags = ['--'] + EXTRA_FLAGS if EXTRA_FLAGS else []
    
    for f in files:
        rc, out = run(['clang-tidy', f] + flags)
        if rc != 0 or out.strip():
            msgs.append((f, out.strip()))
    
    if msgs:
        print_error(len(msgs))
        for f, details in msgs:
            # Truncate long outputs
            lines = details.split('\n')
            truncated = '\n'.join(lines[:15])
            if len(lines) > 15:
                truncated += f"\n... ({len(lines) - 15} more lines)"
            print_file_issue(f, truncated)
        return 1, 0
    
    print_success()
    return 0, 0

def check_cppcheck(roots: List[str]) -> Tuple[int, int]:
    """Check code with cppcheck"""
    print_section("cppcheck")
    
    if not which('cppcheck'):
        print_skip()
        return 0, 1
    
    cmd = ['cppcheck', '--enable=all', '--quiet'] + roots
    rc, out = run(cmd)
    
    if rc != 0:
        print_error(1)
        print_file_issue("cppcheck", out.strip())
        return 1, 0
    
    print_success()
    return 0, 0

def check_cpplint(files: List[str]) -> Tuple[int, int]:
    """Check code style with cpplint"""
    print_section("cpplint")
    
    if not which('cpplint'):
        print_skip()
        return 0, 1
    
    msgs = []
    for f in files:
        rc, out = run(['cpplint', '--filter=-legal/copyright', f])
        filtered_lines = [
            line for line in out.splitlines()
            if line.strip() and not line.strip().startswith('Done processing')
        ]
        filtered = "\n".join(filtered_lines).strip()
        if rc != 0 or filtered:
            msgs.append((f, filtered if filtered else out.strip()))
    
    if msgs:
        print_error(len(msgs))
        for f, details in msgs:
            print_file_issue(f, details)
        return 1, 0
    
    print_success()
    return 0, 0

def main():
    # Find source files
    files = find_sources(ROOTS)
    
    if not files:
        print(f"\n{ICON_ERROR} {Colors.RED}No C/C++ source files found{Colors.RESET}\n")
        return 1
    
    print_header()
    
    # Run all checks
    checks = [
        (check_clang_format, files),
        (check_clang_tidy, files),
        (check_cppcheck, ROOTS),
        (check_cpplint, files),
    ]
    
    failed = 0
    passed = 0
    skipped = 0
    
    for check_func, check_arg in checks:
        rc, skip = check_func(check_arg)
        if skip:
            skipped += 1
        elif rc == 0:
            passed += 1
        else:
            failed += 1
    
    # Print summary
    print()
    total = len(checks)
    print_summary(total, passed, failed, skipped)
    
    return 1 if failed > 0 else 0

if __name__ == "__main__":
    sys.exit(main())