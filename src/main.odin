package main

import "core:c"
import "core:fmt"
import "core:os"
import "core:strings"

import "vendor:sdl3"
import "vendor:sdl3/ttf"

import "../tb"

App_Context :: struct {
	opts:              Options,
	gfx:               Graphics_Context,
	
	font:              ^ttf.Font,
	text_engine:       ^ttf.TextEngine,

	buffer:            tb.Gap_Buffer,
	text_view:         Text_View,
	status_bar:        Status_Bar,
	cursor_timer:      f64,
	is_modified:       bool,
	cursor_visible:    bool,
	colors:	           Theme_Colors,
	// Frame rate control
	target_frame_time: u64,
	last_time:         u64,
}

Text_View :: struct {
	cursor:        tb.Cursor,
	cursor_rect:   sdl3.FRect,
	rect:          sdl3.FRect,
	scroll:        [2]f32,
	gutter_width:  f32,
	line_height:   f32,
	char_width:    f32,
	visible_lines: [dynamic]Visible_Line,
	is_dirty:      bool,
}

Visible_Line :: struct {
	line_idx:      int,
	y_pos:         f32,
	num_text_obj:  ^ttf.Text,
	text_obj:      ^ttf.Text,
	has_selection: bool,
	sel_rect:      sdl3.FRect,
}

Status_Bar :: struct {
	rect:       sdl3.FRect,
	height:     f32,
	left_text:  ^ttf.Text,
	right_text: ^ttf.Text,
}

Graphics_Context :: struct {
	window:   ^sdl3.Window,
	renderer: ^sdl3.Renderer,
}

main :: proc() {
	app_ctx := new(App_Context)
	defer free(app_ctx)

	defer app_quit(app_ctx)
	if !app_init(app_ctx) do return
	app_mainloop(app_ctx)
}

app_init :: proc (app_ctx: ^App_Context) -> bool {
	if !opts_init(&app_ctx.opts) do return false

	if !init_graphics(app_ctx) do return false
	if !init_typography(app_ctx) do return false

	app_ctx.colors = get_theme_colors(app_ctx.opts.theme)

	if len(app_ctx.opts.file_path) != 0 {
		data, err := os.read_entire_file(app_ctx.opts.file_path, context.allocator)
		if err == os.ERROR_NONE {
			tb.gap_buffer_init_from_bytes(&app_ctx.buffer, data, gap_len = 1024)
			delete(data)
		} else { // Titled
			tb.gap_buffer_init(&app_ctx.buffer, cap = 128, lines_cap = 64)
		}
	} else { // Untitled
		app_ctx.opts.file_path = "untitled"
		tb.gap_buffer_init(&app_ctx.buffer, cap = 128, lines_cap = 64)
	}

	window_width, window_height: i32
    sdl3.GetWindowSize(app_ctx.gfx.window, &window_width, &window_height)

	// Status bar
	app_ctx.status_bar.height = 22
	app_ctx.status_bar.rect = sdl3.FRect{
		x = 0.0,
		y = f32(window_height) - app_ctx.status_bar.height,
		w = f32(window_width),
		h = app_ctx.status_bar.height,
	}

	// Text view
	char_width, char_height: c.int
	if !ttf.GetStringSize(app_ctx.font, "!", 0, &char_width, &char_height) {
		return false
	}
	
	app_ctx.text_view.char_width  = f32(char_width)
	app_ctx.text_view.line_height = f32(char_height)

	app_ctx.text_view.rect = sdl3.FRect{
		x = 0.0,
		y = 0.0,
		w = f32(window_width),
		h = f32(window_height) - app_ctx.status_bar.height,
	}
	app_ctx.text_view.is_dirty = true
	update_gutter_width(app_ctx)

	if app_ctx.opts.row > 0 || app_ctx.opts.col > 0 {
		tb.gap_buffer_move_cursor_to(
			&app_ctx.buffer, 
			&app_ctx.text_view.cursor, 
			app_ctx.opts.row - 1,
			app_ctx.opts.col - 1,
			false,
		)
		update_scroll_to_cursor(app_ctx)
		update_status_bar_text(app_ctx)
	}

	_ = sdl3.StartTextInput(app_ctx.gfx.window)

	ibeam_cursor := sdl3.CreateSystemCursor(.TEXT)
	if ibeam_cursor != nil {
		_ = sdl3.SetCursor(ibeam_cursor)
	}

	app_ctx.cursor_visible = true

	app_ctx.target_frame_time = 1_000_000_000 / 60
	app_ctx.last_time = sdl3.GetTicksNS()

	return true
}

