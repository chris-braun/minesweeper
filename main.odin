package main

import "core:math"
import "core:math/rand"
import rl "vendor:raylib"

Game_State :: enum {
	Menu,
	Playing,
	Won,
	Lost,
}

Cell :: struct {
	fill:    rl.Color,
	stroke:  rl.Color,
	color:   rl.Color,
	delta_t: f32,
	symbol:  cstring,
	covered: bool,
	flagged: bool,
	opening: bool,
}

Menu_Particle :: struct {
	color:    rl.Color,
	position: [2]f32,
	velocity: [2]f32,
	depth:    f32,
	size:     f32,
}

BUTTON_W :: 125
BUTTON_H :: 25

ROUNDNESS :: 0.03
SEGMENTS :: 4

PAD1 :: 4
PAD2 :: 8
PAD3 :: 16

CELL_SIZE :: 24
CELL_RADIUS :: i32(CELL_SIZE / 2)
CELL_MINE :: Cell{rl.BLACK, rl.BLACK, rl.RED, 0, "*", true, false, false}
CELL_COUNTS :: [9]Cell {
	Cell{rl.LIGHTGRAY, rl.LIGHTGRAY, rl.LIGHTGRAY, 0, "0", true, false, false},
	Cell{rl.GOLD, rl.ORANGE, rl.ORANGE, 0, "1", true, false, false},
	Cell{rl.GOLD, rl.ORANGE, rl.ORANGE, 0, "2", true, false, false},
	Cell{rl.GOLD, rl.ORANGE, rl.ORANGE, 0, "3", true, false, false},
	Cell{rl.GOLD, rl.ORANGE, rl.ORANGE, 0, "4", true, false, false},
	Cell{rl.GOLD, rl.ORANGE, rl.ORANGE, 0, "5", true, false, false},
	Cell{rl.GOLD, rl.ORANGE, rl.ORANGE, 0, "6", true, false, false},
	Cell{rl.GOLD, rl.ORANGE, rl.ORANGE, 0, "7", true, false, false},
	Cell{rl.GOLD, rl.ORANGE, rl.ORANGE, 0, "8", true, false, false},
}
CELL_OPENING_S :: 0.1

EASY_ROWS :: 9
EASY_COLS :: 9
EASY_MINES :: 10
EASY_W :: EASY_COLS * CELL_SIZE + (EASY_COLS + 1) * PAD1
EASY_H :: EASY_ROWS * CELL_SIZE + (EASY_ROWS + 1) * PAD1

MEDIUM_ROWS :: 16
MEDIUM_COLS :: 16
MEDIUM_MINES :: 40
MEDIUM_W :: MEDIUM_COLS * CELL_SIZE + (MEDIUM_COLS + 1) * PAD1
MEDIUM_H :: MEDIUM_ROWS * CELL_SIZE + (MEDIUM_ROWS + 1) * PAD1

HARD_ROWS :: 16
HARD_COLS :: 30
HARD_MINES :: 99
HARD_W :: HARD_COLS * CELL_SIZE + (HARD_COLS + 1) * PAD1
HARD_H :: HARD_ROWS * CELL_SIZE + (HARD_ROWS + 1) * PAD1

GLOW_FRAMES :: [4]rl.Color{rl.ORANGE, rl.GOLD, rl.ORANGE, rl.RED}
GLOW_DURATION_S :: 0.6

EMITTER_POSITION_SCREEN_CENTER :: [2]f32{f32(SCREEN_W) / 2.0, f32(SCREEN_H) / 2.0}

MAX_MENU_PARTICLES :: 40
MAX_MENU_PARTICLE_SIZE :: 60
MIN_MENU_PARTICLE_SIZE :: 10

FONT_SIZE :: CELL_SIZE
FONT_SIZE_SM :: 10

HEADER_W :: HARD_W
HEADER_H :: PAD3 + FONT_SIZE + PAD2

SCREEN_W :: PAD3 + HARD_W + PAD3
SCREEN_H :: HEADER_H + HARD_H + PAD3
TARGET_FRAME_RATE :: 60

