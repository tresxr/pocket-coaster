extends Node3D
## Offline geometry, bounded instance batches and a small native presentation layer.
const OrbitCamera = preload("res://scripts/orbit_camera.gd")
const QualityController = preload("res://scripts/quality.gd")
const TERRAIN_SHADER = preload("res://shaders/terrain.gdshader")
const WATER_SHADER = preload("res://shaders/water.gdshader")
const FOLIAGE_SHADER = preload("res://shaders/foliage.gdshader")
const INLAY_SHADER = preload("res://shaders/inlay.gdshader")
const ASSETS := ["world", "tidalsea", "skyray", "tree0", "tree1", "tree2", "rock", "grass"]
const CONFIG_PATH := "user://aureole.cfg"

var camera: Camera3D
var quality: Node
var world := Node3D.new()
var sea: Node3D
var sky_ray: Node3D
var cloud_nodes: Array[Node3D] = []
var batch_nodes: Array[MultiMeshInstance3D] = []
var ui := CanvasLayer.new()
var loader: Control
var hint: Label
var status_label: Label
var settings: PanelContainer
var quality_select: OptionButton
var auto_toggle: CheckButton
var loaded := false
var simulation_time := 0.0
var ui_time := 0.0
var loading_text: Label
var library: Dictionary = {}
var test_mode := false
var terrain_material := ShaderMaterial.new()
var water_material := ShaderMaterial.new()
var foliage_material := ShaderMaterial.new()
var key_light: DirectionalLight3D
var inlay_material := ShaderMaterial.new()
var orbital_motes: MultiMesh

func _ready() -> void:
	if OS.has_feature("android"):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	get_tree().auto_accept_quit = false
	Engine.max_fps = 60
	OS.low_processor_usage_mode = false
	test_mode = "--smoke-test" in OS.get_cmdline_user_args()
	terrain_material.shader = TERRAIN_SHADER
	water_material.shader = WATER_SHADER
	foliage_material.shader = FOLIAGE_SHADER
	inlay_material.shader = INLAY_SHADER
	_create_environment()
	world.name = "MiniatureWorld"
	add_child(world)
	camera = OrbitCamera.new()
	camera.name = "OrbitCamera"
	add_child(camera)
	camera.interacted.connect(_on_interaction)
	quality = QualityController.new()
	add_child(quality)
	quality.quality_changed.connect(_on_quality_changed)
	_create_interface()
	_restore()
	if "--capture" in OS.get_cmdline_user_args():
		get_window().size = Vector2i(720, 1280) if "--portrait" in OS.get_cmdline_user_args() else Vector2i(1200, 1000)
	await _load_world()

func _create_environment() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_material := ShaderMaterial.new()
	sky_material.shader = preload("res://shaders/space.gdshader")
	sky.sky_material = sky_material
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.55, 0.64, 0.72)
	environment.ambient_light_energy = 0.38
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var env_node := WorldEnvironment.new()
	env_node.environment = environment
	add_child(env_node)
	_light("Sun / honey softbox", Vector3(-48, -32, -18), Color(1.0, 0.89, 0.75), 1.16, true)
	_light("Fill / lagoon bounce", Vector3(18, 58, 12), Color(0.49, 0.70, 0.83), 0.42, false)
	_light("Rim / lunar silk", Vector3(-24, 155, 30), Color(0.65, 0.75, 1.0), 0.74, false)
	_create_stars()
	_create_orbital_motes()

func _create_orbital_motes() -> void:
	var mesh := SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.0
	mesh.radial_segments = 6
	mesh.rings = 3
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	mesh.material = material
	orbital_motes = MultiMesh.new()
	orbital_motes.transform_format = MultiMesh.TRANSFORM_3D
	orbital_motes.use_colors = true
	orbital_motes.mesh = mesh
	orbital_motes.instance_count = 18
	for i in 18:
		orbital_motes.set_instance_color(i, Color(0.63, 0.76, 0.70) if i % 3 else Color(0.78, 0.52, 0.28))
	var node := MultiMeshInstance3D.new()
	node.multimesh = orbital_motes
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)

