#!/usr/bin/env python3
"""Unit tests for strip_comments.py -- run: python3 strip_comments_test.py

Every case here is a place a naive regex stripper gets it wrong.
"""

import unittest

import strip_comments as sc


class Args(object):
    def __init__(self, **kw):
        self.comments = kw.get("comments", True)
        self.keep_header = kw.get("keep_header", False)
        self.keep_todo = kw.get("keep_todo", False)


def strip(src, lang_name, **kw):
    return sc.transform(src, sc.LANGS[lang_name], Args(**kw))


class C(unittest.TestCase):
    def test_line_and_block(self):
        self.assertEqual(strip("int a; // note\nint b; /* x */\n", "c"),
                         "int a;\nint b;\n")

    def test_slashes_in_string_survive(self):
        src = 'const char *u = "http://x";  // real comment\n'
        self.assertEqual(strip(src, "c"), 'const char *u = "http://x";\n')

    def test_block_delim_in_string(self):
        src = 'const char *p = "/* not a comment */";\n'
        self.assertEqual(strip(src, "c"), src)

    def test_char_literal_slash(self):
        src = "char c = '/';\nint x; // gone\n"
        self.assertEqual(strip(src, "c"), "char c = '/';\nint x;\n")

    def test_keeps_namespace_marker(self):
        src = "}  // namespace foo\nint x; // gone\n"
        self.assertEqual(strip(src, "cpp"), "}  // namespace foo\nint x;\n")

    def test_keeps_pattern_annotation(self):
        src = "if (a) //< a=1, state=CODE\n    return;\n"
        self.assertEqual(strip(src, "cpp"), src)

    def test_unterminated_block_raises(self):
        with self.assertRaises(ValueError):
            strip("int a; /* oops\n", "c")

    def test_inline_between_code_keeps_a_space(self):
        self.assertEqual(strip("int a;/*x*/int b;\n", "c"), "int a; int b;\n")


class JS(unittest.TestCase):
    def test_regex_with_slashes(self):
        src = "var re = /https:\\/\\//g;  // strip me\nx();\n"
        self.assertEqual(strip(src, "js"), "var re = /https:\\/\\//g;\nx();\n")

    def test_division_is_not_regex(self):
        src = "var y = a / b / c; // gone\n"
        self.assertEqual(strip(src, "js"), "var y = a / b / c;\n")

    def test_template_literal_multiline_protected(self):
        src = "const t = `line1\n   line2   \n`; // c\n"
        self.assertEqual(strip(src, "js"),
                         "const t = `line1\n   line2   \n`;\n")

    def test_url_in_string(self):
        self.assertEqual(strip('a("//x");  // c\n', "js"), 'a("//x");\n')


class Shell(unittest.TestCase):
    def test_shebang_kept(self):
        src = "#!/bin/sh\n# a comment\necho hi   # trailing\n"
        self.assertEqual(strip(src, "shell"), "#!/bin/sh\necho hi\n")

    def test_hash_in_double_string(self):
        self.assertEqual(strip('echo "value #1"\n', "shell"),
                         'echo "value #1"\n')

    def test_hash_after_dollar_brace(self):
        self.assertEqual(strip('n=${#arr[@]}  # count\n', "shell"),
                         'n=${#arr[@]}\n')

    def test_hash_glued_to_word_is_literal(self):
        self.assertEqual(strip("x=a#b\n", "shell"), "x=a#b\n")

    def test_heredoc_body_untouched(self):
        src = ("cat <<EOF\n"
               "# this is data, not a comment\n"
               "  indented   \n"
               "EOF\n"
               "echo done  # gone\n")
        expect = ("cat <<EOF\n"
                  "# this is data, not a comment\n"
                  "  indented   \n"
                  "EOF\n"
                  "echo done\n")
        self.assertEqual(strip(src, "shell"), expect)

    def test_quoted_heredoc(self):
        src = "cat <<'END'\n#keep $x\nEND\n# drop\n"
        self.assertEqual(strip(src, "shell"), "cat <<'END'\n#keep $x\nEND\n")

    def test_ansi_c_quote(self):
        self.assertEqual(strip("p=$'a\\'b'  # c\n", "shell"), "p=$'a\\'b'\n")