get_animation_frame_index :: proc(elapsed_time, duration: f32, frame_count: i32) -> i32 {
	time_in_cycle := math.mod(elapsed_time, duration)
	time_per_frame := duration / f32(frame_count)
	return i32(math.floor(time_in_cycle / time_per_frame))
}


count_neighbor_mines :: proc(cells: []Cell, rows, cols, row, col: i32) -> i32 {
	if row < 0 || row >= rows || col < 0 || col >= cols do return 0

	cell := cells[row * cols + col]
	return 1 if cell.symbol == "*" else 0
}

new_game :: proc(cells: []Cell, rows, cols, mines: i32) {
	for _, i in cells do cells[i] = CELL_MINE if i32(i) < mines else CELL_COUNTS[0]

	rand.shuffle(cells)

	cell_counts := CELL_COUNTS
	for row in 0 ..< rows {
		for col in 0 ..< cols {
			index := row * cols + col
			cell := cells[index]
			if cell.symbol == "*" do continue

			count := count_neighbor_mines(cells, rows, cols, row - 1, col - 1)
			count += count_neighbor_mines(cells, rows, cols, row - 1, col + 0)
			count += count_neighbor_mines(cells, rows, cols, row - 1, col + 1)
			count += count_neighbor_mines(cells, rows, cols, row + 0, col - 1)
			count += count_neighbor_mines(cells, rows, cols, row + 0, col + 1)
			count += count_neighbor_mines(cells, rows, cols, row + 1, col - 1)
			count += count_neighbor_mines(cells, rows, cols, row + 1, col + 0)
			count += count_neighbor_mines(cells, rows, cols, row + 1, col + 1)
			if count > 0 {
				cells[index] = cell_counts[count]
			}
		}
	}
}

open_cell_and_neighbors :: proc(cells: []Cell, rows, cols, row, col: i32) {
	if row < 0 || row >= rows || col < 0 || col >= cols do return

	cell := &cells[row * cols + col]
	if !cell.covered do return

	cell.covered = false
	cell.flagged = false
	cell.opening = true
	cell.delta_t = 0
	if cell.symbol == "0" {
		open_cell_and_neighbors(cells, rows, cols, row - 1, col - 1)
		open_cell_and_neighbors(cells, rows, cols, row - 1, col + 0)
		open_cell_and_neighbors(cells, rows, cols, row - 1, col + 1)
		open_cell_and_neighbors(cells, rows, cols, row + 0, col - 1)
		open_cell_and_neighbors(cells, rows, cols, row + 0, col + 1)
		open_cell_and_neighbors(cells, rows, cols, row + 1, col - 1)
		open_cell_and_neighbors(cells, rows, cols, row + 1, col + 0)
		open_cell_and_neighbors(cells, rows, cols, row + 1, col + 1)
	}
}

init_menu_particles :: proc(particles: ^[MAX_MENU_PARTICLES]Menu_Particle) {
	for &particle in particles {
		particle.position.x = rand.float32() * SCREEN_W
		particle.position.y = rand.float32() * SCREEN_H
		particle.velocity.x = (rand.float32() - 0.5) * 1.6 + 0.4
		particle.velocity.y = (rand.float32() - 0.5) * 0.8 + 0.2
		particle.depth = rand.float32() * 0.8 + 0.2
		particle.size = max(particle.depth * MAX_MENU_PARTICLE_SIZE, MIN_MENU_PARTICLE_SIZE)
		particle.color = rl.WHITE
		particle.color.a = u8(255 * particle.depth * 0.5)
	}
}

draw_menu_particles :: proc(particles: ^[MAX_MENU_PARTICLES]Menu_Particle) {
	for &particle in particles {
		particle.position += particle.velocity * particle.depth
		if particle.position.x < -particle.size {
			particle.position.x = SCREEN_W + particle.size
		}
		if particle.position.x > SCREEN_W + particle.size {
			particle.position.x = -particle.size
		}
		if particle.position.y < -particle.size {
			particle.position.y = SCREEN_H + particle.size
		}
		if particle.position.y > SCREEN_H + particle.size {
			particle.position.y = -particle.size
		}

		rl.DrawText(
			"*",
			i32(particle.position.x),
			i32(particle.position.y),
			i32(particle.size),
			particle.color,
		)
	}
}

