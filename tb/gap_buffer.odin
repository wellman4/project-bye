package tb

import "core:io"
import "core:mem"

Gap_Buffer :: struct {
	data:       	[^]byte,
	cap:   			int,
	gap_start:  	int,
	gap_end:    	int,
	allocator:  	mem.Allocator,
	line_offsets: 	[dynamic]int, // In bytes, exclude gap
	end_of_line:	EOL,
}

EOL :: enum {
	// \n (Linux / macOS)
    LF,
	// \r\n (Windows)
    CRLF,
}

Cursor :: struct {
	pos: int, // In bytes, exclude gap
	selection_anchor_pos: int,

	// Logical
	line: int,
	col: int,
	desired_col: int,
}

Delete_Direction :: enum {
	Backward,
	Forward,
}

get_selection_range :: #force_inline proc(self: ^Cursor) -> (int, int) {
	return min(self.pos, self.selection_anchor_pos), max(self.pos, self.selection_anchor_pos)
}

is_selection :: #force_inline proc(self: ^Cursor) -> bool {
	return self.pos != self.selection_anchor_pos
}

// ------------------------------------------------------------------------------------------------
// Create
// -------------------------------------------------------------------------------------------------

// Initializing buffer with capacity
gap_buffer_init :: proc(
	buf: ^Gap_Buffer,
	cap: int,
	lines_cap: int,
	allocator := context.allocator
) -> mem.Allocator_Error {

	buf.allocator = allocator
	buf.cap = cap
	
	raw_mem := mem.alloc(buf.cap, allocator = buf.allocator) or_return
	buf.data = ([^]byte)(raw_mem)
	
	buf.gap_start = 0
	buf.gap_end = buf.cap
	
	initial_lines_cap := max(lines_cap, 4)
	buf.line_offsets = make([dynamic]int, 0, initial_lines_cap, buf.allocator)
	append(&buf.line_offsets, 0)
	
	return .None
}

gap_buffer_init_from_bytes :: proc(
	buf: ^Gap_Buffer, 
	bytes: []byte,
	gap_len: int,
	allocator := context.allocator,
) -> mem.Allocator_Error {

	data_len := len(bytes)
	
	line_count := 1
	removed_cr_count := 0
	buf.end_of_line = .LF

	for i in 0..<data_len {
		if bytes[i] == '\r' {
			if i + 1 < data_len && bytes[i + 1] == '\n' {
				buf.end_of_line = .CRLF
				removed_cr_count += 1
			} else {
				line_count += 1
			}
		} else if bytes[i] == '\n' {
			line_count += 1
		}
	}

	cap := gap_len + data_len - removed_cr_count
	gap_buffer_init(buf, cap, line_count) or_return

	buf.gap_start = 0
	buf.gap_end = gap_len

	write_index := buf.gap_end
	byte_offset := 0

	for i in 0..<data_len {
		b := bytes[i]

		if b == '\r' {
			if i + 1 < data_len && bytes[i + 1] == '\n' {
				continue
			} else {
				b = '\n'
			}
		}

		buf.data[write_index] = b
		write_index += 1
		byte_offset += 1

		if b == '\n' && i < data_len - 1 {
			append(&buf.line_offsets, byte_offset)
		}
	}

	return .None
}

// -------------------------------------------------------------------------------------------------
// Read
// -------------------------------------------------------------------------------------------------

// Buffer's length in bytes without gap
gap_buffer_len :: #force_inline proc(buf: ^Gap_Buffer) -> int {
	return buf.cap - get_gap_len(buf)
}

gap_buffer_get_line_count :: #force_inline proc(buf: ^Gap_Buffer) -> int {
	return len(buf.line_offsets)
}