init_graphics :: proc(app_ctx: ^App_Context) -> bool {
	if !sdl3.Init({.VIDEO}) {
		fmt.eprintln("SDL3 Initialization Error:", sdl3.GetError())
		return false
	}

	window_title: cstring = strings.clone_to_cstring(
		fmt.tprintf("Bye: %s", app_ctx.opts.file_path),
		context.temp_allocator
	)

	if !sdl3.CreateWindowAndRenderer(
		window_title, 
		1080, 
		782, 
		{.RESIZABLE}, 
		&app_ctx.gfx.window, 
		&app_ctx.gfx.renderer,
	) {
		fmt.eprintln("Error! Failed to create window or renderer:", sdl3.GetError())
		return false
	}

	sdl3.SetWindowMinimumSize(app_ctx.gfx.window, 660, 0)
	sdl3.SetRenderVSync(app_ctx.gfx.renderer, 0)
    return true
}

init_typography :: proc(app_ctx: ^App_Context) -> bool {
	if !ttf.Init() {
		fmt.eprintln("SDL3_ttf Initialization Error:", sdl3.GetError())
		return false
	}
	app_ctx.font = ttf.OpenFont(
		"assets/fonts/Source_Code_Pro/SourceCodePro-Regular.ttf",
		app_ctx.opts.font_size
	)
	if app_ctx.font == nil {
		fmt.eprintln("Failed to load font:", sdl3.GetError())
		return false
	}

	app_ctx.text_engine = ttf.CreateRendererTextEngine(app_ctx.gfx.renderer)
	if app_ctx.text_engine == nil {
		fmt.eprintln("Failed to create renderer text engine:", sdl3.GetError())
		return false
	}

	return true
}

app_mainloop :: proc (app_ctx: ^App_Context) {
	for {
		frame_start_time := sdl3.GetTicksNS()
		dt := f64(frame_start_time - app_ctx.last_time) / 1_000_000_000.0
		app_ctx.last_time = frame_start_time 

		if !handle_events(app_ctx) do break

		update(app_ctx, dt)
		render(app_ctx)	

		free_all(context.temp_allocator)

		frame_time := sdl3.GetTicksNS() - frame_start_time
		if frame_time < app_ctx.target_frame_time {
			sdl3.DelayPrecise(app_ctx.target_frame_time - frame_time)
		}
	}
}

