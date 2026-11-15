extends Node2D

const DIRECTIONS = [Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0), Vector2i(0, -1), Vector2i(1, -1), Vector2i(1, 0)]
var cells: Dictionary = {}
var spacing: float = 86.0
var show_facets: bool = true
var far_view: bool = false
var outline_width: float = 2.0

func cell_position(cell: Vector2i) -> Vector2:
	return Vector2(cell.x + cell.y * 0.5, cell.y * sqrt(3.0) * 0.5) * spacing

func set_cells(value: Dictionary) -> void:
	cells = value.duplicate()
	queue_redraw()

func set_view_scale(zoom: float) -> void:
	var distant := zoom < 0.4
	if distant != far_view:
		far_view = distant
		outline_width = 4.0 if distant else 2.0
		queue_redraw()

func hexagon(center: Vector2) -> PackedVector2Array:
	var points := PackedVector2Array()
	for index in range(6):
		points.append(center + Vector2.from_angle(PI / 6.0 + index * PI / 3.0) * spacing / sqrt(3.0))
	return points

func _draw() -> void:
	for cell: Vector2i in cells:
		var center := cell_position(cell)
		var polygon := hexagon(center)
		if show_facets:
			var shade := 0.035 * posmod(cell.x + cell.y, 3)
			draw_colored_polygon(polygon, Color(0.11 + shade, 0.29 + shade, 0.40 + shade, 0.76 if far_view else 0.48))
			for side in range(6):
				if not cells.has(cell + DIRECTIONS[side]):
					draw_line(polygon[side], polygon[(side + 1) % 6], Color(0.62, 0.88, 0.96, 0.8), outline_width, true)
			for direction in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 1)]:
				if cells.has(cell + direction):
					draw_line(center, cell_position(cell + direction), Color(0.48, 0.77, 0.88, 0.13 if far_view else 0.32), 1.0, true)
		draw_line(center - Vector2(12, 0), center + Vector2(12, 0), Color(0.65, 0.9, 1, 0.65), 3.0, true)
		for offset in [-12.0, 12.0]:
			var point := center + Vector2(offset, 0)
			if not far_view:
				draw_circle(point, 11.0, Color(0.45, 0.82, 1, 0.09))
			draw_circle(point, 6.0, Color("91d2e6"))
			draw_circle(point + Vector2(-1.2, -1.2), 2.8, Color("efffff"))
