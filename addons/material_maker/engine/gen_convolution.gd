tool
extends MMGenBase
class_name MMGenConvolution

var convolution_params : Dictionary = {}

func get_type():
	return "convolution"

func get_type_name():
	if convolution_params.has("name"): 
		return convolution_params.name
	return .get_type_name()

func get_parameter_defs():
	var rv : Array = [ { name="size", type="size", first=4, last=11, default=4 } ]
	if convolution_params.has("parameters"):
		for p in convolution_params.parameters:
			rv.push_back(p)
	return rv

func get_input_defs():
	return [ { name="in", type=convolution_params.input_type } ]

func get_output_defs():
	return [ { type=convolution_params.output_type } ]

func set_convolution_params(data: Dictionary):
	convolution_params = data
	
func _get_shader_code(uv : String, output_index : int, context : MMGenContext):
	var genname = "o"+str(get_instance_id())
	var epsilon = 1.0/pow(2, 4+parameters.size)
	var types = { "rgba": { type="vec4", init="vec4(0.0)" }, "rgb": { type="vec3", init="vec3(0.0)" }, "f": { type="float", init="0.0" } }
	var rv = { globals=[], defs="", code="", textures={} }
	var source = get_source(0)
	if source == null:
		return rv
	var variant_index = context.get_variant(self, uv)
	if variant_index == -1:
		variant_index = context.get_variant(self, uv)
		# Calculate matrix
		var errors = 0
		var sum = [ 0.0, 0.0, 0.0, 0.0 ]
		var matrix = []
		var expr : Expression = null
		var expr_variables : PoolStringArray
		var expr_values : Array
		var expr_variables_x_index : int
		if convolution_params.has("matrix_function"):
			expr = Expression.new()
			expr_variables = PoolStringArray(["size"])
			expr_values = [ pow(2, 4+parameters.size) ]
			if convolution_params.has("parameters"):
				for p in convolution_params.parameters:
					expr_variables.push_back(p.name)
					if parameters.has(p.name):
						expr_values.push_back(parameters[p.name])
					elif p.has("default"):
						expr_values.push_back(p.default)
					else:
						expr_values.push_back(0)
						errors += 1
						print("No value for "+p.name)
				expr_variables_x_index = expr_variables.size()
				expr_variables.push_back("x")
				expr_values.push_back(0)
				expr_variables.push_back("y")
				expr_values.push_back(0)
			var error = expr.parse(convolution_params.matrix_function, expr_variables)
			if error != OK:
				print("Error in expression: "+expr.get_error_text())
				return
		for dy in range(-convolution_params.y, convolution_params.y+1):
			var line = []
			for dx in range(-convolution_params.x, convolution_params.x+1):
				var coef = 0.0
				if convolution_params.has("matrix"):
					coef = convolution_params.matrix[dy+convolution_params.y][dx+convolution_params.x]
				elif expr != null:
					expr_values[expr_variables_x_index] = dx
					expr_values[expr_variables_x_index+1] = dy
					coef = expr.execute(expr_values)
				if typeof(coef) == TYPE_INT:
					coef = float(coef)
				match convolution_params.output_type:
					"f":
						if typeof(coef) == TYPE_REAL or convolution_params.input_type == "f":
							sum[0] += coef
						else:
							errors += 1
					"rgb":
						if typeof(coef) == TYPE_REAL:
							sum[0] += coef
							sum[1] += coef
							sum[2] += coef
							if convolution_params.input_type == "f":
								coef = "vec3(%.9f)" % [ coef ]
							elif convolution_params.input_type == "rgb":
								coef = "%.9f" % coef
							else:
								errors += 1
						if typeof(coef) == TYPE_ARRAY and coef.size() == 3:
							if convolution_params.input_type == "f" or convolution_params.input_type == "rgb":
								sum[0] += coef[0]
								sum[1] += coef[1]
								sum[2] += coef[2]
								coef = "vec3(%.9f,%.9f,%.9f)" % [ coef[0], coef[1], coef[2] ]
							else:
								errors += 1
					"rgba":
						if typeof(coef) == TYPE_REAL:
							sum[0] += coef
							sum[1] += coef
							sum[2] += coef
							sum[3] += coef
							if convolution_params.input_type == "f":
								coef = "vec4(%.9f)" % [ coef ]
							if convolution_params.input_type == "rgba":
								coef = "%.9f" % coef
							else:
								errors += 1
						if typeof(coef) == TYPE_ARRAY and coef.size() == 3:
							if convolution_params.input_type == "f" or convolution_params.input_type == "rgba":
								sum[0] += coef[0]
								sum[1] += coef[1]
								sum[2] += coef[2]
								sum[3] += coef[3]
								coef = "vec4(%.9f,%.9f,%.9f,%.9f)" % [ coef[0], coef[1], coef[2], coef[3] ]
							else:
								errors += 1
				line.push_back(coef)
			matrix.push_back(line)
		# Generate code
		rv.code += "%s %s_%d = %s;\n" % [ types[convolution_params.output_type].type, genname, variant_index, types[convolution_params.output_type].init ]
		if errors > 0:
			pass
		else:
			for dy in range(-convolution_params.y, convolution_params.y+1):
				var line = matrix[dy+convolution_params.y]
				for dx in range(-convolution_params.x, convolution_params.x+1):
					var coef = line[dx+convolution_params.x]
					var uv_str = "((%s)+vec2(%.9f,%.9f))" % [ uv, dx*epsilon, dy*epsilon ]
					var src_code = source.generator.get_shader_code(uv_str, source.output_index, context)
					while src_code is GDScriptFunctionState:
						src_code = yield(src_code, "completed")
					# Add global definitions
					for d in src_code.globals:
						if rv.globals.find(d) == -1:
							rv.globals.push_back(d)
					# Add generated definitions
					rv.defs += src_code.defs
					# Add generated code
					rv.code += src_code.code
					rv.code += "%s_%d += %s*%s;\n" % [ genname, variant_index, coef, src_code[convolution_params.input_type] ]
					for t in src_code.textures.keys():
						rv.textures[t] = src_code.textures[t]
			# normalize
			if false:
				var sum_str : String
				var count : float = float((2*convolution_params.x+1) / (2*convolution_params.y+1))
				match convolution_params.output_type:
					"f":
						sum_str = "%.9f" % [ sum[0] / count ]
					"rgb":
						sum_str = "vec3(%.9f, %.9f, %.9f)" % [ sum[0] / count, sum[1] / count, sum[2] / count ]
					"rgba":
						sum_str = "vec4(%.9f, %.9f, %.9f, %.9f)" % [ sum[0] / count, sum[1] / count, sum[2] / count, sum[3] / count ]
				rv.code += "%s_%d /= %s;\n" % [ genname, variant_index, sum_str ]
			rv[convolution_params.output_type] = "%s_%d" % [ genname, variant_index ]
	return rv

func _serialize(data):
	data.convolution_params = convolution_params
	return data