handle_events :: proc (app_ctx: ^App_Context) -> bool {
	event: sdl3.Event = ---
	for sdl3.PollEvent(&event) {
		#partial switch event.type {
		case .QUIT:
			return false
		case .WINDOW_RESIZED:
			new_width := f32(event.window.data1)
			new_height := f32(event.window.data2)

			app_ctx.status_bar.rect = {
				0.0,
				new_height - app_ctx.status_bar.height,
				new_width,
				app_ctx.status_bar.height
			}
			app_ctx.text_view.rect = {
				0.0,
				0.0,
				new_width,
				new_height - app_ctx.status_bar.height
			}
			app_ctx.text_view.is_dirty = true
		case .MOUSE_WHEEL:
			scroll_speed_y := app_ctx.text_view.line_height * 3.0
		
			if event.wheel.direction == .FLIPPED {
				app_ctx.text_view.scroll.y += event.wheel.y * scroll_speed_y
				app_ctx.text_view.scroll.x -= event.wheel.x * 20.0
			} else {
				app_ctx.text_view.scroll.y -= event.wheel.y * scroll_speed_y
				app_ctx.text_view.scroll.x += event.wheel.x * 20.0
			}

			clamp_scroll(app_ctx)
			app_ctx.text_view.is_dirty = true
		case .TEXT_INPUT:
			if app_ctx.opts.ro do return true

			if tb.is_selection(&app_ctx.text_view.cursor) {
				start, end := tb.get_selection_range(&app_ctx.text_view.cursor)
				tb.gap_buffer_delete_range(&app_ctx.buffer, &app_ctx.text_view.cursor, start, end)
			}

			input_text := string(event.text.text)
			tb.gap_buffer_insert_text(&app_ctx.buffer, &app_ctx.text_view.cursor, input_text)
		
			app_ctx.is_modified = true
			app_ctx.cursor_visible = true
			app_ctx.cursor_timer = 0
			update_scroll_to_cursor(app_ctx)
			update_status_bar_text(app_ctx)
			app_ctx.text_view.is_dirty = true
		case .KEY_DOWN:
			mod := sdl3.GetModState()
			shift_pressed := .LSHIFT in mod || .RSHIFT in mod
			ctrl_pressed := .LCTRL in mod || .RCTRL in mod

			#partial switch event.key.scancode {
			case .ESCAPE:
				return false
			case .S:
				if ctrl_pressed {
					if app_ctx.opts.ro do return true

					save_buffer_to_file(&app_ctx.buffer, app_ctx.opts.file_path)
					app_ctx.is_modified = false
					update_status_bar_text(app_ctx)
				}
			case .C:
				if ctrl_pressed && tb.is_selection(&app_ctx.text_view.cursor) {
					start, end := tb.get_selection_range(&app_ctx.text_view.cursor)

					text, _ := tb.gap_buffer_get_selection(&app_ctx.buffer, start, end)

					c_str := strings.clone_to_cstring(text, context.temp_allocator)
	
					if !sdl3.SetClipboardText(c_str) {
						fmt.eprintln("SDL3 Clipboard Error:", sdl3.GetError())
					}
				}
			case .X:
				if ctrl_pressed && tb.is_selection(&app_ctx.text_view.cursor) {
					start, end := tb.get_selection_range(&app_ctx.text_view.cursor)

					text, _ := tb.gap_buffer_get_selection(&app_ctx.buffer, start, end)

					c_str := strings.clone_to_cstring(text, context.temp_allocator)
	
					if !sdl3.SetClipboardText(c_str) {
						fmt.eprintln("SDL3 Clipboard Error:", sdl3.GetError())
					}

					tb.gap_buffer_delete_range(&app_ctx.buffer, &app_ctx.text_view.cursor, start, end)
					app_ctx.text_view.is_dirty = true
				}
			case .V:
				if ctrl_pressed {
					if app_ctx.opts.ro do return true

					if tb.is_selection(&app_ctx.text_view.cursor) {
						start, end := tb.get_selection_range(&app_ctx.text_view.cursor)
						tb.gap_buffer_delete_range(&app_ctx.buffer, &app_ctx.text_view.cursor, start, end)
					}

					clipboard_raw := sdl3.GetClipboardText()

					if clipboard_raw != nil {
						defer sdl3.free(clipboard_raw)

						c_str := cstring(rawptr(clipboard_raw))
						text_to_insert := string(c_str)

						if len(text_to_insert) > 0 {
							tb.gap_buffer_insert_text(&app_ctx.buffer, &app_ctx.text_view.cursor, text_to_insert)
							app_ctx.is_modified = true 
						}
					}
					update_scroll_to_cursor(app_ctx)
					update_gutter_width(app_ctx)
					update_status_bar_text(app_ctx)
					app_ctx.text_view.is_dirty = true
				}
			case .A:
				if ctrl_pressed {
					app_ctx.text_view.cursor.selection_anchor_pos = 0
					tb.gap_buffer_move_cursor_to(
						&app_ctx.buffer,
						&app_ctx.text_view.cursor,
						tb.gap_buffer_get_line_count(&app_ctx.buffer) - 1,
						max(int),
						true,
					)
					update_scroll_to_cursor(app_ctx)
					update_status_bar_text(app_ctx)
					app_ctx.text_view.is_dirty = true
				}
			case .BACKSPACE:
				if app_ctx.opts.ro do return true

				if tb.is_selection(&app_ctx.text_view.cursor) {
					start, end := tb.get_selection_range(&app_ctx.text_view.cursor)
					tb.gap_buffer_delete_range(&app_ctx.buffer, &app_ctx.text_view.cursor, start, end)
				} else {
					tb.gap_buffer_delete(&app_ctx.buffer, &app_ctx.text_view.cursor, .Backward)
				}

				app_ctx.is_modified = true
				update_scroll_to_cursor(app_ctx)
				update_gutter_width(app_ctx)
				update_status_bar_text(app_ctx)
				app_ctx.text_view.is_dirty = true
			case .DELETE:
				if app_ctx.opts.ro do return true

				if tb.is_selection(&app_ctx.text_view.cursor) {
					start, end := tb.get_selection_range(&app_ctx.text_view.cursor)
					tb.gap_buffer_delete_range(&app_ctx.buffer, &app_ctx.text_view.cursor, start, end)
				} else {
					tb.gap_buffer_delete(&app_ctx.buffer, &app_ctx.text_view.cursor, .Forward)
				}
				app_ctx.is_modified = true
				update_scroll_to_cursor(app_ctx)
				update_gutter_width(app_ctx)
				update_status_bar_text(app_ctx)
				app_ctx.text_view.is_dirty = true
			case .TAB:
				if app_ctx.opts.ro do return true

				if tb.is_selection(&app_ctx.text_view.cursor) {
					start, end := tb.get_selection_range(&app_ctx.text_view.cursor)
					tb.gap_buffer_delete_range(&app_ctx.buffer, &app_ctx.text_view.cursor, start, end)
				}

				if app_ctx.opts.indent == .Tabs {
					tb.gap_buffer_insert_text(&app_ctx.buffer, &app_ctx.text_view.cursor, "\t")
				} else {
					spaces := strings.repeat(" ", int(app_ctx.opts.tab_size), context.temp_allocator)
					tb.gap_buffer_insert_text(&app_ctx.buffer, &app_ctx.text_view.cursor, spaces)
				}
			
				app_ctx.is_modified = true
				update_scroll_to_cursor(app_ctx)
				update_status_bar_text(app_ctx)
				app_ctx.text_view.is_dirty = true
			case .RETURN:
				if app_ctx.opts.ro do return true

				if tb.is_selection(&app_ctx.text_view.cursor) {
					start, end := tb.get_selection_range(&app_ctx.text_view.cursor)
					tb.gap_buffer_delete_range(&app_ctx.buffer, &app_ctx.text_view.cursor, start, end)
				}

				tb.gap_buffer_line_feed(&app_ctx.buffer, &app_ctx.text_view.cursor)
				app_ctx.is_modified = true
				update_scroll_to_cursor(app_ctx)
				update_gutter_width(app_ctx)
				update_status_bar_text(app_ctx)
				app_ctx.text_view.is_dirty = true
			case .HOME:
				if ctrl_pressed {
					tb.gap_buffer_move_cursor_to(&app_ctx.buffer, &app_ctx.text_view.cursor, 0, 0, shift_pressed)
				} else {
					tb.gap_buffer_move_cursor_to(
						&app_ctx.buffer, 
						&app_ctx.text_view.cursor, 
						app_ctx.text_view.cursor.line, 
						0,
						shift_pressed,
					)
				}
				update_scroll_to_cursor(app_ctx)
				update_status_bar_text(app_ctx)
				app_ctx.text_view.is_dirty = true
			case .END:
				if ctrl_pressed {
					tb.gap_buffer_move_cursor_to(
						&app_ctx.buffer, 
						&app_ctx.text_view.cursor,
						tb.gap_buffer_get_line_count(&app_ctx.buffer) - 1, 
						max(int),
						shift_pressed,
					)
				} else {
					tb.gap_buffer_move_cursor_to(
						&app_ctx.buffer, 
						&app_ctx.text_view.cursor, 
						app_ctx.text_view.cursor.line, 
						max(int),
						shift_pressed,
					)
				}
				update_scroll_to_cursor(app_ctx)
				update_status_bar_text(app_ctx)
				app_ctx.text_view.is_dirty = true
			case .LEFT:	
				tb.gap_buffer_move_cursor_left(&app_ctx.buffer, &app_ctx.text_view.cursor, shift_pressed)
				update_scroll_to_cursor(app_ctx)
				update_status_bar_text(app_ctx)
				app_ctx.text_view.is_dirty = true
			case .RIGHT:
				tb.gap_buffer_move_cursor_right(&app_ctx.buffer, &app_ctx.text_view.cursor, shift_pressed)
				update_scroll_to_cursor(app_ctx)
				update_status_bar_text(app_ctx)
				app_ctx.text_view.is_dirty = true
			case .UP:
				tb.gap_buffer_move_cursor_to(
					&app_ctx.buffer,
					&app_ctx.text_view.cursor,
					app_ctx.text_view.cursor.line - 1,
					app_ctx.text_view.cursor.desired_col,
					shift_pressed,
				)
				update_scroll_to_cursor(app_ctx)
				update_status_bar_text(app_ctx)
				app_ctx.text_view.is_dirty = true
			case .DOWN:
				tb.gap_buffer_move_cursor_to(
					&app_ctx.buffer,
					&app_ctx.text_view.cursor, 
					app_ctx.text_view.cursor.line + 1, 
					app_ctx.text_view.cursor.desired_col,
					shift_pressed,
				)
				update_scroll_to_cursor(app_ctx)
				update_status_bar_text(app_ctx)
				app_ctx.text_view.is_dirty = true
			}

			app_ctx.cursor_visible = true
			app_ctx.cursor_timer = 0
		case .MOUSE_BUTTON_DOWN:
			if event.button.button == sdl3.BUTTON_LEFT {
				mod := sdl3.GetModState()
				shift_pressed := .LSHIFT in mod || .RSHIFT in mod

				mouse_x := event.button.x
				mouse_y := event.button.y

				text_start_x := app_ctx.text_view.rect.x + app_ctx.text_view.gutter_width

				if mouse_x >= text_start_x && mouse_x <= app_ctx.text_view.rect.x + app_ctx.text_view.rect.w &&
					mouse_y >= app_ctx.text_view.rect.y && mouse_y <= app_ctx.text_view.rect.y + app_ctx.text_view.rect.h {
				
					relative_x := mouse_x - text_start_x + app_ctx.text_view.scroll.x
					relative_y := mouse_y - app_ctx.text_view.rect.y + app_ctx.text_view.scroll.y
				
					target_line := int(relative_y / app_ctx.text_view.line_height)          
					target_col := int((relative_x + app_ctx.text_view.char_width / 2.0) / app_ctx.text_view.char_width)
				
					if tb.gap_buffer_move_cursor_to(
						&app_ctx.buffer,
						&app_ctx.text_view.cursor,
						target_line,
						target_col,
						shift_pressed,
					) {
						app_ctx.text_view.cursor.desired_col = app_ctx.text_view.cursor.col
						update_status_bar_text(app_ctx)
						app_ctx.text_view.is_dirty = true
					}
				
					app_ctx.cursor_visible = true
					app_ctx.cursor_timer = 0.0
				}
			}   
		}
	}
	return true
}

