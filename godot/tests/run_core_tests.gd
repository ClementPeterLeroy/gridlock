extends SceneTree
## Run without opening the visual prototype or importing its models.

const Tests = preload("res://tests/core/test_engine.gd")

func _initialize() -> void:
	var suite = Tests.new()
	suite.run()
	print("CORE TESTS COMPLETE: %d checks, %d failures" % [suite.checks, suite.failures])
	quit(0 if suite.failures == 0 else 1)