func _light(light_name: String, angles: Vector3, color: Color, energy: float, shadows: bool) -> void:
	var light := DirectionalLight3D.new()
	light.name = light_name.replace("/", "_")
	light.rotation_degrees = angles
	light.light_color = color
	light.light_energy = energy
	light.shadow_enabled = shadows
	if shadows:
		key_light = light
		light.add_to_group("key_light")
		light.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
		light.directional_shadow_max_distance = 65.0
		light.shadow_bias = 0.025
		light.shadow_normal_bias = 0.5
		light.directional_shadow_pancake_size = 12.0
	add_child(light)

func _create_stars() -> void:
	var random := RandomNumberGenerator.new()
	random.seed = 7041
	var mesh := SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.0
	mesh.radial_segments = 6
	mesh.rings = 3
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	mesh.material = material
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = 210
	for i in mm.instance_count:
		var p := Vector3(random.randf_range(-46, 46), random.randf_range(-36, 36), random.randf_range(-38, -16))
		var size := random.randf_range(0.008, 0.026)
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * size), p))
		var strength := random.randf_range(0.18, 0.63)
		mm.set_instance_color(i, Color(strength * 0.77, strength * 0.85, strength, 1.0))
	var node := MultiMeshInstance3D.new()
	node.multimesh = mm
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)

func _load_world() -> void:
	for asset in ASSETS:
		var path := "res://assets/generated/%s.glb" % asset
		var result := ResourceLoader.load_threaded_request(path, "PackedScene")
		if result != OK:
			_load_failed("Could not open " + asset)
			return
	for index in ASSETS.size():
		var asset: String = ASSETS[index]
		var path := "res://assets/generated/%s.glb" % asset
		while ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			loading_text.text = "Gathering the archipelago  ·  %d%%" % int(100.0 * index / ASSETS.size())
			await get_tree().process_frame
		if ResourceLoader.load_threaded_get_status(path) != ResourceLoader.THREAD_LOAD_LOADED:
			_load_failed("Could not read " + asset)
			return
		library[asset] = ResourceLoader.load_threaded_get(path)
		await get_tree().process_frame
	var land: Node3D = library.world.instantiate()
	world.add_child(land)
	_replace_materials(land)
	sea = library.tidalsea.instantiate()
	world.add_child(sea)
	_replace_materials(sea)
	sky_ray = library.skyray.instantiate()
	world.add_child(sky_ray)
	var manifest_file := FileAccess.open("res://assets/generated/world_manifest.json", FileAccess.READ)
	if manifest_file == null:
		_load_failed("The atlas is missing")
		return
	var parsed = JSON.parse_string(manifest_file.get_as_text())
	if not parsed is Dictionary or not parsed.has("instances"):
		_load_failed("The atlas could not be read")
		return
	var grouped: Dictionary = {}
	for instance in parsed.instances:
		if not grouped.has(instance.kind):
			grouped[instance.kind] = []
		grouped[instance.kind].append(instance)
	for kind in grouped:
		_create_instance_batch(kind, grouped[kind])
		await get_tree().process_frame
	_create_clouds()
	loaded = true
	quality.active = true
	loading_text.text = "Welcome to the quiet."
	var tween := create_tween()
	tween.tween_property(loader, "modulate:a", 0.0, 1.2)
	tween.tween_callback(loader.queue_free)
	print("AUREOLE_READY instances=%d static_batches=%d renderer=%s" % [parsed.instances.size(), land.get_child_count(), RenderingServer.get_current_rendering_method()])
	if test_mode:
		await _run_smoke_test()
	if "--capture" in OS.get_cmdline_user_args():
		print("AUREOLE_CAPTURE_VIEW size=", get_window().size, " canvas=", get_viewport().get_visible_rect().size)
		camera.automatic_orbit = false
		if "--close" in OS.get_cmdline_user_args():
			camera.target_zoom = 0.72
			camera.zoom = 0.72
			camera.pitch = 0.22
		if "--reverse" in OS.get_cmdline_user_args():
			camera.yaw = PI
		quality.set_preset(1)
		# Wait for the real launch transition at every frame rate, including CI.
		await tween.finished
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		_capture_output()

