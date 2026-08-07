package openfl.display3D._internal;

#if !flash
#if lime
import lime.graphics.WebGLRenderContext;
#end
import openfl.errors.ShaderError;
import openfl.utils._internal.Log;

/**
	The single place shader and program compilation results are inspected and reported.

	Both GLSL compilation paths - `openfl.display.Shader` (filters and custom display shaders)
	and `openfl.display3D.Program3D` (raw AGAL/GLSL uploaded through `Context3D`) - route their
	diagnostics through here, so a failure reports the same way regardless of which one produced
	it: a `ShaderError` carrying the driver log remapped into the author's line numbers, thrown
	when `Log.throwErrors` is set and printed otherwise.
**/
#if !openfl_debug
@:fileXml('tags="haxe,release"')
@:noDebug
#end
@SuppressWarnings("checkstyle:FieldDocComment")
class GLShaderDiagnostics
{
	/**
		Counts the lines a preamble adds ahead of the author's source, so `ShaderError` can
		translate driver-reported line numbers back into the author's coordinates.
	**/
	public static function lineOffset(preamble:String):Int
	{
		if (preamble == null || preamble == "") return 0;

		var offset = 0;

		for (i in 0...preamble.length)
		{
			if (preamble.charCodeAt(i) == "\n".code) offset++;
		}

		return offset;
	}

	/**
		Checks the compile status of `shader` and reports a failure as a `ShaderError`.

		@param	shaderType	`"vertex"` or `"fragment"`.
		@param	source	The full source handed to the driver, preamble included.
		@param	lineOffset	The number of preamble lines ahead of the author's source.
		@return	`true` if the shader compiled.
	**/
	public static function checkShader(gl:#if lime WebGLRenderContext #else Dynamic #end, shader:GLShader, shaderType:String, source:String,
			lineOffset:Int = 0):Bool
	{
		var infoLog = gl.getShaderInfoLog(shader);

		if (gl.getShaderParameter(shader, gl.COMPILE_STATUS) == 0)
		{
			__report(new ShaderError(shaderType, infoLog, source, lineOffset));
			return false;
		}

		if (infoLog != null && StringTools.trim(infoLog) != "")
		{
			Log.debug("Info compiling " + shaderType + " shader\n" + infoLog + "\n" + source);
		}

		return true;
	}

	/**
		Checks the link status of `program` and reports a failure as a `ShaderError` whose
		`shaderType` is `"program"`.

		@param	source	A source to quote in the report; the fragment source is the usual choice.
		@return	`true` if the program linked.
	**/
	public static function checkProgram(gl:#if lime WebGLRenderContext #else Dynamic #end, program:GLProgram, source:String, lineOffset:Int = 0):Bool
	{
		if (gl.getProgramParameter(program, gl.LINK_STATUS) == 0)
		{
			__report(new ShaderError("program", gl.getProgramInfoLog(program), source, lineOffset));
			return false;
		}

		return true;
	}

	@:noCompletion private static function __report(error:ShaderError):Void
	{
		// Throwing is opt-in so existing applications keep their current behavior; the
		// message is the same either way
		if (Log.throwErrors) throw error;
		Log.println(error.message);
	}
}
#end
