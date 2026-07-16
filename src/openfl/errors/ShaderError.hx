package openfl.errors;

#if !flash
/**
	The ShaderError class represents a GLSL shader that failed to compile or link.

	Unlike a generic error, ShaderError carries the pieces needed to diagnose the
	failure: which shader stage failed, the driver's info log, the source that was
	given to the driver, and the line number of the first reported error.

	OpenFL prepends a precision-qualifier preamble to every shader before handing it
	to the driver, so the line numbers a driver reports do not match the line numbers
	of the source you wrote. ShaderError corrects for this: `errorLine` and `infoLog`
	are both reported in the coordinates of your own source, while `rawInfoLog`
	preserves the driver's original text.

	```haxe
	try
	{
		sprite.shader = new MyShader();
	}
	catch (e:ShaderError)
	{
		trace(e.shaderType); // "fragment"
		trace(e.errorLine); // 6
		trace(e.message); // full report, with a source excerpt
	}
	```
**/
#if !openfl_debug
@:fileXml('tags="haxe,release"')
@:noDebug
#end
class ShaderError extends Error
{
	/**
		The line number of the first error reported by the driver, numbered against the
		source you wrote rather than the source the driver saw. Equal to `-1` if no line
		number could be recovered from the info log.
	**/
	public var errorLine(default, null):Int;

	/**
		The driver's info log, with every line number rewritten to match the source you
		wrote. See `rawInfoLog` for the driver's original text.
	**/
	public var infoLog(default, null):String;

	/**
		The number of lines OpenFL prepended to the source before compiling it. This is
		the difference between the line numbers in `rawInfoLog` and those in `infoLog`.
	**/
	public var lineOffset(default, null):Int;

	/**
		The driver's info log, exactly as reported, with line numbers still referring to
		the prepended source in `source`.
	**/
	public var rawInfoLog(default, null):String;

	/**
		The shader stage that failed: `"vertex"`, `"fragment"`, or `"program"` when
		linking failed rather than compilation.
	**/
	public var shaderType(default, null):String;

	/**
		The complete source passed to the driver, including the preamble OpenFL prepended.
		Line numbers in `rawInfoLog` refer to this string.
	**/
	public var source(default, null):String;

	/**
		Creates a new ShaderError.

		@param	shaderType	The stage that failed: `"vertex"`, `"fragment"` or `"program"`.
		@param	rawInfoLog	The info log as reported by the driver.
		@param	source	The full source passed to the driver, including any preamble.
		@param	lineOffset	The number of preamble lines prepended to the author's source.
	**/
	public function new(shaderType:String, rawInfoLog:String, source:String, lineOffset:Int = 0)
	{
		if (shaderType == null) shaderType = "";
		if (rawInfoLog == null) rawInfoLog = "";
		if (source == null) source = "";
		if (lineOffset < 0) lineOffset = 0;

		var infoLog = __remapInfoLog(rawInfoLog, lineOffset);
		var errorLine = __findErrorLine(rawInfoLog, lineOffset);

		super(__buildMessage(shaderType, infoLog, source, lineOffset, errorLine));

		this.shaderType = shaderType;
		this.rawInfoLog = rawInfoLog;
		this.source = source;
		this.lineOffset = lineOffset;
		this.infoLog = infoLog;
		this.errorLine = errorLine;

		name = "ShaderError";
	}

	/**
		Returns an excerpt of the author's source around `errorLine`, with the offending
		line marked. Returns an empty string if the error could not be traced to a line.

		@param	contextLines	How many lines to show either side of the error.
	**/
	public function getSourceContext(contextLines:Int = 3):String
	{
		return __sourceContext(source, lineOffset, errorLine, contextLines);
	}

