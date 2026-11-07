extends Node3D

const BattleModel = preload("res://scripts/battle_model.gd")
const Hud = preload("res://scripts/hud.gd")
const Campaign = preload("res://scripts/campaign.gd")
const Profile = preload("res://scripts/player_profile.gd")
const Sound = preload("res://scripts/sound.gd")
const Services = preload("res://scripts/services/game_services.gd")
const NativeProvider = preload("res://scripts/services/native_provider_bridge.gd")
var model := BattleModel.new()
var profile := Profile.new()
var sound: Node
var services: Node
var native_services: Object
var hud: Control
var camera: Camera3D
var player_kite: Node3D
var rival_kite: Node3D
var player_string: Array[MeshInstance3D] = []
var rival_string: Array[MeshInstance3D] = []
var player_tail: Array[MeshInstance3D] = []
var rival_tail: Array[MeshInstance3D] = []
var clash: MeshInstance3D
var materials := {}
var paused := false
var visual_time := 0.0
var rng := RandomNumberGenerator.new()
var fade_time := 0.0
var match_recorded := false
var cue_cooldown := 0.0
var city_meshes_before := 0
var city_meshes_after := 0
var input_armed := true
var campaign: RefCounted
var active_encounter := {}
var play_mode := "quick"
var match_summary := {}
var training_step := 0
var training_progress := 0.0
var sky_colors: ProceduralSkyMaterial
var sun_light: DirectionalLight3D

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Engine.max_fps = 60
	get_tree().auto_accept_quit = false
	profile.load_profile()
	campaign = Campaign.new(profile)
	sound = Sound.new()
	add_child(sound)
	services = Services.new()
	add_child(services)
	configure_native_services()
	rng.seed = 197
	build_lighting()
	build_city()
	batch_static_city()
	player_kite = make_kite(Color("24cabb"), Color("fcdf97"))
	rival_kite = make_kite(Color("f17a66"), Color("ffe1b1"))
	add_kite_label(player_kite, "YOU", Color("edfff6"))
	add_kite_label(rival_kite, "RIVAL", Color("ffe9dd"))
	player_string = make_rope(20, Color("fff7da"), 0.023)
	rival_string = make_rope(20, Color("f8b39d"), 0.023)
	player_tail = make_rope(10, Color("23a89c"), 0.055)
	rival_tail = make_rope(10, Color("ed6f5c"), 0.055)
	clash = sphere(Vector3.ZERO, 0.15, Color("ffdf74"))
	clash.material_override = material(Color("ffdf74"), true)
	clash.visible = false
	var canvas := CanvasLayer.new()
	add_child(canvas)
	hud = Hud.new()
	hud.model = model
	hud.profile = profile
	hud.services = services
	hud.campaign = campaign
	canvas.add_child(hud)
	hud.start_requested.connect(start_or_resume)
	hud.campaign_requested.connect(start_campaign_stage)
	hud.tournament_requested.connect(start_tournament)
	hud.quick_requested.connect(start_quick)
	hud.practice_requested.connect(start_practice)
	hud.continue_requested.connect(continue_result)
	hud.pause_requested.connect(toggle_pause)
	hud.home_requested.connect(return_home)
	hud.settings_changed.connect(apply_settings)
	hud.account_requested.connect(services.login)
	hud.erase_requested.connect(erase_progress)
	services.notice.connect(hud.notify_user)
	services.demo_reward_earned.connect(func(): hud.notify_user("Google TEST ad completed. Demo only: no saved reward was added."))
	if native_services != null and native_services.has_signal("test_ad_status"):
		native_services.test_ad_status.connect(hud.notify_user)
	apply_settings(false)
	update_visuals(0.0)
	if profile.last_error != "":
		hud.notify_user(profile.last_error)

func configure_native_services() -> void:
	# SDK methods are unavailable on desktop/older APKs; guest mode remains intact.
	if not Engine.has_singleton("KiteGoogleServices"):
		return
	native_services = Engine.get_singleton("KiteGoogleServices")
	var client_id := ""
	var path := "res://config/google_sign_in.json"
	if FileAccess.file_exists(path):
		var parser := JSON.new()
		if parser.parse(FileAccess.get_file_as_string(path)) == OK and parser.data is Dictionary:
			client_id = str(parser.data.get("server_client_id", ""))
	var can_configure: bool = native_services.has_java_method("configure_google_sign_in") if native_services.has_method("has_java_method") else native_services.has_method("configure_google_sign_in")
	if can_configure:
		native_services.configure_google_sign_in(client_id)
	# Real monetized ads stay disabled. Explicit TEST requests use separate gates.
	services.configure(NativeProvider.new(native_services), true, false)