main :: proc() {
	rl.InitWindow(SCREEN_W, SCREEN_H, "Minesweeper")
	defer rl.CloseWindow()

	rl.SetTargetFPS(TARGET_FRAME_RATE)
	rl.SetExitKey(rl.KeyboardKey.KEY_NULL)

	skull := rl.LoadTexture("resources/skull.png")
	defer rl.UnloadTexture(skull)

	rl.InitAudioDevice()
	defer rl.CloseAudioDevice()

	fx_win := rl.LoadSound("resources/win.wav")
	defer rl.UnloadSound(fx_win)

	fx_explode := rl.LoadSound("resources/explode.wav")
	defer rl.UnloadSound(fx_explode)

	fx_lose := rl.LoadSound("resources/lose.wav")
	defer rl.UnloadSound(fx_lose)

	easy_bounds := rl.Rectangle {
		x      = (SCREEN_W - EASY_W) / 2,
		y      = HEADER_H + ((SCREEN_H - HEADER_H - PAD3) - EASY_H) / 2,
		width  = EASY_W,
		height = EASY_H,
	}
	medium_bounds := rl.Rectangle {
		x      = (SCREEN_W - MEDIUM_W) / 2,
		y      = HEADER_H,
		width  = MEDIUM_W,
		height = MEDIUM_H,
	}
	hard_bounds := rl.Rectangle {
		x      = (SCREEN_W - HARD_W) / 2,
		y      = HEADER_H,
		width  = HARD_W,
		height = HARD_H,
	}

	easy_button_bounds := rl.Rectangle{SCREEN_W - PAD3 - BUTTON_W, PAD3 - 1, BUTTON_W, BUTTON_H}
	medium_button_bounds := rl.Rectangle {
		easy_button_bounds.x,
		easy_button_bounds.y + BUTTON_H + PAD2,
		BUTTON_W,
		BUTTON_H,
	}
	hard_button_bounds := rl.Rectangle {
		medium_button_bounds.x,
		medium_button_bounds.y + BUTTON_H + PAD2,
		BUTTON_W,
		BUTTON_H,
	}
	back_button_bounds := easy_button_bounds

	glow_frames := GLOW_FRAMES

	buffer: Circular_Buffer
	emitter_position := EMITTER_POSITION_SCREEN_CENTER

	menu_particles: [MAX_MENU_PARTICLES]Menu_Particle
	init_menu_particles(&menu_particles)

	show_fps := false

	cell_pool: [HARD_ROWS * HARD_COLS]Cell
	game_state: Game_State
	rows: i32
	cols: i32
	mines: i32
	bounds: rl.Rectangle
	time: f32
	timer_started: bool
	cells: []Cell
	flagged_mines: i32
	game_over_time: f32

	for !rl.WindowShouldClose() {
		if game_state == .Playing && timer_started {
			time += rl.GetFrameTime()
		}
		if game_state == .Won || game_state == .Lost {
			game_over_time += rl.GetFrameTime()
		}

		rl.BeginDrawing()
		defer rl.EndDrawing()

		rl.ClearBackground(rl.SKYBLUE)

		if game_state == .Menu {
			draw_menu_particles(&menu_particles)

			rl.DrawText("CHOOSE YOUR LEVEL...", PAD3, PAD3, FONT_SIZE, rl.DARKBLUE)
			rl.DrawText(
				"Click a cell to open it",
				PAD3,
				PAD3 + FONT_SIZE + PAD1,
				FONT_SIZE_SM,
				rl.DARKBLUE,
			)
			rl.DrawText(
				"Alt + click a cell to flag it",
				PAD3,
				PAD3 + FONT_SIZE + PAD1 + FONT_SIZE_SM + PAD1,
				FONT_SIZE_SM,
				rl.DARKBLUE,
			)

			easy := rl.GuiButton(easy_button_bounds, "BEGINNER")
			medium := rl.GuiButton(medium_button_bounds, "INTERMEDIATE")
			hard := rl.GuiButton(hard_button_bounds, "ADVANCED")
			if easy || medium || hard {
				game_state = .Playing
				time = 0
				timer_started = false
				flagged_mines = 0
				game_over_time = 0
			}
			if easy {
				rows = EASY_ROWS
				cols = EASY_COLS
				mines = EASY_MINES
				bounds = easy_bounds
				cells = cell_pool[0:EASY_ROWS * EASY_COLS]
				new_game(cells, rows, cols, mines)
			}
			if medium {
				rows = MEDIUM_ROWS
				cols = MEDIUM_COLS
				mines = MEDIUM_MINES
				bounds = medium_bounds
				cells = cell_pool[0:MEDIUM_ROWS * MEDIUM_COLS]
				new_game(cells, rows, cols, mines)
			}
			if hard {
				rows = HARD_ROWS
				cols = HARD_COLS
				mines = HARD_MINES
				bounds = hard_bounds
				cells = cell_pool[0:HARD_ROWS * HARD_COLS]
				new_game(cells, rows, cols, mines)
			}
		} else {
			rl.DrawRectangleRounded(bounds, ROUNDNESS, SEGMENTS, rl.WHITE)
			rl.DrawRectangleRoundedLines(bounds, ROUNDNESS, SEGMENTS, rl.DARKBLUE)

			mouse := rl.GetMousePosition()

			y := i32(bounds.y) + PAD1
			for row in 0 ..< rows {
				x := i32(bounds.x) + PAD1
				for col in 0 ..< cols {
					cell := &cells[row * cols + col]

					mouse_down := rl.IsMouseButtonPressed(rl.MouseButton.LEFT)
					mouse_down_check: if game_state == .Playing && mouse_down {
						cell_bounds := rl.Rectangle{f32(x), f32(y), CELL_SIZE, CELL_SIZE}
						if rl.CheckCollisionPointRec(mouse, cell_bounds) {
							if !cell.covered do break mouse_down_check

							timer_started = true

							if rl.IsKeyDown(rl.KeyboardKey.LEFT_SHIFT) ||
							   rl.IsKeyDown(rl.KeyboardKey.LEFT_CONTROL) ||
							   rl.IsKeyDown(rl.KeyboardKey.LEFT_ALT) ||
							   rl.IsKeyDown(rl.KeyboardKey.LEFT_SUPER) ||
							   rl.IsKeyDown(rl.KeyboardKey.RIGHT_SUPER) ||
							   rl.IsKeyDown(rl.KeyboardKey.RIGHT_ALT) ||
							   rl.IsKeyDown(rl.KeyboardKey.RIGHT_SHIFT) {
								cell.flagged = !cell.flagged
							} else if cell.symbol == "0" {
								open_cell_and_neighbors(cells, rows, cols, row, col)
							} else if cell.symbol == "*" {
								cell.covered = false
								cell.flagged = false
								game_state = .Lost
								for &cell in cells {
									if cell.symbol == "*" {
										cell.covered = false
										cell.flagged = false
									}
								}
								reset_buffer(&buffer)
								emitter_position = [2]f32 {
									f32(x + CELL_RADIUS),
									f32(y + CELL_RADIUS),
								}

								rl.PlaySound(fx_explode)
								rl.PlaySound(fx_lose)
							} else {
								cell.covered = false
								cell.flagged = false
								cell.opening = true
								cell.delta_t = 0
							}
						}
					}

					cx, cy, radius := x + CELL_RADIUS, y + CELL_RADIUS, f32(CELL_RADIUS)
					if !cell.covered {
						cell_color := cell.color
						if cell.symbol == "*" {
							frame_index := get_animation_frame_index(
								game_over_time,
								GLOW_DURATION_S,
								len(GLOW_FRAMES),
							)
							cell_color = glow_frames[frame_index]
						}
						rl.DrawCircle(cx, cy, radius, cell.fill)
						rl.DrawCircleLines(cx, cy, radius, cell.stroke)
						rl.DrawText(cell.symbol, x + 6, y + 1, FONT_SIZE, cell_color)
					}
					if cell.covered || cell.opening {
						if cell.opening {
							radius *= max(1 - cell.delta_t / CELL_OPENING_S, 0)
							if cell.delta_t >= CELL_OPENING_S {
								cell.opening = false
							} else {
								cell.delta_t += rl.GetFrameTime()
							}
						}

						rl.DrawCircle(cx, cy, radius, rl.SKYBLUE)
						rl.DrawCircleLines(cx, cy, radius, rl.DARKBLUE)
					}
					if cell.flagged {
						rl.DrawCircle(cx, cy, radius, rl.PURPLE)
						rl.DrawCircleLines(cx, cy, radius, rl.DARKPURPLE)
						rl.DrawTexture(skull, x, y, rl.WHITE)
					}

					x += CELL_SIZE + PAD1
				}
				y += CELL_SIZE + PAD1
			}

			if game_state == .Won || game_state == .Lost {
				emit_particle(&buffer, emitter_position, .Star if game_state == .Won else .Smoke)
				update_particles(&buffer)
				update_buffer(&buffer)
				draw_particles(&buffer)
			}

			rl.DrawText(
				rl.TextFormat("%d MINES    %.0f SECONDS", mines - flagged_mines, time),
				PAD3,
				PAD3,
				FONT_SIZE,
				rl.DARKBLUE,
			)
			if game_state == .Won || game_state == .Lost {
				message: cstring = "YOU WIN!" if game_state == .Won else "GAME OVER, MAN!"
				text_start: i32 = SCREEN_W * 5 / 12
				rl.DrawText(message, text_start + 2, PAD3 + 2, FONT_SIZE, rl.DARKBLUE)
				rl.DrawText(message, text_start + 1, PAD3 + 1, FONT_SIZE, rl.ORANGE)
				rl.DrawText(message, text_start + 0, PAD3 + 0, FONT_SIZE, rl.GOLD)
			}
			if rl.GuiButton(back_button_bounds, "MENU") {
				game_state = .Menu
				reset_buffer(&buffer)
			}
		}

		if rl.IsKeyPressed(rl.KeyboardKey.SPACE) {
			show_fps = !show_fps
		}
		if (show_fps) {
			rl.DrawText(
				rl.TextFormat("%d FPS", rl.GetFPS()),
				PAD3,
				SCREEN_H - (PAD1 - 2) - FONT_SIZE_SM,
				FONT_SIZE_SM,
				rl.DARKBLUE,
			)
		}

		if game_state == .Playing {
			flagged_mines = 0
			open_cells: i32
			for &cell in cells {
				open_cells += 0 if cell.covered else 1
				flagged_mines += 1 if cell.flagged else 0
			}
			if flagged_mines == mines && open_cells == i32(len(cells)) - mines {
				game_state = .Won
				reset_buffer(&buffer)
				emitter_position = EMITTER_POSITION_SCREEN_CENTER

				rl.PlaySound(fx_win)
			}
		}
	}
}