gap_buffer_get_selection :: proc(self: ^Gap_Buffer, start, end: int) -> (string, mem.Allocator_Error) {
	logical_len := self.cap - (self.gap_end - self.gap_start)
	s := clamp(start, 0, logical_len)
	e := clamp(end, s, logical_len)
	
	req_len := e - s
	if req_len == 0 do return "", nil

	buf, err := mem.alloc_bytes(req_len, allocator = context.allocator)
	if err != nil do return "", err

	dst_cursor := 0

	if s < self.gap_start {
		part1_end := min(e, self.gap_start)
		part1_len := part1_end - s
		
		mem.copy(&buf[dst_cursor], &self.data[s], part1_len)
		dst_cursor += part1_len
	}

	if e > self.gap_start {
		part2_start := max(s, self.gap_start)
		part2_len := e - part2_start
		
		gap_size := self.gap_end - self.gap_start
		phys_start := part2_start + gap_size
		
		mem.copy(&buf[dst_cursor], &self.data[phys_start], part2_len)
	}

	return string(buf), nil
}

gap_buffer_get_line :: proc(
	buf: ^Gap_Buffer, 
	line_idx: int, 
) -> (line_text: string, is_broken: bool) {
	
	if line_idx < 0 || line_idx >= len(buf.line_offsets) do return "", true

	start_pos := buf.line_offsets[line_idx]
	end_pos   := 0
	
	if line_idx == len(buf.line_offsets) - 1 {
		end_pos = gap_buffer_len(buf)
	} else {
		end_pos = buf.line_offsets[line_idx + 1]
	}

	if start_pos >= end_pos do return "", false

	line_len := end_pos - start_pos
	

	if end_pos <= buf.gap_start {
		slice := buf.data[start_pos : start_pos + line_len]
		
		return trim_line_feed(string(slice)), false
	}

	if start_pos >= buf.gap_start {
		gap_size := buf.gap_end - buf.gap_start
		real_start := start_pos + gap_size
		
		slice := buf.data[real_start : real_start + line_len]
		return trim_line_feed(string(slice)), false
	}

	temp_scratch, alloc_err := make([]byte, line_len, context.temp_allocator)
	if alloc_err != nil do return "", true

	left_len := buf.gap_start - start_pos
	if left_len > 0 {
		mem.copy(&temp_scratch[0], &buf.data[start_pos], left_len)
	}

	right_len := line_len - left_len
	if right_len > 0 {
		mem.copy(&temp_scratch[left_len], &buf.data[buf.gap_end], right_len)
	}

	slice := temp_scratch[:line_len]
	return trim_line_feed(string(slice)), false
}

gap_buffer_write_to_stream :: proc(
	buf: ^Gap_Buffer,
	writer: io.Writer
) -> (bytes_written: int, err: io.Error) {
	
	left_len := buf.gap_start
	right_len := buf.cap - buf.gap_end

	if buf.end_of_line == .CRLF {
		for i in 0..<left_len {
			b := buf.data[i]
			if b == '\n' {
				io.write_byte(writer, '\r') or_return
				bytes_written += 1
			}
			io.write_byte(writer, b) or_return
			bytes_written += 1
		}

		for i in buf.gap_end..<buf.cap {
			b := buf.data[i]
			if b == '\n' {
				io.write_byte(writer, '\r') or_return
				bytes_written += 1
			}
			io.write_byte(writer, b) or_return
			bytes_written += 1
		}
	} else {
		if left_len > 0 {
			left_slice := buf.data[0:left_len]
			n := io.write(writer, left_slice) or_return
			bytes_written += n
		}
		if right_len > 0 {
			right_slice := buf.data[buf.gap_end:buf.cap]
			n := io.write(writer, right_slice) or_return
			bytes_written += n
		}
	}

	return bytes_written, .None
}

// -------------------------------------------------------------------------------------------------
// Update
// -------------------------------------------------------------------------------------------------

gap_buffer_move_cursor_left :: proc(buf: ^Gap_Buffer, cursor: ^Cursor, is_selecting: bool) -> bool {
	if cursor.pos <= 0 do return false

	width := get_prev_rune_len(buf, cursor.pos)
	
	start_byte := buf.data[get_raw_index(buf, cursor.pos - width)]

	cursor.pos -= width

	if start_byte == '\n' {
		cursor.line -= 1
		cursor.col = get_line_len_in_runes(buf, cursor.line)
	} else {
		cursor.col -= 1
	}
	if !is_selecting do cursor.selection_anchor_pos = cursor.pos
	cursor.desired_col = cursor.col

	return true
}