class Python(unittest.TestCase):
    def test_hash_comment(self):
        self.assertEqual(strip("x = 1  # c\n", "python"), "x = 1\n")

    def test_floor_division_not_comment(self):
        self.assertEqual(strip("x = 7 // 2  # c\n", "python"), "x = 7 // 2\n")

    def test_hash_in_string(self):
        self.assertEqual(strip('s = "a # b"  # c\n', "python"), 's = "a # b"\n')

    def test_docstring_kept(self):
        src = 'def f():\n    """doc # not a comment"""\n    return 1  # c\n'
        self.assertEqual(
            strip(src, "python"),
            'def f():\n    """doc # not a comment"""\n    return 1\n')

    def test_fstring_with_hash(self):
        self.assertEqual(strip('v = f"{x}#tag"  # c\n', "python"),
                         'v = f"{x}#tag"\n')

    def test_raw_string(self):
        self.assertEqual(strip('p = r"a\\#b"  # c\n', "python"), 'p = r"a\\#b"\n')


class Css(unittest.TestCase):
    def test_block_only(self):
        self.assertEqual(strip("a{color:red} /* c */\n", "css"),
                         "a{color:red}\n")

    def test_double_slash_is_not_a_comment(self):
        src = "a{background:url(//cdn/x.png)}\n"
        self.assertEqual(strip(src, "css"), src)

    def test_scss_line_comment(self):
        self.assertEqual(strip("$x: 1; // c\n", "scss"), "$x: 1;\n")


class Yaml(unittest.TestCase):
    def test_needs_space_before_hash(self):
        self.assertEqual(strip("url: http://h/p#frag\n", "yaml"),
                         "url: http://h/p#frag\n")

    def test_trailing_comment(self):
        self.assertEqual(strip("key: value   # c\n", "yaml"), "key: value\n")

    def test_hash_in_quotes(self):
        self.assertEqual(strip('key: "a # b"  # c\n', "yaml"), 'key: "a # b"\n')

    def test_full_line_comment_removed(self):
        self.assertEqual(strip("# header\nkey: v\n", "yaml"), "key: v\n")


class Ini(unittest.TestCase):
    def test_sol_markers(self):
        src = "; a\n# b\n[sec]\nk = v ; not a comment\n"
        self.assertEqual(strip(src, "ini"), "[sec]\nk = v ; not a comment\n")

    def test_conf_hash_after_space(self):
        self.assertEqual(strip("listen 80;  # http\n", "conf"), "listen 80;\n")


class Html(unittest.TestCase):
    def test_comment(self):
        self.assertEqual(strip("<p>x</p><!-- c -->\n", "html"), "<p>x</p>\n")

    def test_script_inner_js(self):
        src = "<script>\nvar a = 1; // c\n</script>\n"
        self.assertEqual(strip(src, "html"),
                         "<script>\nvar a = 1;\n</script>\n")

    def test_style_inner_css(self):
        src = "<style>\na{color:red} /* c */\n</style>\n"
        self.assertEqual(strip(src, "html"),
                         "<style>\na{color:red}\n</style>\n")

    def test_json_script_left_opaque(self):
        src = '<script type="application/json">\n{"a": 1}\n</script>\n'
        self.assertEqual(strip(src, "html"), src)


class Php(unittest.TestCase):
    def test_all_three_comment_styles(self):
        src = "<?php\n$a = 1; // one\n$b = 2; # two\n/* three */\necho $a;\n?>\n"
        self.assertEqual(strip(src, "php"),
                         "<?php\n$a = 1;\n$b = 2;\necho $a;\n?>\n")

    def test_html_around_php(self):
        src = "<!-- html c -->\n<?php echo 1; // c ?>\n"
        self.assertEqual(strip(src, "php"), "<?php echo 1; ?>\n")

    def test_attribute_hash_kept(self):
        src = "<?php\n#[Route('/x')]\nfunction f() {}\n"
        self.assertEqual(strip(src, "php"),
                         "<?php\n#[Route('/x')]\nfunction f() {}\n")

    def test_heredoc_kept(self):
        src = "<?php\n$x = <<<SQL\n# not a comment\nSELECT 1\nSQL;\n// c\n"
        self.assertEqual(
            strip(src, "php"),
            "<?php\n$x = <<<SQL\n# not a comment\nSELECT 1\nSQL;\n")


