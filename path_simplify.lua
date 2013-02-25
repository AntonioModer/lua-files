--2d path simplification: convert a complex path to a path containing only move, line, curve and close commands.
local arc = require'path_arc'.arc
local svgarc = require'path_svgarc'.svgarc
local shapes = require'path_shapes'
local cubic_control_points = require'path_math'.cubic_control_points
local reflect_point = require'path_math'.reflect_point
local path_commands = require'path_state'.commands
local next_state = require'path_state'.next_state

local unpack, radians = unpack, math.rad

local function shape_writer(writer, argc)
	return function(write, path, i)
		writer(write, unpack(path, i + 1, i + argc))
	end
end

local shape_writers = {
	ellipse     = shape_writer(shapes.ellipse, 4),
	circle      = shape_writer(shapes.circle, 3),
	rect        = shape_writer(shapes.rectangle, 4),
	round_rect  = shape_writer(shapes.round_rectangle, 5),
	star        = shape_writer(shapes.star, 7),
	rpoly       = shape_writer(shapes.regular_polygon, 4),
}

local function path_simplify(write, path) --avoid making garbage in here
	local cpx, cpy, spx, spy, bx, by, qx, qy
	for i,s in path_commands(path) do
		if s == 'move' or s == 'rel_move' then
			local x, y = path[i+1], path[i+2]
			if s == 'rel_move' then
				x, y = cpx + x, cpy + y
			end
			write('move', x, y)
		elseif s == 'close' then
			write('close')
		elseif s == 'line' or s == 'rel_line' then
			local x, y = path[i+1], path[i+2]
			if s == 'rel_line' then x, y = cpx + x, cpy + y end
			write('line', x, y)
		elseif s == 'hline' or s == 'rel_hline' then
			local x = path[i+1]
			if s == 'rel_hline' then x = cpx + x end
			write('line', x, cpy)
		elseif s == 'vline' or s == 'rel_vline' then
			local y = path[i+1]
			if s == 'rel_vline' then y = cpy + y end
			write('line', cpx, y)
		elseif s:match'curve$' then
			local x2, y2, x3, y3, x4, y4
			local rel, quad, smooth = s:match'^rel_', s:match'quad_', s:match'smooth_'
			if quad then
				local xc, yc
				if smooth then
					xc, yc = reflect_point(qx or cpx, qy or cpy, cpx, cpy)
					x4, y4 = path[i+1], path[i+2]
					if rel then x4, y4 = cpx + x4, cpy + y4 end
				else
					xc, yc, x4, y4 = unpack(path, i + 1, i + 4)
					if rel then xc, yc, x4, y4 = cpx + xc, cpy + yc, cpx + x4, cpy + y4 end
				end
				x2, y2, x3, y3 = cubic_control_points(cpx, cpy, xc, yc, x4, y4)
			else
				if smooth then
					x2, y2 = reflect_point(bx or cpx, by or cpy, cpx, cpy)
					x3, y3, x4, y4 = unpack(path, i + 1, i + 4)
					if rel then x3, y3, x4, y4 = cpx + x3, cpy + y3, cpx + x4, cpy + y4 end
				else
					x2, y2, x3, y3, x4, y4 = unpack(path, i + 1, i + 6)
					if rel then x2, y2, x3, y3, x4, y4 = cpx + x2, cpy + y2, cpx + x3, cpy + y3, cpx + x4, cpy + y4 end
				end
			end
			write('curve', x2, y2, x3, y3, x4, y4)
		elseif s:match'arc$' then
			local segments
			if s == 'arc' or s == 'rel_arc' then
				local cx, cy, r, start_angle, sweep_angle = unpack(path, i + 1, i + 5)
				if s == 'rel_arc' then cx, cy = cpx + cx, cpy + cy end
				segments = arc(cx, cy, r, r, radians(start_angle), radians(sweep_angle))
				write(cpx ~= nil and 'line' or 'move', segments[1], segments[2])
			else
				local rx, ry, angle, large_arc_flag, sweep_flag, x2, y2 = unpack(path, i + 1, i + 7)
				if s == 'rel_elliptical_arc' then x2, y2 = cpx + x2, cpy + y2 end
				segments = svgarc(cpx, cpy, rx, ry, radians(angle), large_arc_flag, sweep_flag, x2, y2)
			end
			if #segments == 4 then
				write('line', segments[3], segments[4])
			else
				for i=3,#segments,8 do
					write('curve', unpack(segments, i, i+6-1))
				end
			end
		elseif s == 'text' then
			write(s, path[i+1], path[i+2])
		elseif shape_writers[s] then
			shape_writers[s](write, path, i)
		end
		cpx, cpy, spx, spy, bx, by, qx, qy = next_state(path, i, cpx, cpy, spx, spy, bx, by, qx, qy)
	end
end

if not ... then require'sg_cairo_demo' end

return path_simplify