func batch_static_city() -> void:
	# Merge static meshes by material once; gameplay objects stay independent.
	var meshes := find_children("*", "MeshInstance3D", true, false)
	var groups := {}
	city_meshes_before = meshes.size()
	for item in meshes:
		var instance := item as MeshInstance3D
		for surface_index in range(instance.mesh.get_surface_count()):
			var mat: Material = instance.material_override if instance.material_override != null else instance.mesh.surface_get_material(surface_index)
			if mat == null:
				continue
			var key := mat.get_instance_id()
			if not groups.has(key):
				var tool := SurfaceTool.new()
				tool.begin(Mesh.PRIMITIVE_TRIANGLES)
				tool.set_material(mat)
				groups[key] = tool
			groups[key].append_from(instance.mesh, surface_index, instance.global_transform)
		instance.visible = false
		instance.queue_free()
	for key in groups:
		var batch := MeshInstance3D.new()
		batch.mesh = groups[key].commit()
		batch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(batch)
	city_meshes_after = groups.size()

func add_kite_label(kite: Node3D, text_value: String, color: Color) -> void:
	var label := Label3D.new()
	label.text = text_value
	label.font_size = 48
	label.pixel_size = .012
	label.position = Vector3(0, 2.05, 0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = color
	label.no_depth_test = true
	kite.add_child(label)

func apply_settings(persist: bool = true) -> void:
	if persist and not profile.save():
		hud.notify_user(profile.last_error)
	sound.enabled = profile.data.sound and DisplayServer.get_name() != "headless"
	if not sound.enabled:
		sound.stream_player.stop()
	var colors := [Color("24cabb"), Color("f0a447"), Color("8b88e8"), Color("ef7a97"), Color("65afd8"), Color("efd66f")]
	for i in range(4):
		var face := player_kite.get_child(i) as MeshInstance3D
		face.material_override = material(colors[profile.data.skin] if i % 2 == 0 else Color("fcdf97"))
	hud.clear_input()

func erase_progress() -> void:
	var saved: bool = profile.reset_progress()
	campaign.clear_active_encounter()
	active_encounter.clear()
	match_summary.clear()
	services.clear_local_account()
	services.set_ad_consent(false)
	apply_settings(false)
	hud.notify_user("Local settings and progress have been reset." if saved else profile.last_error)

func return_home() -> void:
	campaign.clear_active_encounter()
	active_encounter.clear()
	match_summary.clear()
	hud.match_summary.clear()
	hud.active_encounter.clear()
	paused = false
	hud.paused = false
	hud.panel = ""
	hud.clear_input()
	model.state = "ready"
	model.contact = false
	services.set_in_battle(false)
	input_armed = false

func build_lighting() -> void:
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_colors = sky_material
	sky_material.sky_top_color = Color("5a91a5")
	sky_material.sky_horizon_color = Color("f5d0a0")
	sky_material.ground_bottom_color = Color("b88d6d")
	sky_material.ground_horizon_color = Color("f5d0a0")
	sky_material.sun_angle_max = 20.0
	sky.sky_material = sky_material
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("ffecd3")
	env.ambient_light_energy = 0.75
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.environment = env
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun_light = sun
	sun.rotation_degrees = Vector3(-32, -35, 0)
	sun.light_color = Color("ffe5b7")
	sun.light_energy = 1.25
	sun.shadow_enabled = false
	add_child(sun)
	camera = Camera3D.new()
	camera.position = Vector3(0, 17, 35)
	camera.fov = 60
	camera.far = 250
	add_child(camera)
	camera.look_at(Vector3(0, 13, -9))
	camera.current = true

func material(color: Color, unshaded: bool = false) -> StandardMaterial3D:
	var key := color.to_html() + str(unshaded)
	if materials.has(key):
		return materials[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 1.0
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	if unshaded:
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	materials[key] = mat
	return mat

func box(at: Vector3, dimensions: Vector3, color: Color, parent: Node = self) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = dimensions
	instance.mesh = mesh
	instance.position = at
	instance.material_override = material(color)
	parent.add_child(instance)
	return instance

func cylinder(at: Vector3, radius: float, height: float, color: Color, parent: Node = self) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 12
	instance.mesh = mesh
	instance.position = at
	instance.material_override = material(color)
	parent.add_child(instance)
	return instance

func sphere(at: Vector3, radius: float, color: Color, parent: Node = self) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2
	mesh.radial_segments = 12
	mesh.rings = 6
	instance.mesh = mesh
	instance.position = at
	instance.material_override = material(color)
	parent.add_child(instance)
	return instance

func build_city() -> void:
	box(Vector3(0, -1, -45), Vector3(170, 1, 180), Color("b19578"))
	var palette := [Color("c87556"), Color("dfb17a"), Color("c9907c"), Color("83a7a2"), Color("e2c28b"), Color("dd957b")]
	for row in range(5):
		for col in range(7):
			var x := float(col - 3) * 15.0 + rng.randf_range(-2.0, 2.0)
			var z := -14.0 - row * 18.0 + rng.randf_range(-3.0, 3.0)
			var h := rng.randf_range(4.0, 10.0)
			var width := rng.randf_range(8.0, 12.0)
			var depth := rng.randf_range(8.0, 12.0)
			var color: Color = palette[rng.randi_range(0, palette.size() - 1)]
			box(Vector3(x, h / 2.0, z), Vector3(width, h, depth), color)
			box(Vector3(x, h + 0.13, z), Vector3(width + 0.4, 0.28, depth + 0.4), color.lightened(0.22))
			box(Vector3(x, h + 0.5, z - depth / 2), Vector3(width, 0.8, 0.22), color)
			box(Vector3(x - width / 2, h + 0.5, z), Vector3(.22, .8, depth), color)
			box(Vector3(x + width / 2, h + 0.5, z), Vector3(.22, .8, depth), color)
			if (row + col) % 2 == 0:
				cylinder(Vector3(x + 1.5, h + 1.1, z), .85, 1.9, Color("344e50"))
				cylinder(Vector3(x + 1.5, h + 2.08, z), .9, .12, Color("233c3e"))
			if (row + col) % 3 == 0:
				box(Vector3(x - 2.0, h + 1, z - 1), Vector3(2.4, 2.0, 2.6), color.lightened(.10))
			for win in range(3):
				box(Vector3(x - width * .3 + win * width * .3, h * .55, z + depth / 2 + .03), Vector3(.9, 1.5, .07), Color("305559"))
	make_terrace(Vector3(-9, 0, 7), Color("ca8767"), true)
	make_terrace(Vector3(9, 0, 7), Color("d7b97c"), false)
	# Small flags and spare festival kites help ground the setting without assets.
	for i in range(12):
		var flag := make_triangle(Color("de7058") if i % 2 == 0 else Color("e7bb69"))
		flag.position = Vector3(-15.0 + i * 2.75, 4.6 + sin(i * .3) * .4, 12)
		flag.scale = Vector3.ONE * .4
	for i in range(7):
		var distant := make_kite(palette[i % palette.size()], Color("fce6b9"))
		distant.position = Vector3(rng.randf_range(-42, 42), rng.randf_range(22, 36), rng.randf_range(-80, -45))
		distant.scale = Vector3.ONE * rng.randf_range(.35, .6)
		distant.rotation.z = rng.randf_range(-.4, .4)

func make_terrace(at: Vector3, color: Color, is_player: bool) -> void:
	var h := 3.4
	box(at + Vector3(0, h / 2, 0), Vector3(13, h, 11), color)
	box(at + Vector3(0, h + .12, 0), Vector3(13.3, .24, 11.3), color.lightened(.2))
	box(at + Vector3(0, h + .6, -5.2), Vector3(13, 1.2, .35), color.lightened(.1))
	box(at + Vector3(-6.3 if is_player else 6.3, h + .6, 0), Vector3(.35, 1.2, 11), color)
	cylinder(at + Vector3(-4 if is_player else 4, h + 1.1, -3), 1.0, 2.0, Color("315454"))
	var anchor: Vector3 = BattleModel.PLAYER_ANCHOR if is_player else BattleModel.RIVAL_ANCHOR
	var shirt := Color("1aa59b") if is_player else Color("dd6e58")
	box(anchor + Vector3(0, -.3, .5), Vector3(.55, .85, .4), shirt)
	sphere(anchor + Vector3(0, .35, .5), .23, Color("b97d53"))
	box(anchor + Vector3(-.15, -.9, .5), Vector3(.2, .55, .2), Color("25464d"))
	box(anchor + Vector3(.15, -.9, .5), Vector3(.2, .55, .2), Color("25464d"))
	cylinder(anchor + Vector3(.35, -.1, .3), .15, .45, Color("edc77b")).rotation.z = PI / 2.0
	var sign_node := Label3D.new()
	sign_node.text = "PATANG CLUB" if is_player else "ROOFTOP RIVALS"
	sign_node.font_size = 52
	sign_node.pixel_size = .017
	sign_node.modulate = Color("fff0cf")
	sign_node.position = at + Vector3(0, 2.1, 5.56)
	add_child(sign_node)

func make_triangle(color: Color) -> MeshInstance3D:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_material(material(color))
	surface.add_vertex(Vector3(-1, 0, 0))
	surface.add_vertex(Vector3(1, 0, 0))
	surface.add_vertex(Vector3(0, -1.5, 0))
	surface.generate_normals()
	var result := MeshInstance3D.new()
	result.mesh = surface.commit()
	add_child(result)
	return result

func make_kite(first: Color, second: Color) -> Node3D:
	var root := Node3D.new()
	add_child(root)
	var points := [Vector3(0, 1.65, 0), Vector3(1.05, 0, 0), Vector3(0, -1.3, 0), Vector3(-1.05, 0, 0)]
	for i in range(4):
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		surface.set_material(material(first if i % 2 == 0 else second))
		surface.add_vertex(Vector3(0, .1, .16))
		surface.add_vertex(points[i])
		surface.add_vertex(points[(i + 1) % 4])
		surface.generate_normals()
		var face := MeshInstance3D.new()
		face.mesh = surface.commit()
		root.add_child(face)
	var spine := cylinder(Vector3(0, .15, .17), .018, 2.96, Color("6b5c43"), root)
	spine.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var bow := cylinder(Vector3(0, 0, .18), .016, 2.08, Color("6b5c43"), root)
	bow.rotation.z = PI / 2
	return root

func make_rope(count: int, color: Color, radius: float) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = 1.0
	mesh.radial_segments = 4
	for i in range(count):
		var segment := MeshInstance3D.new()
		segment.mesh = mesh
		segment.material_override = material(color, true)
		segment.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(segment)
		result.append(segment)
	return result

func set_beam(segment: MeshInstance3D, a: Vector3, b: Vector3) -> void:
	var difference := b - a
	var length := difference.length()
	if length < .0001:
		return
	segment.transform = Transform3D(Basis(Quaternion(Vector3.UP, difference / length)).scaled(Vector3(1, length, 1)), (a + b) * .5)

func update_rope(segments: Array[MeshInstance3D], anchor: Vector3, kite: Vector3, tension: float) -> void:
	for i in range(segments.size()):
		var t0 := float(i) / segments.size()
		var t1 := float(i + 1) / segments.size()
		var a := anchor.lerp(kite, t0)
		var b := anchor.lerp(kite, t1)
		# Small slack, kept within contact tolerance of the model's straight tether.
		a.y -= sin(t0 * PI) * .3 * (1.0 - tension)
		b.y -= sin(t1 * PI) * .3 * (1.0 - tension)
		set_beam(segments[i], a, b)

func update_tail(segments: Array[MeshInstance3D], root: Node3D, phase: float) -> void:
	var base := root.to_global(Vector3(0, -1.3, 0))
	for i in range(segments.size()):
		var t0 := float(i) / segments.size()
		var t1 := float(i + 1) / segments.size()
		var a := base + Vector3(sin(visual_time * 4.0 + t0 * 7.0 + phase) * t0 * .55, -t0 * 2.5, t0 * .35)
		var b := base + Vector3(sin(visual_time * 4.0 + t1 * 7.0 + phase) * t1 * .55, -t1 * 2.5, t1 * .35)
		set_beam(segments[i], a, b)

func _physics_process(dt: float) -> void:
	if model.state == "playing" and not paused:
		if not input_armed:
			if Input.is_anything_pressed():
				return
			input_armed = true
		var direction: Vector2 = hud.joystick
		direction.x += float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT))
		direction.y += float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN)) - float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP))
		var pulling: bool = hud.pull_held or Input.is_physical_key_pressed(KEY_SPACE)
		var releasing: bool = hud.release_held or Input.is_physical_key_pressed(KEY_SHIFT)
		if play_mode == "training":
			# Guided practice cannot kill either kite or expire; it never awards progress.
			model.player_health = 100.0
			model.rival_health = 100.0
			model.time = minf(model.time, 110.0)
		model.step(direction, pulling, releasing, dt)
		if play_mode == "training":
			update_training(direction, pulling, releasing, dt)
		if "gust_warning" in model.events and cue_cooldown <= 0:
			sound.play_cue("gust")
			cue_cooldown = .22
		elif "clash" in model.events and cue_cooldown <= 0:
			sound.play_cue("clash")
			cue_cooldown = .08
		if "clean_cut" in model.events and cue_cooldown <= 0:
			sound.play_cue("cut")
			cue_cooldown = .22
			if profile.data.haptics:
				Input.vibrate_handheld(18)
		if model.state == "finished" and not match_recorded:
			match_recorded = true
			if play_mode != "training":
				match_summary = campaign.record_result(model)
				profile.record_match(model.result, model.score)
			hud.match_summary = match_summary
			services.set_in_battle(false)
			sound.play_cue("win" if model.result == "win" else "loss")
			hud.clear_input()
			if profile.last_error != "":
				hud.notify_user(profile.last_error)

