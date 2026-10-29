extends Node
## Whole-world quality identity is retained; sampling and shadow cost change first.
signal quality_changed(label: String)
enum Preset { ADAPTIVE, CINEMATIC, BALANCED, BATTERY }
var preset := Preset.ADAPTIVE
var level := 2
var mean_frame_ms := 16.67
var frames := 0
var slow_seconds := 0.0
var fast_seconds := 0.0
var last_change := 0.0
var active := false
var elapsed := 0.0
var render_viewport: Viewport

func _ready() -> void:
	render_viewport = get_viewport()
	apply_level(2)

func set_preset(value: int) -> void:
	preset = clampi(value, 0, 3)
	apply_level([2, 2, 1, 0][preset])

func _process(delta: float) -> void:
	if not active:
		return
	elapsed += delta
	frames += 1
	mean_frame_ms = lerpf(mean_frame_ms, minf(delta * 1000.0, 250.0), 0.025)
	if preset != Preset.ADAPTIVE or elapsed < 8.0:
		return
	slow_seconds = slow_seconds + delta if mean_frame_ms > 20.5 else maxf(0.0, slow_seconds - delta)
	fast_seconds = fast_seconds + delta if mean_frame_ms < 15.5 else 0.0
	if elapsed - last_change > 12.0:
		if slow_seconds > 4.0 and level > 0:
			apply_level(level - 1)
		elif fast_seconds > 22.0 and level < 2:
			apply_level(level + 1)

func apply_level(value: int) -> void:
	level = clampi(value, 0, 2)
	slow_seconds = 0.0
	fast_seconds = 0.0
	last_change = elapsed
	# Viewport resolution scaling works on GLES3 as well as Vulkan.
	render_viewport.scaling_3d_scale = [0.70, 0.85, 1.0][level]
	render_viewport.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X][level]
	render_viewport.mesh_lod_threshold = [3.8, 2.5, 1.5][level]
	get_tree().call_group("key_light", "set", "shadow_enabled", level > 0)
	quality_changed.emit(["Battery", "Balanced", "Cinematic"][level])