app_quit :: proc (app_ctx: ^App_Context) {
	_ = sdl3.StopTextInput(app_ctx.gfx.window)

	tb.gap_buffer_destroy(&app_ctx.buffer)

	for &vl in app_ctx.text_view.visible_lines {
		if vl.num_text_obj != nil do ttf.DestroyText(vl.num_text_obj)
		if vl.text_obj != nil     do ttf.DestroyText(vl.text_obj)
	}
	delete(app_ctx.text_view.visible_lines)

	ttf.DestroyText(app_ctx.status_bar.left_text)
	ttf.DestroyText(app_ctx.status_bar.right_text)

	ttf.CloseFont(app_ctx.font)
	ttf.DestroyRendererTextEngine(app_ctx.text_engine)
	sdl3.DestroyRenderer(app_ctx.gfx.renderer)
	sdl3.DestroyWindow(app_ctx.gfx.window)
	opts_destroy(&app_ctx.opts)

	ttf.Quit()
	sdl3.Quit()
}

update_gutter_width :: proc(app_ctx: ^App_Context) {
	if !app_ctx.opts.ln {
		app_ctx.text_view.gutter_width = 0.0
		return
	}

	total_lines := tb.gap_buffer_get_line_count(&app_ctx.buffer)

	digits := 1
	temp := total_lines
	for temp >= 10 {
		digits += 1
		temp /= 10
	}

	number_width := f32(digits) * app_ctx.text_view.char_width
	
	app_ctx.text_view.gutter_width = app_ctx.opts.ln_hmargin[0] + number_width + app_ctx.opts.ln_hmargin[1]
}

