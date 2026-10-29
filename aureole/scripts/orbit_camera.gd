extends Camera3D
## Spherical orbit with inertia, tracked touch IDs, aspect-safe framing and restore.
signal interacted

var yaw := 0.0
var pitch := 0.10
var zoom := 1.0
var target_zoom := 1.0
var velocity := Vector2.ZERO
var touches: Dictionary = {}
var mouse_drag := false
var idle_seconds := 0.0
var automatic_orbit := true
var enabled := true
var focus := Vector3(0.0, 0.45, 0.0)
var reset_tween: Tween

func _ready() -> void:
	fov = 38.0
	near = 0.2
	far = 140.0
	get_viewport().size_changed.connect(_resize)
	_resize()
	_update_transform()

func _resize() -> void:
	# A 5.5 m radius envelope includes crest, satellites, and the entire silhouette.
	var aspect := get_viewport().get_visible_rect().size.aspect()
	set_meta("framing_distance", 5.9 / (tan(deg_to_rad(fov * 0.5)) * minf(aspect, 1.0)) + 1.5)

func _process(delta: float) -> void:
	if not enabled:
		return
	var dt := minf(delta, 0.05)
	idle_seconds += dt
	if touches.is_empty() and not mouse_drag:
		yaw += velocity.x * dt
		pitch = clampf(pitch + velocity.y * dt, -1.15, 1.15)
		velocity *= exp(-3.8 * dt)
		if automatic_orbit and idle_seconds > 8.0:
			yaw += 0.025 * dt * smoothstep(8.0, 12.0, idle_seconds)
	zoom = lerpf(zoom, target_zoom, 1.0 - exp(-8.0 * dt))
	_update_transform()

func _update_transform() -> void:
	var distance: float = get_meta("framing_distance", 19.0) * zoom
	position = focus + Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * distance
	look_at(focus, Vector3.UP)

func _activity() -> void:
	if reset_tween != null and reset_tween.is_running():
		reset_tween.kill()
	idle_seconds = 0.0
	interacted.emit()

func _drag(relative: Vector2) -> void:
	var movement := relative * (3.7 / maxf(500.0, get_viewport().get_visible_rect().size.x))
	yaw -= movement.x
	pitch = clampf(pitch - movement.y, -1.15, 1.15)
	velocity = Vector2(-movement.x, -movement.y) * 22.0
	_activity()

func _unhandled_input(event: InputEvent) -> void:
	if not enabled:
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			touches[event.index] = event.position
			velocity = Vector2.ZERO
		else:
			touches.erase(event.index)
		_activity()
	elif event is InputEventScreenDrag:
		if not touches.has(event.index):
			return
		if touches.size() == 1:
			_drag(event.relative)
		elif touches.size() == 2:
			var ids := touches.keys()
			var previous: float = (touches[ids[0]] as Vector2).distance_to(touches[ids[1]])
			touches[event.index] = event.position
			var current: float = (touches[ids[0]] as Vector2).distance_to(touches[ids[1]])
			if previous > 8.0 and current > 8.0:
				target_zoom = clampf(target_zoom * previous / current, 0.55, 1.4)
			_activity()
		touches[event.index] = event.position
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			mouse_drag = event.pressed
			_activity()
		elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			target_zoom = clampf(target_zoom * (0.91 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.10), 0.55, 1.4)
			_activity()
	elif event is InputEventMouseMotion and mouse_drag:
		_drag(event.relative)
	elif event is InputEventMagnifyGesture:
		target_zoom = clampf(target_zoom / event.factor, 0.55, 1.4)
		_activity()

func cancel_gesture() -> void:
	touches.clear()
	mouse_drag = false
	velocity = Vector2.ZERO

func reset_view() -> void:
	cancel_gesture()
	if reset_tween != null:
		reset_tween.kill()
	yaw = wrapf(yaw, -PI, PI)
	reset_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	reset_tween.tween_property(self, "yaw", 0.0, 1.25)
	reset_tween.tween_property(self, "pitch", 0.1, 1.25)
	reset_tween.tween_property(self, "target_zoom", 1.0, 1.25)
	idle_seconds = 0.0