gap_buffer_move_cursor_right :: proc(buf: ^Gap_Buffer, cursor: ^Cursor, is_selecting: bool) -> bool {
    if cursor.pos >= gap_buffer_len(buf) do return false
    
	first_byte := buf.data[get_raw_index(buf, cursor.pos)]
    width := get_rune_len_by_first_byte(first_byte)
    
    if first_byte == '\n' {
        cursor.line += 1
        cursor.col = 0
    } else {
        cursor.col += 1
    }
    
    cursor.pos += width
	if !is_selecting do cursor.selection_anchor_pos = cursor.pos
	cursor.desired_col = cursor.col

	return true
}

gap_buffer_move_cursor_to :: proc(
	buf: ^Gap_Buffer,
	cursor: ^Cursor,
	target_line,
	target_col: int,
	is_selecting: bool,
) -> bool {

	total_lines := len(buf.line_offsets)

	if target_line < 0 || target_line >= total_lines do return false

	cursor.line = target_line

	start_byte := buf.line_offsets[cursor.line]

	end_byte := gap_buffer_len(buf)
	if cursor.line + 1 < total_lines {
		end_byte = buf.line_offsets[cursor.line + 1]
	}

	current_byte := start_byte
	cursor.col = 0

	for cursor.col < target_col && current_byte < end_byte {
		b := buf.data[get_raw_index(buf, current_byte)]

		if b == '\n' do break 

		width := get_rune_len_by_first_byte(b)
		
		current_byte += width
		cursor.col += 1
	}

	cursor.pos = current_byte
	if !is_selecting do cursor.selection_anchor_pos = cursor.pos
	if target_col != cursor.desired_col do cursor.desired_col = cursor.col

	return true
}

gap_buffer_move_gap_to :: proc(buf: ^Gap_Buffer, target_logical_byte: int) {
	target := clamp(target_logical_byte, 0, gap_buffer_len(buf))

	if target == buf.gap_start do return

	gap_len := get_gap_len(buf)

	if target < buf.gap_start {
		bytes_to_move := buf.gap_start - target
		
		src := &buf.data[target]
		dst := &buf.data[target + gap_len]
		
		mem.copy(dst, src, bytes_to_move)
		
		buf.gap_start = target
		buf.gap_end = target + gap_len
	} else {
		bytes_to_move := target - buf.gap_start
		
		src := &buf.data[buf.gap_end]
		dst := &buf.data[buf.gap_start]
		
		mem.copy(dst, src, bytes_to_move)
		
		buf.gap_start = target
		buf.gap_end = target + gap_len
	}
}

gap_buffer_line_feed :: proc(buf: ^Gap_Buffer, cursor: ^Cursor) -> mem.Allocator_Error {
	gap_buffer_move_gap_to(buf, cursor.pos)

	if get_gap_len(buf) < 1 do grow(buf, 1) or_return
	
	buf.data[buf.gap_start] = '\n'
	buf.gap_start += 1

	inject_at(&buf.line_offsets, cursor.line + 1, cursor.pos + 1) or_return

	for i in cursor.line + 2..<len(buf.line_offsets) {
		buf.line_offsets[i] += 1
	}

	cursor.line += 1
	cursor.col = 0
	cursor.pos += 1
	cursor.selection_anchor_pos = cursor.pos
	cursor.desired_col = cursor.col
	
	return .None
}

gap_buffer_insert_text :: proc(buf: ^Gap_Buffer, cursor: ^Cursor, text: string) {
	bytes_len := len(text)
	if bytes_len == 0 do return

	gap_buffer_move_gap_to(buf, cursor.pos)

	if get_gap_len(buf) < bytes_len do grow(buf, bytes_len)

	src := raw_data(text)
	dst := &buf.data[buf.gap_start]
	mem.copy(dst, src, bytes_len)

	inserted_lines_count := 0
	curr_byte_idx := 0

	for curr_byte_idx < bytes_len {
		b := text[curr_byte_idx]
		
		if b == '\n' {
			inserted_lines_count += 1
			next_line_offset := cursor.pos + curr_byte_idx + 1
			
			inject_at(&buf.line_offsets, cursor.line + inserted_lines_count, next_line_offset)
			
			cursor.col = 0
		} else {
			if (b & 0xC0) != 0x80 {
				cursor.col += 1
			}
		}
		
		curr_byte_idx += 1
	}

	start_shift_idx := cursor.line + inserted_lines_count + 1
	for i := start_shift_idx; i < len(buf.line_offsets); i += 1 {
		buf.line_offsets[i] += bytes_len
	}

	buf.gap_start += bytes_len
	cursor.pos += bytes_len
	cursor.selection_anchor_pos = cursor.pos
	cursor.line += inserted_lines_count
	cursor.desired_col = cursor.col
}