func _process(dt: float) -> void:
	cue_cooldown = maxf(0, cue_cooldown - dt)
	if not paused and not profile.data.reduced_motion:
		visual_time += dt
	update_visuals(dt)

func update_visuals(dt: float) -> void:
	if player_kite == null:
		return
	player_kite.position = model.player
	rival_kite.position = model.rival
	player_kite.rotation = Vector3(sin(visual_time * 2.0) * .08, .05, -model.player_velocity.x * .065 + sin(visual_time) * .04)
	rival_kite.rotation = Vector3(sin(visual_time * 2.1) * .08, -.05, -model.rival_velocity.x * .065)
	if model.state == "finished" and not profile.data.reduced_motion:
		fade_time += dt if not paused else 0.0
		var falling := rival_kite if model.result == "win" else player_kite
		falling.position.y -= minf(fade_time * 1.4, 13.0)
		falling.position.x += sin(fade_time) * fade_time * .5
		falling.rotation.z += fade_time
	update_rope(player_string, BattleModel.PLAYER_ANCHOR, player_kite.position, model.player_tension)
	update_rope(rival_string, BattleModel.RIVAL_ANCHOR, rival_kite.position, model.rival_tension)
	for segment in player_string:
		segment.visible = not (model.state == "finished" and model.result in ["loss", "draw"])
	for segment in rival_string:
		segment.visible = not (model.state == "finished" and model.result in ["win", "draw"])
	update_tail(player_tail, player_kite, 0)
	update_tail(rival_tail, rival_kite, 2)
	clash.visible = model.contact and model.state == "playing"
	clash.position = model.clash_position
	clash.scale = Vector3.ONE * (1.0 + sin(visual_time * 25.0) * .4)