func _capture_output() -> void:
	var path := OS.get_environment("AUREOLE_CAPTURE_PATH")
	if path.is_empty():
		path = "user://aureole-hero.png"
	var result := get_viewport().get_texture().get_image().save_png(path)
	print("AUREOLE_CAPTURE ", path, " result=", result)
	get_tree().quit(0 if result == OK else 1)

func _replace_materials(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_node := node as MeshInstance3D
		for surface in mesh_node.mesh.get_surface_count():
			var material := mesh_node.mesh.surface_get_material(surface)
			if material == null:
				continue
			if material.resource_name == "sand":
				mesh_node.set_surface_override_material(surface, terrain_material)
			elif material.resource_name == "water":
				mesh_node.set_surface_override_material(surface, water_material)
			elif material.resource_name == "light":
				mesh_node.set_surface_override_material(surface, inlay_material)
			elif material is StandardMaterial3D and material.resource_name == "ivory":
				# Sky-ray wings are thin sculpted surfaces; preserve both sides.
				material.cull_mode = BaseMaterial3D.CULL_DISABLED
	for child in node.get_children():
		_replace_materials(child)

func _mesh_parts(node: Node, transform: Transform3D = Transform3D.IDENTITY) -> Array:
	var parts: Array = []
	if node is Node3D:
		transform *= node.transform
	if node is MeshInstance3D:
		parts.append({"mesh": node.mesh, "transform": transform})
	for child in node.get_children():
		parts.append_array(_mesh_parts(child, transform))
	return parts

func _create_instance_batch(kind: String, entries: Array) -> void:
	if not library.has(kind):
		return
	var source: Node3D = library[kind].instantiate()
	var parts := _mesh_parts(source)
	for part in parts:
		var mesh: Mesh = part.mesh
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = entries.size()
		for i in entries.size():
			var entry: Dictionary = entries[i]
			var normal := Vector3(entry.n[0], entry.n[1], entry.n[2]).normalized()
			var basis := Basis(Quaternion(Vector3.UP, normal)) * Basis(Vector3.UP, entry.yaw)
			basis = basis.scaled(Vector3.ONE * entry.scale)
			var placement := Transform3D(basis, Vector3(entry.p[0], entry.p[1], entry.p[2]))
			mm.set_instance_transform(i, placement * part.transform)
		var node := MultiMeshInstance3D.new()
		node.name = kind + "_instances"
		node.multimesh = mm
		for surface in mesh.get_surface_count():
			var material := mesh.surface_get_material(surface)
			if material != null and material.resource_name == "leaf":
				node.material_override = foliage_material
		if kind in ["grass", "rock"]:
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		world.add_child(node)
		batch_nodes.append(node)
	source.free()

func _create_clouds() -> void:
	var cloud_material := StandardMaterial3D.new()
	cloud_material.albedo_color = Color(0.57, 0.67, 0.72)
	cloud_material.roughness = 0.95
	var mesh := SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.0
	mesh.radial_segments = 16
	mesh.rings = 8
	mesh.material = cloud_material
	var random := RandomNumberGenerator.new()
	random.seed = 919
	var centers := [Vector3(-4.9, 1.1, 1), Vector3(3.8, -2.2, 2.4), Vector3(1.2, 5.1, -3), Vector3(-2.6, -4.2, -1)]
	for center in centers:
		var cloud := Node3D.new()
		cloud.position = center
		cloud.set_meta("anchor", center)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = 7
		for i in 7:
			var p := Vector3((i - 3) * 0.13, random.randf_range(-0.025, 0.04), random.randf_range(-0.1, 0.1))
			var scale := Vector3(random.randf_range(0.18, 0.29), random.randf_range(0.07, 0.13), random.randf_range(0.13, 0.2))
			mm.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(scale), p))
		var node := MultiMeshInstance3D.new()
		node.multimesh = mm
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		cloud.add_child(node)
		add_child(cloud)
		cloud_nodes.append(cloud)

