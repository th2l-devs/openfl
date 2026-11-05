package openfl.display3D._internal;

#if (lime && sys && lime_cffi && !macro)
import haxe.crypto.Md5;
import haxe.io.Bytes;
import lime.graphics.WebGLRenderContext;
import lime.graphics.opengl.GLProgram as LimeProgram;
import lime.graphics.opengl.GLProgramBinary;
import lime.system.System;
import sys.FileSystem;
import sys.io.File;

class GLProgramCache
{
	public static var enabled:Bool = true;
	public static var hits(default, null):Int = 0;
	public static var misses(default, null):Int = 0;

	private static inline var VERSION:Int = 1;
	private static var checked:Bool = false;
	private static var usable:Bool = false;
	private static var folder:String = null;
	private static var driver:String = "";

	private static function ready(gl:WebGLRenderContext):Bool
	{
		if (!enabled) return false;
		if (checked) return usable;
		checked = true;
		try
		{
			if (!GLProgramBinary.ready()) return false;
			driver = VERSION + "|" + gl.getParameter(gl.VENDOR) + "|" + gl.getParameter(gl.RENDERER) + "|" + gl.getParameter(gl.VERSION);
			folder = System.applicationStorageDirectory + "shadercache/";
			if (!FileSystem.exists(folder)) FileSystem.createDirectory(folder);
			usable = true;
		}
		catch (_:Dynamic)
		{
			usable = false;
		}
		return usable;
	}

	private static inline function pathOf(vertex:String, fragment:String):String
	{
		return folder + Md5.encode(driver + "\x01" + vertex + "\x01" + fragment) + ".bin";
	}

	public static function load(gl:WebGLRenderContext, vertex:String, fragment:String):Dynamic
	{
		if (!ready(gl)) return null;
		final path = pathOf(vertex, fragment);
		try
		{
			if (!FileSystem.exists(path))
			{
				misses++;
				return null;
			}
			final file = File.getBytes(path);
			if (file.length > 4)
			{
				final program = gl.createProgram();
				if (GLProgramBinary.write(cast program, file.getInt32(0), file.sub(4, file.length - 4)))
				{
					hits++;
					return program;
				}
				gl.deleteProgram(program);
			}
			FileSystem.deleteFile(path);
		}
		catch (_:Dynamic) {}
		misses++;
		return null;
	}

	public static function prepare(gl:WebGLRenderContext, program:Dynamic):Void
	{
		if (ready(gl)) GLProgramBinary.allowRead(cast program);
	}

	public static function store(gl:WebGLRenderContext, program:Dynamic, vertex:String, fragment:String):Void
	{
		if (!ready(gl)) return;
		try
		{
			final data = Bytes.alloc(0);
			final format = GLProgramBinary.read(cast program, data);
			if (format == 0 || data.length == 0) return;
			final out = Bytes.alloc(data.length + 4);
			out.setInt32(0, format);
			out.blit(4, data, 0, data.length);
			final path = pathOf(vertex, fragment);
			File.saveBytes(path + ".tmp", out);
			if (FileSystem.exists(path)) FileSystem.deleteFile(path);
			FileSystem.rename(path + ".tmp", path);
		}
		catch (_:Dynamic) {}
	}
}
#end
