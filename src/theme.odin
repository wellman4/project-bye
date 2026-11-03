package main

import sdl "vendor:sdl3"

Theme :: enum {
    Dark,
    Light,
}

Theme_Colors :: struct {
	background: 		sdl.Color,
	text:       		sdl.Color,
	cursor:     		sdl.Color,
	selection: 			sdl.Color,
	gutter:				sdl.Color,
	line_numbers_text:  sdl.Color,
	status_bar_bg:      sdl.Color,
	status_bar_text:    sdl.Color,
	modified_accent:    sdl.Color,
}

get_theme_colors :: proc(theme: Theme) -> Theme_Colors {
	switch theme {
    case .Dark:
        return Theme_Colors{
			background 			= {8, 8, 8, 255},		// rgb(8, 8, 8)
			text       			= {145, 145, 145, 255},	// rgb(145, 145, 145)
			cursor     			= {255, 255, 255, 255},	// rgb(255, 255, 255)
			selection 			= {0, 63, 90, 255},		// rgb(0, 63, 90)
			gutter				= {8, 8, 8, 255}, 		// rgb(8, 8, 8)
			line_numbers_text 	= {100, 100, 100, 255}, // rgb(100, 100, 100)
			status_bar_bg 		= {4, 4, 4, 255},		// rgb(4, 4, 4)
			status_bar_text	    = {120, 120, 120, 255},	// rgb(120, 120, 120)
			modified_accent 	= {187, 125, 0, 255},	// rgb(187, 125, 0)
        }

	case .Light:
        return Theme_Colors{
            background 			= {223, 223, 223, 255},	// rgb(223, 223, 223)
			text       			= {32, 32, 32, 255},	// rgb(32, 32, 32)
			cursor     			= {0, 132, 255, 255},	// rgb(0, 132, 255)
			selection 			= {139, 190, 211, 255},	// rgb(139, 190, 211)
			gutter				= {211, 211, 211, 255}, // rgb(211, 211, 211)
			line_numbers_text 	= {87, 87, 87, 255}, 	// rgb(87, 87, 87)
			status_bar_bg 		= {202, 202, 202, 255},	// rgb(202, 202, 202)
			status_bar_text	    = {97, 97, 97, 255},	// rgb(97, 97, 97)
			modified_accent 	= {201, 120, 0, 255},	// rgb(255, 145, 0)
        }
    case:
    	return {}
	}
}
