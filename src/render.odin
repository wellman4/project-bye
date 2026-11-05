package main

import "vendor:sdl3"
import "vendor:sdl3/ttf"

render :: proc(app_ctx: ^App_Context) {
    sdl3.SetRenderDrawColor(
		app_ctx.gfx.renderer, 
		app_ctx.colors.background.r,
		app_ctx.colors.background.g, 
		app_ctx.colors.background.b,
		app_ctx.colors.background.a,
	)
	sdl3.RenderClear(app_ctx.gfx.renderer)

    draw_text_view(app_ctx)
    draw_status_bar(app_ctx)
	
	sdl3.RenderPresent(app_ctx.gfx.renderer)
}

draw_text_view :: proc(app_ctx: ^App_Context) {
	text_clip := sdl3.Rect{
		x = i32(app_ctx.text_view.rect.x + app_ctx.text_view.gutter_width),
		y = i32(app_ctx.text_view.rect.y),
		w = i32(app_ctx.text_view.rect.w - app_ctx.text_view.gutter_width),
		h = i32(app_ctx.text_view.rect.h),
	}
	sdl3.SetRenderClipRect(app_ctx.gfx.renderer, &text_clip)

	for &vl in app_ctx.text_view.visible_lines {
		if vl.has_selection {
			sdl3.SetRenderDrawColor(app_ctx.gfx.renderer, app_ctx.colors.selection.r, app_ctx.colors.selection.g, app_ctx.colors.selection.b, app_ctx.colors.selection.a)
			sdl3.RenderFillRect(app_ctx.gfx.renderer, &vl.sel_rect)
		}
		if vl.text_obj != nil {
			x_pos := app_ctx.text_view.rect.x + app_ctx.text_view.gutter_width - app_ctx.text_view.scroll.x
			ttf.DrawRendererText(vl.text_obj, x_pos, vl.y_pos)
		}
	}

	if app_ctx.cursor_visible {
		sdl3.SetRenderDrawColor(app_ctx.gfx.renderer, app_ctx.colors.cursor.r, app_ctx.colors.cursor.g, app_ctx.colors.cursor.b, app_ctx.colors.cursor.a)
		sdl3.RenderFillRect(app_ctx.gfx.renderer, &app_ctx.text_view.cursor_rect)
	}

	full_clip := sdl3.Rect{
		x = i32(app_ctx.text_view.rect.x), y = i32(app_ctx.text_view.rect.y),
		w = i32(app_ctx.text_view.rect.w), h = i32(app_ctx.text_view.rect.h),
	}
	sdl3.SetRenderClipRect(app_ctx.gfx.renderer, &full_clip)

	gutter_rect := sdl3.FRect{
		x = app_ctx.text_view.rect.x, y = app_ctx.text_view.rect.y,
		w = app_ctx.text_view.gutter_width, h = app_ctx.text_view.rect.h,
	}
	sdl3.SetRenderDrawColor(app_ctx.gfx.renderer, app_ctx.colors.gutter.r, app_ctx.colors.gutter.g, app_ctx.colors.gutter.b, app_ctx.colors.gutter.a)
	sdl3.RenderFillRect(app_ctx.gfx.renderer, &gutter_rect)

	if app_ctx.opts.ln {
		for &vl in app_ctx.text_view.visible_lines {
			if vl.num_text_obj != nil {
				num_w: i32
				ttf.GetTextSize(vl.num_text_obj, &num_w, nil)
				num_x_pos := app_ctx.text_view.rect.x + app_ctx.text_view.gutter_width - app_ctx.opts.ln_hmargin[1] - f32(num_w)
				
				ttf.DrawRendererText(vl.num_text_obj, num_x_pos, vl.y_pos)
			}
		}
	}

	sdl3.SetRenderClipRect(app_ctx.gfx.renderer, nil)
}

draw_status_bar :: proc(app_ctx: ^App_Context) {
	sdl3.SetRenderDrawColor(
		app_ctx.gfx.renderer,
		app_ctx.colors.status_bar_bg.r,
		app_ctx.colors.status_bar_bg.g,
		app_ctx.colors.status_bar_bg.b,
		app_ctx.colors.status_bar_bg.a,
	)
	sdl3.RenderFillRect(app_ctx.gfx.renderer, &app_ctx.status_bar.rect)

	if app_ctx.status_bar.left_text != nil {
		text_w, text_h: i32
		ttf.GetTextSize(app_ctx.status_bar.left_text, &text_w, &text_h)
		
		text_y := app_ctx.status_bar.rect.y + (app_ctx.status_bar.rect.h - f32(text_h)) / 2.0 - 2.5
		
		ttf.DrawRendererText(app_ctx.status_bar.left_text, 10.0, text_y)
	}

	if app_ctx.status_bar.right_text != nil {
		text_w, text_h: i32
		ttf.GetTextSize(app_ctx.status_bar.right_text, &text_w, &text_h)
		
		right_x := (app_ctx.status_bar.rect.x + app_ctx.status_bar.rect.w) - f32(text_w) - 10.0
		text_y  := app_ctx.status_bar.rect.y + (app_ctx.status_bar.rect.h - f32(text_h)) / 2.0 - 2.5
		
		ttf.DrawRendererText(app_ctx.status_bar.right_text, right_x, text_y)
	}
}