func start_or_resume() -> void:
	if paused:
		paused = false
		hud.paused = false
		hud.panel = ""
		hud.clear_input()
		input_armed = false
		services.set_in_battle(true)
	else:
		start_quick()

func start_practice() -> void:
	campaign.clear_active_encounter()
	play_mode = "training"
	training_step = 0
	training_progress = 0.0
	begin_encounter({"id": "training", "title": "Guided practice", "rival": "Mira", "style": "sweeper", "chapter": 0, "seed": 101, "difficulty": 0, "wind_strength": .25, "gust_strength": 0.0, "tip": "Move the thumb pad to steer. This practice has no losses or rewards."})
	hud.training_text = "1 / 3   STEER: move the thumb pad for two seconds"

func update_training(direction: Vector2, pulling: bool, releasing: bool, dt: float) -> void:
	if training_step == 0:
		if direction.length() > .2:
			training_progress += dt
		if training_progress >= 2.0:
			training_step = 1
			training_progress = 0.0
			hud.training_text = "2 / 3   CROSS STRINGS, then hold PULL in the green zone"
	elif training_step == 1:
		if model.contact and pulling and not releasing and model.player_tension >= .4 and model.player_tension <= .82:
			training_progress += dt
		if training_progress >= .8:
			training_step = 2
			training_progress = 0.0
			hud.training_text = "3 / 3   RELEASE: let line out until tension falls below 30%"
	elif training_step == 2 and releasing and model.player_tension <= .3:
		training_step = 3
		hud.training_text = ""
		model.finish("win", "training")