save_buffer_to_file :: proc(buf: ^tb.Gap_Buffer, file_path: string) -> bool {
	handle, os_err := os.open(
		file_path,
		os.O_WRONLY | os.O_CREATE | os.O_TRUNC,
		transmute(os.Permissions)u32(0o644)
	)
	if os_err != os.ERROR_NONE {
		fmt.eprintln("Failed to open file for writing:", os_err)
		return false
	}
	defer os.close(handle)

	stream := os.to_stream(handle)
	
	_, write_err := tb.gap_buffer_write_to_stream(buf, stream)
	if write_err != .None {
		fmt.eprintln("Failed to write buffer data to stream:", write_err)
		return false
	}

	return true
}

clamp_scroll :: proc(app_ctx: ^App_Context) {
	if app_ctx.text_view.scroll.y < 0 do app_ctx.text_view.scroll.y = 0
	if app_ctx.text_view.scroll.x < 0 do app_ctx.text_view.scroll.x = 0

	total_lines := tb.gap_buffer_get_line_count(&app_ctx.buffer)
	total_text_height := f32(total_lines) * app_ctx.text_view.line_height
	
	max_scroll_y := total_text_height - app_ctx.text_view.rect.h
	
	if max_scroll_y < 0 {
		app_ctx.text_view.scroll.y = 0
	} else if app_ctx.text_view.scroll.y > max_scroll_y {
		app_ctx.text_view.scroll.y = max_scroll_y
	}
}

 update_scroll_to_cursor :: proc(app_ctx: ^App_Context) {
 	horizontal_margin_px := f32(app_ctx.opts.scrolloff[0]) * app_ctx.text_view.char_width
 	vertical_margin_px   := f32(app_ctx.opts.scrolloff[1]) * app_ctx.text_view.line_height

 	cursor_pixel_y := f32(app_ctx.text_view.cursor.line) * app_ctx.text_view.line_height
 	cursor_pixel_x := f32(app_ctx.text_view.cursor.col) * app_ctx.text_view.char_width

 	// Vertical

 	min_visible_y := app_ctx.text_view.scroll.y + vertical_margin_px
 	max_visible_y := app_ctx.text_view.scroll.y + app_ctx.text_view.rect.h - (vertical_margin_px + app_ctx.text_view.line_height)

 	if cursor_pixel_y < min_visible_y {
 		app_ctx.text_view.scroll.y = cursor_pixel_y - vertical_margin_px
 	} else if cursor_pixel_y > max_visible_y {
 		app_ctx.text_view.scroll.y = cursor_pixel_y - app_ctx.text_view.rect.h + (vertical_margin_px + app_ctx.text_view.line_height)
 	}

 	// Horizontal

 	min_visible_x := app_ctx.text_view.scroll.x + horizontal_margin_px
 	max_visible_x := app_ctx.text_view.scroll.x + (app_ctx.text_view.rect.w - app_ctx.text_view.gutter_width) - horizontal_margin_px - app_ctx.text_view.char_width

 	if cursor_pixel_x < min_visible_x {
 		app_ctx.text_view.scroll.x = cursor_pixel_x - horizontal_margin_px
 	} else if cursor_pixel_x > max_visible_x {
 		app_ctx.text_view.scroll.x = cursor_pixel_x - (app_ctx.text_view.rect.w - app_ctx.text_view.gutter_width) + horizontal_margin_px + app_ctx.text_view.char_width
 	}

 	if app_ctx.text_view.scroll.y < 0 do app_ctx.text_view.scroll.y = 0
 	if app_ctx.text_view.scroll.x < 0 do app_ctx.text_view.scroll.x = 0

 	total_lines := len(app_ctx.buffer.line_offsets)
 	total_text_height := f32(total_lines) * app_ctx.text_view.line_height
 	max_scroll_y := total_text_height - app_ctx.text_view.rect.h
	
 	if max_scroll_y < 0 {
 		app_ctx.text_view.scroll.y = 0
 	} else if app_ctx.text_view.scroll.y > max_scroll_y {
 		app_ctx.text_view.scroll.y = max_scroll_y
 	}
 }