// -------------------------------------------------------------------------------------------------
// Delete
// -------------------------------------------------------------------------------------------------

gap_buffer_delete :: proc(buf: ^Gap_Buffer, cursor: ^Cursor, dir: Delete_Direction) {
	gap_buffer_move_gap_to(buf, cursor.pos)

	switch dir {
	case .Forward:
		if buf.gap_end >= buf.cap do return 

		first_byte := buf.data[buf.gap_end]
		width := get_rune_len_by_first_byte(first_byte)

		if first_byte == '\n' {
			ordered_remove(&buf.line_offsets, cursor.line + 1)

			for i := cursor.line + 1; i < len(buf.line_offsets); i += 1 {
				buf.line_offsets[i] -= width
			}
		} else {
			for i := cursor.line + 1; i < len(buf.line_offsets); i += 1 {
				buf.line_offsets[i] -= width
			}
		}

		buf.gap_end += width
	
	case .Backward:
		if buf.gap_start <= 0 do return 

		width := get_prev_rune_len(buf, cursor.pos)

		start_raw_idx := get_raw_index(buf, cursor.pos - width)
		start_byte := buf.data[start_raw_idx]

		if start_byte == '\n' {
			ordered_remove(&buf.line_offsets, cursor.line)

			for i := cursor.line; i < len(buf.line_offsets); i += 1 {
				buf.line_offsets[i] -= width
			}
			
			cursor.line -= 1
			cursor.col = get_line_len_in_runes(buf, cursor.line)
		} else {
			for i := cursor.line + 1; i < len(buf.line_offsets); i += 1 {
				buf.line_offsets[i] -= width
			}
			cursor.col -= 1
		}

		buf.gap_start -= width
		cursor.pos -= width
		cursor.selection_anchor_pos = cursor.pos
		cursor.desired_col = cursor.col
	}
}

gap_buffer_delete_range :: proc(buf: ^Gap_Buffer, cursor: ^Cursor, start_pos, end_pos: int) {
	buf_len := gap_buffer_len(buf)
	s := max(0, min(start_pos, buf_len))
	e := max(0, min(end_pos, buf_len))
	
	if s >= e do return

	range_width := e - s

	gap_buffer_move_gap_to(buf, s)

	start_line := 0
	for i := 1; i < len(buf.line_offsets); i += 1 {
		if buf.line_offsets[i] <= s {
			start_line = i
		} else {
			break
		}
	}

	for i := len(buf.line_offsets) - 1; i > 0; i -= 1 {
		offset := buf.line_offsets[i]
		if offset > s && offset <= e {
			ordered_remove(&buf.line_offsets, i)
		}
	}

	for i := 0; i < len(buf.line_offsets); i += 1 {
		if buf.line_offsets[i] > s {
			buf.line_offsets[i] -= range_width
		}
	}

	buf.gap_end += range_width

	cursor.pos = s
	cursor.line = start_line

	line_start_byte := buf.line_offsets[start_line]
	curr_byte := line_start_byte
	runes_count := 0

	for curr_byte < cursor.pos {
		raw_idx := get_raw_index(buf, curr_byte)
		b := buf.data[raw_idx]
		
		curr_byte += get_rune_len_by_first_byte(b)
		runes_count += 1
	}

	cursor.col = runes_count
	cursor.desired_col = cursor.col
	cursor.selection_anchor_pos = cursor.pos
}


gap_buffer_destroy :: proc(buf: ^Gap_Buffer) {
	mem.zero_slice(mem.slice_ptr(buf.data, buf.cap))
	mem.free(buf.data, buf.allocator)
	buf.data = nil

	buf.cap = 0
	buf.gap_start = 0
	buf.gap_end = 0

	mem.zero_slice(mem.slice_ptr(raw_data(buf.line_offsets), cap(buf.line_offsets)))
	delete(buf.line_offsets)
	buf.line_offsets = nil
}