func start_quick() -> void:
	campaign.clear_active_encounter()
	play_mode = "quick"
	begin_encounter({"id": "quick", "title": "Quick duel", "rival": "Rooftop challenger", "chapter": 0, "seed": 23 + profile.data.matches * 17, "difficulty": profile.data.difficulty, "tip": "Cross lines. Sweep above your rival. Ease off before red."})

func start_campaign_stage(index: int) -> void:
	var encounter: Dictionary = campaign.begin_stage(index)
	if encounter.is_empty():
		hud.notify_user("Win the previous rooftop to unlock this rival.")
		return
	play_mode = "campaign"
	begin_encounter(encounter)

func start_tournament() -> void:
	var encounter: Dictionary = campaign.begin_tournament()
	if encounter.is_empty():
		hud.notify_user("The cup could not start. Check your saved progress.")
		return
	play_mode = "tournament"
	begin_encounter(encounter)

func continue_result() -> void:
	if play_mode == "tournament" and campaign.has_active_tournament():
		var encounter: Dictionary = campaign.next_tournament_encounter()
		if not encounter.is_empty():
			begin_encounter(encounter)
			return
	elif play_mode == "campaign":
		var index: int = int(active_encounter.get("index", 0))
		if model.result == "win" and index < 11:
			index += 1
		start_campaign_stage(index)
		return
	return_home()