class Sql(unittest.TestCase):
    def test_dash_dash_and_block(self):
        self.assertEqual(strip("SELECT 1; -- c\n/* b */\nSELECT 2;\n", "sql"),
                         "SELECT 1;\nSELECT 2;\n")

    def test_doubled_quote_escape(self):
        src = "SELECT 'it''s -- fine';  -- c\n"
        self.assertEqual(strip(src, "sql"), "SELECT 'it''s -- fine';\n")


class Ruby(unittest.TestCase):
    def test_begin_end_block(self):
        src = "a = 1\n=begin\nblock note\n=end\nb = 2  # c\n"
        self.assertEqual(strip(src, "ruby"), "a = 1\nb = 2\n")

    def test_end_marker_cuts_file(self):
        self.assertEqual(strip("puts 1\n__END__\nrandom # data\n", "ruby"),
                         "puts 1\n")


class Rust(unittest.TestCase):
    def test_nested_block(self):
        self.assertEqual(strip("let a = 1; /* x /* y */ z */\n", "rust"),
                         "let a = 1;\n")

    def test_lifetime_not_a_string(self):
        src = "fn f<'a>(x: &'a str) -> &'a str { x } // c\n"
        self.assertEqual(strip(src, "rust"),
                         "fn f<'a>(x: &'a str) -> &'a str { x }\n")

    def test_raw_string(self):
        self.assertEqual(strip('let s = r#"a // b"#; // c\n', "rust"),
                         'let s = r#"a // b"#;\n')


class Makefile(unittest.TestCase):
    def test_comment_removed_escaped_hash_kept(self):
        src = "all:\n\techo \\#not-a-comment  # gone\n"
        self.assertEqual(strip(src, "makefile"),
                         "all:\n\techo \\#not-a-comment\n")

    def test_tab_indent_preserved(self):
        src = "t:\n\tcmd\n# c\n"
        self.assertEqual(strip(src, "makefile"), "t:\n\tcmd\n")


class Whitespace(unittest.TestCase):
    def test_collapses_blank_runs_and_trailing_ws(self):
        src = "a();   \n\n\n\nb();\n"
        self.assertEqual(strip(src, "c"), "a();\n\nb();\n")

    def test_trims_leading_and_trailing_blanks(self):
        src = "\n\n// top\nint x;\n\n\n"
        self.assertEqual(strip(src, "c"), "int x;\n")

    def test_no_comments_mode_keeps_comments(self):
        src = "int x;   // keep me\n\n\n"
        self.assertEqual(strip(src, "c", comments=False),
                         "int x;   // keep me\n")

    def test_brace_blank_pruning(self):
        src = "void f() {\n\n    int x;\n\n}\n"
        self.assertEqual(strip(src, "c"), "void f() {\n    int x;\n}\n")


class Keep(unittest.TestCase):
    def test_keep_header(self):
        src = "/* Licence line */\n#include <x>\nint a; // gone\n"
        self.assertEqual(strip(src, "c", keep_header=True),
                         "/* Licence line */\n#include <x>\nint a;\n")

    def test_keep_todo(self):
        src = "int a; // TODO: later\nint b; // gone\n"
        self.assertEqual(strip(src, "c", keep_todo=True),
                         "int a; // TODO: later\nint b;\n")

    def test_modeline_kept(self):
        src = "# -*- coding: utf-8 -*-\nx = 1  # gone\n"
        self.assertEqual(strip(src, "python"),
                         "# -*- coding: utf-8 -*-\nx = 1\n")


class Dispatch(unittest.TestCase):
    def test_lang_for_by_extension(self):
        self.assertIs(sc.lang_for("a/b/c.py", {}, False), sc.LANGS["python"])

    def test_lang_for_by_filename(self):
        self.assertIs(sc.lang_for("x/Dockerfile", {}, False),
                      sc.LANGS["dockerfile"])

    def test_makefile_opt_in(self):
        self.assertIsNone(sc.lang_for("Makefile", {}, False))
        self.assertIs(sc.lang_for("Makefile", {}, True), sc.LANGS["makefile"])

    def test_unknown_skipped(self):
        self.assertIsNone(sc.lang_for("notes.md", {}, False))

    def test_shebang_fallback(self):
        import os
        import tempfile
        d = tempfile.mkdtemp()
        p = os.path.join(d, "runme")
        with open(p, "w") as fh:
            fh.write("#!/usr/bin/env python3\nprint(1)\n")
        self.assertIs(sc.lang_for(p, {}, False), sc.LANGS["python"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
