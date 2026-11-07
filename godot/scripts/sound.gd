extends Node
## Small original synthesized cues. No external samples or microphone access.
var enabled := true
var stream_player: AudioStreamPlayer
var cues := {}

func _ready() -> void:
	stream_player = AudioStreamPlayer.new()
	stream_player.volume_db = -12
	add_child(stream_player)
	cues["tap"] = make_tone([660.0], .08)
	cues["gust"] = make_tone([220.0, 329.63], .22)
	cues["clash"] = make_tone([1480.0], .055)
	cues["cut"] = make_tone([880.0, 1174.66], .10)
	cues["start"] = make_tone([392.0, 523.25, 659.25], .24)
	cues["win"] = make_tone([523.25, 659.25, 783.99], .65)
	cues["loss"] = make_tone([261.63, 311.13], .5)

func play_cue(cue: String) -> void:
	if not enabled or stream_player == null or not cues.has(cue):
		return
	stream_player.stream = cues[cue]
	stream_player.play()

func _exit_tree() -> void:
	if is_instance_valid(stream_player):
		stream_player.stop()
		stream_player.stream = null
	cues.clear()

func make_tone(frequencies: Array, duration: float) -> AudioStreamWAV:
	var rate := 22050
	var samples := int(duration * rate)
	var bytes := PackedByteArray()
	bytes.resize(samples * 2)
	for i in range(samples):
		var t := float(i) / rate
		var envelope := minf(t / .015, 1.0) * pow(1.0 - float(i) / samples, 1.7)
		var value := 0.0
		for frequency in frequencies:
			value += sin(TAU * float(frequency) * t) / frequencies.size()
		bytes.encode_s16(i * 2, int(value * envelope * 16000.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.stereo = false
	stream.data = bytes
	return stream