func begin_encounter(encounter: Dictionary) -> void:
	hud.training_text = ""
	active_encounter = encounter.duplicate(true)
	match_summary.clear()
	hud.active_encounter = active_encounter
	hud.match_summary = {}
	hud.play_mode = play_mode
	hud.panel = ""
	hud.clear_input()
	paused = false
	hud.paused = false
	input_armed = false
	model.reset(int(encounter.get("seed", 23)), int(encounter.get("difficulty", 1)))
	model.configure_encounter(encounter)
	match_recorded = false
	fade_time = 0.0
	for child in rival_kite.get_children():
		if child is Label3D:
			child.text = str(encounter.get("rival", "RIVAL")).to_upper()
	var chapter: int = clampi(int(encounter.get("chapter", 0)), 0, 3)
	sky_colors.sky_top_color = [Color("5a91a5"), Color("8fb9c5"), Color("66849e"), Color("536983")][chapter]
	sky_colors.sky_horizon_color = [Color("f5d0a0"), Color("fbe9c1"), Color("e3bf9c"), Color("efa68b")][chapter]
	sun_light.light_color = [Color("ffe5b7"), Color("fff4da"), Color("dedfec"), Color("ffbf92")][chapter]
	var rival_color: Color = [Color("f17a66"), Color("d9aa43"), Color("8496df"), Color("f1b5ca")][chapter]
	for i in range(4):
		(rival_kite.get_child(i) as MeshInstance3D).material_override = material(rival_color if i % 2 == 0 else Color("ffe1b1"))
	sound.play_cue("start")
	hud.notify_user(str(encounter.get("rival", "Rival")) + ": " + str(encounter.get("tip", "Pull through a crossing, then ease the line.")))
	if not profile.data.tutorial_seen:
		profile.data.tutorial_seen = true
		profile.save()
	services.set_in_battle(true)

func toggle_pause() -> void:
	if model.state == "playing":
		paused = not paused
		hud.paused = paused
		hud.panel = ""
		hud.clear_input()
		input_armed = false

func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED] and hud != null and model.state == "playing":
		paused = true
		hud.paused = true
		hud.clear_input()
		input_armed = false
		sound.stream_player.stop()
	elif what == NOTIFICATION_WM_GO_BACK_REQUEST and hud != null:
		if model.state == "ready" and hud.panel == "":
			get_tree().quit()
		else:
			hud.back()
	elif what == NOTIFICATION_WM_CLOSE_REQUEST:
		get_tree().quit()