func _process(delta: float) -> void:
	if not loaded:
		return
	simulation_time += minf(delta, 0.05)
	ui_time += delta
	for i in orbital_motes.instance_count:
		var angle := i * TAU / 18.0 + simulation_time * 0.025
		var p := Vector3(cos(angle) * 5.6, sin(angle) * 2.45 + 0.3, sin(angle) * 3.0)
		var size := 0.012 + 0.004 * sin(simulation_time * 0.8 + i)
		orbital_motes.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * size), p))
	# Fit the one shadow frustum to the miniature instead of wasting texels on space.
	var shadow_range := camera.position.length() + 6.5
	if key_light != null and absf(key_light.directional_shadow_max_distance - shadow_range) > 0.5:
		key_light.directional_shadow_max_distance = shadow_range
	if sky_ray != null:
		sky_ray.position = Vector3(sin(simulation_time * 0.19) * 0.18, sin(simulation_time * 0.37) * 0.09, 0)
		sky_ray.rotation.z = sin(simulation_time * 0.27) * 0.035
	for i in cloud_nodes.size():
		var cloud := cloud_nodes[i]
		var anchor: Vector3 = cloud.get_meta("anchor")
		cloud.position = anchor + Vector3(sin(simulation_time * 0.055 + i) * 0.24, sin(simulation_time * 0.13 + i) * 0.055, 0)
	if is_instance_valid(hint):
		hint.modulate.a = move_toward(hint.modulate.a, 0.0 if ui_time > 9.0 else 0.65, delta * 0.4)
	if settings.visible:
		status_label.text = "%s · %.1f ms / frame" % [["Battery", "Balanced", "Cinematic"][quality.level], quality.mean_frame_ms]

func _create_interface() -> void:
	ui.layer = 10
	add_child(ui)
	var full_screen := Control.new()
	full_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	full_screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(full_screen)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	full_screen.add_child(root)
	_apply_safe_area(root)
	get_viewport().size_changed.connect(func(): _apply_safe_area(root))
	var title := Label.new()
	title.text = "AUREOLE"
	title.position = Vector2(50, 37)
	title.add_theme_font_override("font", preload("res://assets/cormorant.ttf"))
	title.add_theme_font_size_override("font_size", 46)
	title.add_theme_color_override("font_color", Color(0.84, 0.82, 0.70, 0.86))
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "A  W O R L D  B E T W E E N  T I D E S"
	subtitle.position = Vector2(52, 93)
	subtitle.add_theme_font_size_override("font_size", 11)
	subtitle.add_theme_color_override("font_color", Color(0.61, 0.69, 0.71, 0.68))
	root.add_child(subtitle)
	var settings_button := Button.new()
	settings_button.text = "· · ·"
	settings_button.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	settings_button.position = Vector2(-105, 38)
	settings_button.size = Vector2(64, 56)
	settings_button.flat = true
	settings_button.tooltip_text = "World settings"
	settings_button.add_theme_font_size_override("font_size", 30)
	settings_button.add_theme_color_override("font_color", Color(0.76, 0.79, 0.73, 0.8))
	settings_button.pressed.connect(_toggle_settings)
	root.add_child(settings_button)
	hint = Label.new()
	hint.text = "DRAG TO EXPLORE   ·   PINCH TO WANDER CLOSER"
	hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hint.offset_left = -260
	hint.offset_right = 260
	hint.offset_top = -69
	hint.offset_bottom = -40
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", Color(0.63, 0.73, 0.72))
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hint)
	_create_settings(root)
	loader = Control.new()
	loader.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	full_screen.add_child(loader)
	var background := ColorRect.new()
	background.color = Color(0.025, 0.023, 0.044)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	loader.add_child(background)
	var loading_title := Label.new()
	loading_title.text = "A U R E O L E"
	loading_title.add_theme_font_override("font", preload("res://assets/cormorant.ttf"))
	loading_title.add_theme_font_size_override("font_size", 56)
	loading_title.add_theme_color_override("font_color", Color(0.84, 0.82, 0.70))
	loading_title.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	loading_title.offset_left = -270
	loading_title.offset_right = 270
	loading_title.offset_top = -55
	loading_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	loader.add_child(loading_title)
	loading_text = Label.new()
	loading_text.text = "Gathering the archipelago"
	loading_text.add_theme_font_size_override("font_size", 13)
	loading_text.add_theme_color_override("font_color", Color(0.55, 0.65, 0.66))
	loading_text.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	loading_text.offset_left = -300
	loading_text.offset_right = 300
	loading_text.offset_top = 25
	loading_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	loader.add_child(loading_text)

