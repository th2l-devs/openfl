package openfl.display;

#if !openfl_debug
@:fileXml('tags="haxe,release"')
@:noDebug
#end
class RenderStats
{
	public static var drawCalls(default, null):Int = 0;
	public static var textureBinds(default, null):Int = 0;
	public static var textureBindsSaved(default, null):Int = 0;
	public static var shaderSwitches(default, null):Int = 0;
	public static var targetSwitches(default, null):Int = 0;
	public static var viewportChanges(default, null):Int = 0;
	public static var viewportChangesSaved(default, null):Int = 0;
	public static var bufferUploads(default, null):Int = 0;
	public static var bufferUploadBytes(default, null):Int = 0;
	public static var frames(default, null):Int = 0;
	public static var markedDraws(default, null):Int = 0;
	public static var markedShaderSwitches(default, null):Int = 0;
	public static var markName:String = null;
	public static var targetTrace:Array<String> = null;
	@:noCompletion private static var __markDraws:Int = -1;
	@:noCompletion private static var __markShaders:Int = -1;

	@:noCompletion private static function __mark():Void
	{
		if (__markDraws >= 0) return;
		__markDraws = __drawCalls;
		__markShaders = __shaderSwitches;
	}

	@:noCompletion private static var __drawCalls:Int = 0;
	@:noCompletion private static var __textureBinds:Int = 0;
	@:noCompletion private static var __textureBindsSaved:Int = 0;
	@:noCompletion private static var __shaderSwitches:Int = 0;
	@:noCompletion private static var __targetSwitches:Int = 0;
	@:noCompletion private static var __viewportChanges:Int = 0;
	@:noCompletion private static var __viewportChangesSaved:Int = 0;
	@:noCompletion private static var __bufferUploads:Int = 0;
	@:noCompletion private static var __bufferUploadBytes:Int = 0;

	@:noCompletion private static function __endFrame():Void
	{
		drawCalls = __drawCalls;
		textureBinds = __textureBinds;
		textureBindsSaved = __textureBindsSaved;
		shaderSwitches = __shaderSwitches;
		targetSwitches = __targetSwitches;
		viewportChanges = __viewportChanges;
		viewportChangesSaved = __viewportChangesSaved;
		bufferUploads = __bufferUploads;
		bufferUploadBytes = __bufferUploadBytes;
		frames++;
		markedDraws = __markDraws >= 0 ? __drawCalls - __markDraws : 0;
		markedShaderSwitches = __markShaders >= 0 ? __shaderSwitches - __markShaders : 0;
		__markDraws = -1;
		__markShaders = -1;

		__drawCalls = 0;
		__textureBinds = 0;
		__textureBindsSaved = 0;
		__shaderSwitches = 0;
		__targetSwitches = 0;
		__viewportChanges = 0;
		__viewportChangesSaved = 0;
		__bufferUploads = 0;
		__bufferUploadBytes = 0;
	}
}