gap_buffer_clear :: proc(buf: ^Gap_Buffer) {
	mem.zero_slice(mem.slice_ptr(buf.data, buf.cap))

	buf.gap_start = 0
	buf.gap_end = buf.cap

	mem.zero_slice(mem.slice_ptr(raw_data(buf.line_offsets), cap(buf.line_offsets)))
	clear(&buf.line_offsets)
	append(&buf.line_offsets, 0)
}

// -------------------------------------------------------------------------------------------------
// Private
// -------------------------------------------------------------------------------------------------

@(private="file")
get_gap_len :: #force_inline proc(buf: ^Gap_Buffer) -> int {
	return buf.gap_end - buf.gap_start
}

@(private="file")
get_rune_len_by_first_byte :: #force_inline proc(b: byte) -> int {
	if      (b & 0x80) == 0x00 do return 1 // 0xxxxxxx
	else if (b & 0xE0) == 0xC0 do return 2 // 110xxxxx
	else if (b & 0xF0) == 0xE0 do return 3 // 1110xxxx
	else if (b & 0xF8) == 0xF0 do return 4 // 11110xxx
	return 1
}

@(private="file")
get_prev_rune_len :: proc(buf: ^Gap_Buffer, current_logical_pos: int) -> int {
	if current_logical_pos <= 0 do return 0

	width := 0
	for {
		width += 1
		if current_logical_pos - width <= 0 do break

		raw_idx := get_raw_index(buf, current_logical_pos - width)
		b := buf.data[raw_idx]
		
		if (b & 0xC0) != 0x80 { 
			break
		}
	}
	return width
}

@(private="file")
get_raw_index :: #force_inline proc(buf: ^Gap_Buffer, logical_byte_index: int) -> int {
	return logical_byte_index if logical_byte_index < buf.gap_start else logical_byte_index + get_gap_len(buf)
}

@(private="file")
get_line_len_in_runes :: proc(buf: ^Gap_Buffer, line_index: int) -> int {
	if line_index < 0 || line_index >= len(buf.line_offsets) do return 0

	start_byte := buf.line_offsets[line_index]
	end_byte := gap_buffer_len(buf)
	
	if line_index + 1 < len(buf.line_offsets) {
		end_byte = buf.line_offsets[line_index + 1]
	}

	runes_count := 0
	curr_byte := start_byte

	for curr_byte < end_byte {
		b := buf.data[get_raw_index(buf, curr_byte)]

		if b == '\n' do break

		curr_byte += get_rune_len_by_first_byte(b)
		runes_count += 1
	}

	return runes_count
}

@(private="file")
trim_line_feed :: proc(s: string) -> string {
	if len(s) == 0 do return s
	
	res := s
	if res[len(res)-1] == '\n' {
		res = res[:len(res)-1]
	}
	return res
}

@(private="file")
grow :: proc(buf: ^Gap_Buffer, additional_capacity: int) -> mem.Allocator_Error {
	current_gap_len := get_gap_len(buf)
	if current_gap_len >= additional_capacity do return .None
	
	new_capacity := buf.cap * 2
	needed := buf.cap + (additional_capacity - current_gap_len)
	if new_capacity < needed do new_capacity = needed
	
	new_raw := mem.alloc(new_capacity, allocator = buf.allocator) or_return
	new_data := ([^]byte)(new_raw)
	
	if buf.gap_start > 0 {
		mem.copy(new_data, buf.data, buf.gap_start)
	}
	
	right_part_len := buf.cap - buf.gap_end
	new_gap_end := new_capacity - right_part_len
	
	if right_part_len > 0 {
		mem.copy(&new_data[new_gap_end], &buf.data[buf.gap_end], right_part_len)
	}

	mem.set(buf.data, 0, buf.cap)
	mem.free(buf.data, allocator = buf.allocator)
	
	buf.data = new_data
	buf.gap_end = new_gap_end
	buf.cap = new_capacity
	return .None
}