func _apply_safe_area(root: Control) -> void:
	if not OS.has_feature("android"):
		return
	var safe := DisplayServer.get_display_safe_area()
	var screen_size := Vector2(DisplayServer.window_get_size())
	if screen_size.x <= 0.0 or screen_size.y <= 0.0 or safe.size.x <= 0:
		return
	var scale := get_viewport().get_visible_rect().size / screen_size
	# Controls retain physical touch-target sizes on high-density Android panels.
	var density := clampf(DisplayServer.screen_get_dpi() / 160.0, 1.0, 4.0)
	var ui_scale := maxf(1.0, density * scale.x)
	root.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	root.position = Vector2(safe.position) * scale
	root.scale = Vector2.ONE * ui_scale
	root.size = Vector2(safe.size) * scale / ui_scale

func _create_settings(root: Control) -> void:
	settings = PanelContainer.new()
	settings.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	settings.offset_left = -346
	settings.offset_right = -24
	settings.offset_top = 112
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.045, 0.065, 0.08, 0.97)
	style.border_color = Color(0.22, 0.32, 0.32, 0.7)
	style.set_border_width_all(1)
	style.set_corner_radius_all(16)
	style.content_margin_left = 24
	style.content_margin_right = 24
	style.content_margin_top = 23
	style.content_margin_bottom = 23
	settings.add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	settings.add_child(box)
	var label := Label.new()
	label.text = "The observatory"
	label.add_theme_font_override("font", preload("res://assets/cormorant.ttf"))
	label.add_theme_font_size_override("font_size", 29)
	box.add_child(label)
	quality_select = OptionButton.new()
	for item in ["Adaptive quality", "Cinematic", "Balanced", "Battery saver"]:
		quality_select.add_item(item)
	quality_select.custom_minimum_size.y = 48
	quality_select.item_selected.connect(func(value: int): quality.set_preset(value); _save())
	box.add_child(quality_select)
	auto_toggle = CheckButton.new()
	auto_toggle.text = "Slow orbit when idle"
	auto_toggle.button_pressed = true
	auto_toggle.custom_minimum_size.y = 48
	auto_toggle.toggled.connect(func(value: bool): camera.automatic_orbit = value; _save())
	box.add_child(auto_toggle)
	var reset := Button.new()
	reset.text = "Return to the first view"
	reset.custom_minimum_size.y = 48
	reset.pressed.connect(func(): camera.reset_view(); _toggle_settings(); _save())
	box.add_child(reset)
	status_label = Label.new()
	status_label.add_theme_font_size_override("font_size", 12)
	status_label.add_theme_color_override("font_color", Color(0.55, 0.67, 0.67))
	box.add_child(status_label)
	settings.hide()
	root.add_child(settings)

func _toggle_settings() -> void:
	settings.visible = not settings.visible
	camera.enabled = not settings.visible
	camera.cancel_gesture()
	_save()

func _on_quality_changed(_label: String) -> void:
	for batch in batch_nodes:
		batch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if quality.level == 0 or batch.name.begins_with("rock") or batch.name.begins_with("grass") else GeometryInstance3D.SHADOW_CASTING_SETTING_ON

func _on_interaction() -> void:
	ui_time = maxf(ui_time, 7.0)

func _load_failed(message: String) -> void:
	push_error("Aureole loading failed: " + message)
	loading_text.text = "The world could not be opened.\nPlease close and reopen Aureole."
	if test_mode:
		get_tree().quit(1)