	@:noCompletion private static function __buildMessage(shaderType:String, infoLog:String, source:String, lineOffset:Int, errorLine:Int):String
	{
		var buf = new StringBuf();

		buf.add(shaderType == "program" ? "Error linking shader program" : "Error compiling " + shaderType + " shader");
		if (errorLine > 0) buf.add(" (line " + errorLine + ")");

		var trimmedLog = StringTools.trim(infoLog);

		if (trimmedLog != "")
		{
			buf.add("\n\n");
			buf.add(trimmedLog);
		}

		var context = __sourceContext(source, lineOffset, errorLine, 3);

		if (context != "")
		{
			buf.add("\n\n");
			buf.add(context);
		}
		else if (source != "")
		{
			// No line number could be recovered, so fall back to the whole source rather
			// than leave the failure undiagnosable
			buf.add("\n\n");
			buf.add(__stripPreamble(source, lineOffset));
		}

		return buf.toString();
	}

	@:noCompletion private static function __findErrorLine(rawInfoLog:String, lineOffset:Int):Int
	{
		// "ERROR: 0:12: 'x' : undeclared identifier" (ANGLE, Mesa, most GLES drivers)
		var angle = ~/\bERROR:\s*\d+:(\d+)/i;

		if (angle.match(rawInfoLog))
		{
			var line = Std.parseInt(angle.matched(1));
			if (line != null && line > lineOffset) return line - lineOffset;
		}

		// "0(12) : error C1503: undefined variable" (NVIDIA desktop GL)
		var nvidia = ~/^\d+\((\d+)\)\s*:\s*error/im;

		if (nvidia.match(rawInfoLog))
		{
			var line = Std.parseInt(nvidia.matched(1));
			if (line != null && line > lineOffset) return line - lineOffset;
		}

		return -1;
	}

	@:noCompletion private static function __remapInfoLog(rawInfoLog:String, lineOffset:Int):String
	{
		if (lineOffset <= 0 || rawInfoLog == "") return rawInfoLog;

		// "ERROR: 0:12:" / "WARNING: 0:12:" -> shift the second number into author space
		var result = ~/\b(ERROR|WARNING):\s*(\d+):(\d+)/gi.map(rawInfoLog, function(r)
		{
			var line = Std.parseInt(r.matched(3));
			// A line inside the preamble is not the author's; leave it untouched
			if (line == null || line <= lineOffset) return r.matched(0);
			return r.matched(1) + ": " + r.matched(2) + ":" + Std.string(line - lineOffset);
		});

		// "0(12) :" -> same, for the NVIDIA desktop format
		result = ~/^(\d+)\((\d+)\)/gm.map(result, function(r)
		{
			var line = Std.parseInt(r.matched(2));
			if (line == null || line <= lineOffset) return r.matched(0);
			return r.matched(1) + "(" + Std.string(line - lineOffset) + ")";
		});

		return result;
	}

	@:noCompletion private static function __sourceContext(source:String, lineOffset:Int, errorLine:Int, contextLines:Int):String
	{
		if (source == "" || errorLine < 1) return "";
		if (contextLines < 0) contextLines = 0;

		var lines = __stripPreamble(source, lineOffset).split("\n");
		if (errorLine > lines.length) return "";

		var start = errorLine - contextLines;
		if (start < 1) start = 1;

		var end = errorLine + contextLines;
		if (end > lines.length) end = lines.length;

		var width = Std.string(end).length;
		var buf = new StringBuf();

		for (i in start...end + 1)
		{
			buf.add(i == errorLine ? "> " : "  ");
			buf.add(StringTools.lpad(Std.string(i), " ", width));
			buf.add(" | ");
			buf.add(lines[i - 1]);
			if (i < end) buf.add("\n");
		}

		return buf.toString();
	}

	@:noCompletion private static function __stripPreamble(source:String, lineOffset:Int):String
	{
		if (lineOffset <= 0) return source;

		var lines = source.split("\n");
		if (lines.length <= lineOffset) return source;

		return lines.slice(lineOffset).join("\n");
	}
}
#end
