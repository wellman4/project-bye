package main

import "core:os"
import "core:flags"

Options :: struct {
	file_path:    string `args:"pos=0" usage:"Path to the file to open"`,
	row:          int `usage:"Go to specific line after opening"`,
	col:          int `usage:"Go to specific column after opening"`,
	ro:           bool `usage:"Open the file in read-only mode"`,
	ln:           bool `usage:"Show line numbers on the left side of the window"`,
	ln_hmargin:   [dynamic]f32 `args:"manifold=2" usage:"Horizontal margin for line numbers"`,
	indent:       Indent_Style `usage:"Indentation style (Spaces or Tabs)"`,
	tab_size:     u8 `usage:"Number of spaces in one tab"`,	
	font_size:    f32 `usage:"Font size in points"`,
	theme:        Theme `usage:"Editor color theme"`,
	cursor_width: f32 `usage:"Cursor width in pixels"`,
	cursor_blink: bool `usage:"Enable cursor blinking"`,
	scrolloff:    [dynamic]u8 `args:"manifold=2" usage:"Cursor padding from window edges before scrolling"`
}

Indent_Style :: enum {
	Spaces,
	Tabs,
}

opts_init :: proc(opts: ^Options) -> bool {
	opts^ = {
		ln = true,
		indent = .Spaces,
		tab_size = 4,
		row = 1,
		col = 1,
		cursor_blink = true,
		cursor_width = 2,
		font_size = 15,
		theme = Theme.Dark,
	}

	parsing_style := flags.Parsing_Style.Unix

	#partial switch e in flags.parse(opts, os.args[1:], parsing_style) {
	case nil:
	case flags.Help_Request:
		flags.write_usage(os.to_stream(os.stdout), Options, os.args[0], parsing_style)
		return false
	case:
		flags.print_errors(Options, e, os.args[0], parsing_style)
		return false
	}

	if opts.ln_hmargin == nil {
		append(&opts.ln_hmargin, 6.0, 16.0)
	}

	if opts.scrolloff == nil {
		append(&opts.scrolloff, 5, 5)
	}

	return true
}

opts_destroy :: proc(opts: ^Options) {
	delete(opts.ln_hmargin)
	delete(opts.scrolloff)
}
