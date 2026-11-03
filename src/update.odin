package main

import "core:fmt"
import "core:strings"
import "core:unicode/utf8"

import "vendor:sdl3"
import "vendor:sdl3/ttf"

import "../tb"

update :: proc(app_ctx: ^App_Context, dt: f64) {
	if app_ctx.text_view.is_dirty {
		update_text_view(app_ctx)
		app_ctx.text_view.is_dirty = false
	}
	
	if app_ctx.opts.cursor_blink {
		app_ctx.cursor_timer += dt
		if app_ctx.cursor_timer >= 0.5 {
			app_ctx.cursor_timer = 0
			app_ctx.cursor_visible = !app_ctx.cursor_visible
		}
	}
}

update_text_view :: proc(app_ctx: ^App_Context) {
	for &vl in app_ctx.text_view.visible_lines {
		if vl.num_text_obj != nil do ttf.DestroyText(vl.num_text_obj)
		if vl.text_obj != nil     do ttf.DestroyText(vl.text_obj)
	}
	clear(&app_ctx.text_view.visible_lines)

	start_line_idx    := int(app_ctx.text_view.scroll.y / app_ctx.text_view.line_height)
	display_lines     := int(app_ctx.text_view.rect.h / app_ctx.text_view.line_height) + 1
	total_lines_count := tb.gap_buffer_get_line_count(&app_ctx.buffer)

	for i in 0..<display_lines {
		line_idx := start_line_idx + i
		if line_idx >= total_lines_count do break

		line_str, _ := tb.gap_buffer_get_line(&app_ctx.buffer, line_idx)
		
		x_pos := app_ctx.text_view.rect.x + app_ctx.text_view.gutter_width - app_ctx.text_view.scroll.x
		y_pos := app_ctx.text_view.rect.y + f32(line_idx) * app_ctx.text_view.line_height - app_ctx.text_view.scroll.y

		vl: Visible_Line
		vl.line_idx = line_idx
		vl.y_pos = y_pos

		if app_ctx.opts.ln {
			num_str := fmt.tprintf("%d", line_idx + 1)
			num_c_str := strings.clone_to_cstring(num_str, context.temp_allocator)
			vl.num_text_obj = ttf.CreateText(app_ctx.text_engine, app_ctx.font, num_c_str, 0)
			if vl.num_text_obj != nil {
				ttf.SetTextColor(vl.num_text_obj, app_ctx.colors.line_numbers_text.r, app_ctx.colors.line_numbers_text.g, app_ctx.colors.line_numbers_text.b, app_ctx.colors.line_numbers_text.a)
			}
		}

		line_start := app_ctx.buffer.line_offsets[line_idx]
		line_len   := len(line_str)
		line_end   := line_start + line_len
		sel_start, sel_end := tb.get_selection_range(&app_ctx.text_view.cursor)

		if tb.is_selection(&app_ctx.text_view.cursor) && !(line_end <= sel_start || line_start >= sel_end) {
			g_start := max(line_start, sel_start)
			g_end   := min(line_end, sel_end)

			local_start_bytes := g_start - line_start
			local_end_bytes   := g_end - line_start

			runes_before := utf8.rune_count(line_str[0:local_start_bytes])
			runes_inside := utf8.rune_count(line_str[local_start_bytes:local_end_bytes])

			rect_x := x_pos + f32(runes_before) * app_ctx.text_view.char_width
			rect_w := f32(runes_inside) * app_ctx.text_view.char_width

			if sel_end > line_end do rect_w += app_ctx.text_view.char_width 

			if rect_w > 0 {
				vl.has_selection = true
				vl.sel_rect = sdl3.FRect{x = rect_x, y = y_pos, w = rect_w, h = app_ctx.text_view.line_height}
			}
		}

		if len(line_str) > 0 {
			c_str := strings.clone_to_cstring(line_str, context.temp_allocator)
			vl.text_obj = ttf.CreateText(app_ctx.text_engine, app_ctx.font, c_str, 0)
			if vl.text_obj != nil {
				ttf.SetTextColor(vl.text_obj, app_ctx.colors.text.r, app_ctx.colors.text.g, app_ctx.colors.text.b, app_ctx.colors.text.a)
			}
		}

		append(&app_ctx.text_view.visible_lines, vl)
	}

	cx := app_ctx.text_view.rect.x + app_ctx.text_view.gutter_width + f32(app_ctx.text_view.cursor.col) * app_ctx.text_view.char_width - app_ctx.text_view.scroll.x
	cy := app_ctx.text_view.rect.y + f32(app_ctx.text_view.cursor.line) * app_ctx.text_view.line_height - app_ctx.text_view.scroll.y
	
	app_ctx.text_view.cursor_rect = sdl3.FRect{
		x = cx,
		y = cy,
		w = app_ctx.opts.cursor_width,
		h = app_ctx.text_view.line_height,
	}
}


update_status_bar_text :: proc(app_ctx: ^App_Context) {
	if app_ctx.status_bar.left_text != nil {
		ttf.DestroyText(app_ctx.status_bar.left_text)
		app_ctx.status_bar.left_text = nil
	}
	if app_ctx.status_bar.right_text != nil {
		ttf.DestroyText(app_ctx.status_bar.right_text)
		app_ctx.status_bar.right_text = nil
	}

	indent_str    := app_ctx.opts.indent == .Spaces ? "Spaces" : "Tabs"
	mod_indicator := app_ctx.is_modified ? "*" : ""
	eol_str       := app_ctx.buffer.end_of_line == .LF ? "LF" : "CRLF" 

	left_str := fmt.tprintf(" %s%s", app_ctx.opts.file_path, mod_indicator)
	c_left   := strings.clone_to_cstring(left_str, context.temp_allocator)
	
	app_ctx.status_bar.left_text = ttf.CreateText(app_ctx.text_engine, app_ctx.font, c_left, 0)
	if app_ctx.status_bar.left_text != nil {
		left_color := app_ctx.is_modified ? app_ctx.colors.modified_accent : app_ctx.colors.status_bar_text
		ttf.SetTextColor(
			app_ctx.status_bar.left_text, 
			left_color.r, left_color.g, left_color.b, left_color.a,
		)
	}

	right_str := fmt.tprintf(
		"Row %d, Col %d   %s: %d   UTF-8   %s ", 
		app_ctx.text_view.cursor.line + 1, 
		app_ctx.text_view.cursor.col + 1, 
		indent_str,
		app_ctx.opts.tab_size,
		eol_str,
	)
	c_right := strings.clone_to_cstring(right_str, context.temp_allocator)
	
	app_ctx.status_bar.right_text = ttf.CreateText(app_ctx.text_engine, app_ctx.font, c_right, 0)
	if app_ctx.status_bar.right_text != nil {
		ttf.SetTextColor(
			app_ctx.status_bar.right_text, 
			app_ctx.colors.status_bar_text.r, 
			app_ctx.colors.status_bar_text.g, 
			app_ctx.colors.status_bar_text.b, 
			app_ctx.colors.status_bar_text.a,
		)
	}
}