//
// The following code was ported, with my own additions, from:
// "raylib [shapes] example - simple particles"
// Original example code contributed by Jordi Santonja (@JordSant)
// (https://github.com/raysan5/raylib/blob/master/examples/shapes/shapes_simple_particles.c)
//
MAX_PARTICLES :: 100

Particle_Type :: enum {
	Smoke,
	Star,
}

Particle :: struct {
	type:      Particle_Type,
	position:  [2]f32,
	velocity:  [2]f32,
	radius:    f32,
	life_time: f32,
	color:     rl.Color,
	alive:     bool,
}

Circular_Buffer :: struct {
	head:  int,
	tail:  int,
	store: [MAX_PARTICLES]Particle,
}

emit_particle :: proc(buffer: ^Circular_Buffer, emitter_position: [2]f32, type: Particle_Type) {
	new_particle := add_to_buffer(buffer)
	if new_particle == nil do return

	new_particle.position = emitter_position
	new_particle.alive = true
	new_particle.life_time = 0
	new_particle.type = type

	speed: f32
	switch type {
	case .Smoke:
		new_particle.radius = 7.0
		new_particle.color = rl.GRAY
		speed = rand.float32() * 2.0
	case .Star:
		new_particle.radius = 4.0
		new_particle.color = rl.WHITE
		speed = rand.float32() * 6.0
	}

	direction := rand.float32() * f32(math.PI) * 2
	new_particle.velocity = [2]f32{speed * math.cos(direction), speed * math.sin(direction)}
}

