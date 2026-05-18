class_name EnemyBase extends CharacterBody2D

@export var target_tools: Array[ItemData.Id] = []
@export var move_speed: float = 30.0
@export var chase_speed_multiplier: float = 1.8
@export var detection_radius: float = 80.0
@export var attack_range: float = 24.0
@export var attack_damage: int = 10
@export var attack_cooldown: float = 1.5
@export var patrol_distance: float = 48.0
@export var prompt: String = ""

@onready var health_component: HealthComponent = $HealthComponent
@onready var state_machine: StateMachine = $StateMachine
@onready var detect_area: Area2D = $DetectArea
@onready var animated_sprite_2d: AnimatedSprite2D = $AnimatedSprite2D
@onready var hit_delay_timer: Timer = $HitDelayTimer
@onready var resource_spawners: Node2D = $ResourceSpawners

var _player: CharacterBody2D
var _start_position: Vector2
var _patrol_direction: int = 1
var _attack_timer: float = 0.0
var _idle_timer: float = 0.0

func _ready() -> void:
	EventSystem.data_save.connect(save_data)
	health_component.died.connect(_on_health_depleted)
	_start_position = global_position
	detect_area.body_entered.connect(_on_body_entered)
	detect_area.body_exited.connect(_on_body_exited)

	_patrol_direction = 1 if randf() > 0.5 else -1
	_idle_timer = randf_range(0.5, 2.0)

	_setup_states()
	load_data()

func _setup_states() -> void:
	state_machine.add_state("idle", _enter_idle, _process_idle)
	state_machine.add_state("patrol", _enter_patrol, _process_patrol)
	state_machine.add_state("chase", _enter_chase, _process_chase)
	state_machine.add_state("attack", _enter_attack, _process_attack)
	state_machine.add_state("hurt", _enter_hurt, _process_hurt)
	state_machine.add_state("death", _enter_death, _process_death)

func _process(delta: float) -> void:
	if health_component.is_dead():
		return
	_attack_timer = max(0, _attack_timer - delta)
	if _player:
		var dist = global_position.distance_to(_player.global_position)
		match state_machine.current_state():
			"idle", "patrol":
				if dist <= detection_radius:
					state_machine.transition_to("chase")
				elif state_machine.is_state("idle"):
					_idle_timer -= delta
					if _idle_timer <= 0:
						state_machine.transition_to("patrol")

func _physics_process(_delta: float) -> void:
	if health_component.is_dead():
		return
	move_and_slide()

func interactor(player: CharacterBody2D) -> void:
	if health_component.is_dead():
		return
	if player.equipped_item in target_tools or target_tools.is_empty():
		EventSystem.start_interaction()
		await _on_interaction_start(player)
		health_component.take_damage(_get_interaction_damage(player))
		if not health_component.is_dead():
			state_machine.transition_to("hurt")
		await player.animated_sprite_2d.animation_finished
		EventSystem.end_interaction()

func _on_interaction_start(player: CharacterBody2D) -> void:
	var tool: ToolResource = ItemData.get_item_resource(player.equipped_item)
	player.animated_sprite_2d.play(tool.use_tool_animation)
	hit_delay_timer.start(tool.hit_delay)
	await hit_delay_timer.timeout

func _get_interaction_damage(player: CharacterBody2D) -> int:
	var tool: ToolResource = ItemData.get_item_resource(player.equipped_item)
	return tool.damage

func save_data() -> void:
	var path := "user://enemy_" + str(name) + ".tres"
	var data := MinableSaveData.new()
	data.health = health_component.health
	ResourceSaver.save(data, path)

func load_data() -> void:
	var path := "user://enemy_" + str(name) + ".tres"
	if not ResourceLoader.exists(path):
		return
	var data := ResourceLoader.load(path) as MinableSaveData
	health_component.health = data.health
	if data.health == 0:
		get_parent().remove_child.call_deferred(self)

func _on_health_depleted() -> void:
	state_machine.transition_to("death")

func _on_body_entered(body: Node2D) -> void:
	if body is Player:
		_player = body

func _on_body_exited(body: Node2D) -> void:
	if body == _player:
		_player = null
		if not health_component.is_dead():
			state_machine.transition_to("patrol")

func _spawn_resources() -> void:
	for spawner: ResourceSpawner in resource_spawners.get_children():
		spawner.spawn()

func _face_movement() -> void:
	if abs(velocity.x) > 0.1:
		animated_sprite_2d.scale.x = 1 if velocity.x > 0 else -1

func _face_pos(pos: Vector2) -> void:
	var dx := pos.x - global_position.x
	if abs(dx) > 2.0:
		animated_sprite_2d.scale.x = 1 if dx > 0 else -1

## idle
func _enter_idle() -> void:
	animated_sprite_2d.play("idle")
	velocity = Vector2.ZERO
	_idle_timer = randf_range(0.5, 2.0)

func _process_idle(_delta: float) -> void:
	pass

## patrol
func _enter_patrol() -> void:
	animated_sprite_2d.play("run")
	velocity.x = move_speed * _patrol_direction
	_face_movement()

func _process_patrol(_delta: float) -> void:
	velocity.x = move_speed * _patrol_direction
	if abs(global_position.x - _start_position.x) > patrol_distance:
		_patrol_direction *= -1
		velocity.x = move_speed * _patrol_direction
	_face_movement()

## chase
func _enter_chase() -> void:
	animated_sprite_2d.play("run")

func _process_chase(_delta: float) -> void:
	if not _player:
		state_machine.transition_to("patrol")
		return
	var dist = global_position.distance_to(_player.global_position)
	if dist <= attack_range:
		velocity = Vector2.ZERO
		state_machine.transition_to("attack")
		return
	if dist > detection_radius * 1.5:
		state_machine.transition_to("patrol")
		return
	var dir_to_player = (_player.global_position - global_position).normalized()
	velocity = dir_to_player * move_speed * chase_speed_multiplier
	_face_pos(_player.global_position)

## attack
func _enter_attack() -> void:
	animated_sprite_2d.play("attack")
	velocity = Vector2.ZERO
	_attack_timer = attack_cooldown

func _process_attack(_delta: float) -> void:
	if not _player:
		state_machine.transition_to("patrol")
		return
	if global_position.distance_to(_player.global_position) > attack_range:
		state_machine.transition_to("chase")
		return
	_face_pos(_player.global_position)
	if _attack_timer <= 0:
		(_player as Player).health_component.take_damage(attack_damage)
		_attack_timer = attack_cooldown

## hurt
func _enter_hurt() -> void:
	animated_sprite_2d.play("hurt")
	velocity = Vector2.ZERO

func _process_hurt(_delta: float) -> void:
	if _player:
		_face_pos(_player.global_position)
	if not animated_sprite_2d.is_playing():
		state_machine.transition_to("chase" if _player else "patrol")

## death
func _enter_death() -> void:
	animated_sprite_2d.play("death")
	detect_area.monitoring = false
	collision_layer = 0
	velocity = Vector2.ZERO

func _process_death(_delta: float) -> void:
	if not animated_sprite_2d.is_playing():
		_spawn_resources()
		get_parent().remove_child.call_deferred(self)