func _save() -> void:
	if camera == null or quality == null:
		return
	var config := ConfigFile.new()
	config.set_value("view", "yaw", camera.yaw)
	config.set_value("view", "pitch", camera.pitch)
	config.set_value("view", "zoom", camera.target_zoom)
	config.set_value("view", "auto", camera.automatic_orbit)
	config.set_value("graphics", "preset", quality.preset)
	var result := config.save(CONFIG_PATH)
	if result != OK:
		push_warning("Could not save settings: " + str(result))

func _restore() -> void:
	if "--capture" in OS.get_cmdline_user_args() or test_mode:
		return
	var config := ConfigFile.new()
	if config.load(CONFIG_PATH) != OK:
		return
	camera.yaw = float(config.get_value("view", "yaw", 0.0))
	camera.pitch = clampf(float(config.get_value("view", "pitch", 0.1)), -1.15, 1.15)
	camera.target_zoom = clampf(float(config.get_value("view", "zoom", 1.0)), 0.55, 1.4)
	camera.zoom = camera.target_zoom
	camera.automatic_orbit = bool(config.get_value("view", "auto", true))
	quality.set_preset(int(config.get_value("graphics", "preset", 0)))
	quality_select.select(quality.preset)
	auto_toggle.set_pressed_no_signal(camera.automatic_orbit)

func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT]:
		_save()
		if camera != null:
			camera.cancel_gesture()
		if quality != null:
			quality.active = false
	elif what in [NOTIFICATION_APPLICATION_RESUMED, NOTIFICATION_APPLICATION_FOCUS_IN]:
		if quality != null:
			quality.active = loaded
			quality.slow_seconds = 0.0
			quality.fast_seconds = 0.0
	elif what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if is_instance_valid(settings) and settings.visible:
			_toggle_settings()
		else:
			_save()
			get_tree().quit()
	elif what == NOTIFICATION_WM_CLOSE_REQUEST:
		_save()
		get_tree().quit()

func _run_smoke_test() -> void:
	assert(batch_nodes.size() == 8, "Expected eight reusable material batches")
	assert(world.get_child_count() >= 11, "World failed to assemble")
	assert(camera.position.is_finite(), "Camera transform is invalid")
	# Exercise two-touch pinch, release ordering, quality hysteresis and lifecycle.
	var touch := InputEventScreenTouch.new()
	touch.index = 3; touch.position = Vector2(400, 400); touch.pressed = true
	camera._unhandled_input(touch)
	touch = InputEventScreenTouch.new()
	touch.index = 8; touch.position = Vector2(600, 400); touch.pressed = true
	camera._unhandled_input(touch)
	var drag := InputEventScreenDrag.new()
	drag.index = 8; drag.position = Vector2(800, 400); drag.relative = Vector2(200, 0)
	camera._unhandled_input(drag)
	assert(camera.target_zoom < 1.0, "Pinch failed to zoom")
	camera.cancel_gesture()
	assert(camera.touches.is_empty(), "Touch state survived cancellation")
	camera.reset_view()
	quality.set_preset(3)
	assert(quality.level == 0 and get_viewport().scaling_3d_scale < 0.75)
	quality.set_preset(0)
	quality.elapsed = 30.0
	quality.last_change = 0.0
	quality.mean_frame_ms = 30.0
	quality.slow_seconds = 4.1
	quality._process(0.03)
	assert(quality.level == 1, "Adaptive quality failed to respond")
	quality.elapsed = 60.0
	quality.last_change = 0.0
	quality.mean_frame_ms = 16.67
	quality.fast_seconds = 22.1
	quality._process(1.0 / 60.0)
	assert(quality.level == 2, "Adaptive quality failed to recover at the 60 Hz cap")
	quality.apply_level(2)
	_notification(NOTIFICATION_APPLICATION_PAUSED)
	assert(not quality.active)
	_notification(NOTIFICATION_APPLICATION_RESUMED)
	assert(quality.active)
	assert(FileAccess.file_exists(CONFIG_PATH))
	print("AUREOLE_SMOKE_TEST_PASS")
	get_tree().quit()