add_to_buffer :: proc(buffer: ^Circular_Buffer) -> ^Particle {
	if (buffer.head + 1) % MAX_PARTICLES != buffer.tail {
		buffer.head = (buffer.head + 1) % MAX_PARTICLES
		return &buffer.store[buffer.head]
	}

	return nil
}

update_particles :: proc(buffer: ^Circular_Buffer) {
	for i := buffer.tail; i != buffer.head; i = (i + 1) % MAX_PARTICLES {
		particle := &buffer.store[i]

		particle.life_time += 1.0 / 180.0 // 60 FPS -> 1/60 seconds per frame

		switch particle.type {
		case .Smoke:
			particle.velocity.y -= 0.05
			particle.position += particle.velocity
			particle.radius += 0.5
			particle.color.a -= 4

			if particle.color.a < 4 {particle.alive = false}
		case .Star:
			particle.position += particle.velocity
			particle.radius += 0.5
			particle.color.a -= 3

			if particle.color.a < 4 {particle.alive = false}
		}
		if !particle.alive do continue

		center := particle.position
		radius := particle.radius
		if ((center.x < -radius) ||
			   (center.x > (SCREEN_W + radius)) ||
			   (center.y < -radius) ||
			   (center.y > (SCREEN_H + radius))) {
			particle.alive = false
		}
	}
}

update_buffer :: proc(buffer: ^Circular_Buffer) {
	for (buffer.tail != buffer.head) && !buffer.store[buffer.tail].alive {
		buffer.tail = (buffer.tail + 1) % MAX_PARTICLES
	}
}

draw_particles :: proc(buffer: ^Circular_Buffer) {
	for i := buffer.tail; i != buffer.head; i = (i + 1) % MAX_PARTICLES {
		particle := &buffer.store[i]
		if particle.alive {
			switch particle.type {
			case .Smoke:
				rl.DrawCircleV(particle.position, particle.radius, particle.color)
			case .Star:
				draw_star(
					particle.position.x,
					particle.position.y,
					particle.radius,
					particle.radius / 2,
					particle.color,
				)
			}
		}
	}
}

reset_buffer :: proc(buffer: ^Circular_Buffer) {
	buffer.head = 0
	buffer.tail = 0
	for &particle in buffer.store do particle = Particle{}
}

draw_star :: proc(cx, cy, outer_r, inner_r: f32, color: rl.Color) {
	draw_section :: #force_inline proc(origin, v1, v2, v3: [2]f32, color: rl.Color) {
		rl.DrawTriangle(v1, v2, v3, color)
		rl.DrawTriangle(origin, v1, v3, color)
	}

	origin := [2]f32{cx, cy}

	angle_step := -2.0 * f32(math.PI) / 10.0
	vertices: [10][2]f32
	for &vertex, i in vertices {
		angle := f32(i) * angle_step
		radius := outer_r if i % 2 == 0 else inner_r
		vertex = [2]f32{cx + radius * math.cos(angle), cy + radius * math.sin(angle)}
	}

	draw_section(origin, vertices[1], vertices[2], vertices[3], color)
	draw_section(origin, vertices[3], vertices[4], vertices[5], color)
	draw_section(origin, vertices[5], vertices[6], vertices[7], color)
	draw_section(origin, vertices[7], vertices[8], vertices[9], color)
	draw_section(origin, vertices[9], vertices[0], vertices[1], color)
}
