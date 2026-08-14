package openfl.display._internal;

#if (!flash && (windows || linux) && cpp)
import openfl.display.BitmapData;
import openfl.display.BlendMode;
import openfl.display.Tile;
import openfl.display.TileContainer;
import openfl.display.Tilemap;
import openfl.display.Tileset;
import openfl.display.Tileset.TileData;
import openfl.display3D.Context3D;
import openfl.display3D.IndexBuffer3D;
import openfl.display3D.VertexBuffer3D;
import openfl.display3D._internal.GLProgram;
import openfl.display3D._internal.GLShaderDiagnostics;
import openfl.display3D._internal.GLUniformLocation;
import openfl.geom.ColorTransform;
import openfl.geom.Matrix;
import openfl.geom.Rectangle;
import openfl.utils._internal.Float32Array;
import openfl.utils._internal.UInt16Array;
#if lime
import lime.graphics.WebGL2RenderContext;
#end
#if gl_stats
import openfl.display._internal.stats.Context3DStats;
import openfl.display._internal.stats.DrawCallContext;
#end

/**
	Draws a `Tilemap` as hardware instances of a single unit quad, on desktop GL (Windows and Linux).

	`Context3DTilemap` writes four vertices per tile every frame - position and UV unrolled per
	corner, plus alpha and an eight-float color transform repeated four times when those are
	enabled - and uploads the lot. The corners of an axis-aligned quad are entirely derived from
	the tile's transform and size, so three quarters of that is the CPU recomputing what the GPU
	can replicate for free.

	Here a tile is one 80-byte instance record - a 2x3 transform, the source UV rect, and the
	color transform - drawn against a static unit quad uploaded once at startup, via
	`glVertexAttribDivisor` and `glDrawElementsInstanced`. The CPU writes and uploads roughly a
	quarter as much per tile, and there is still only one traversal of the tile tree because the
	instance buffer grows as it fills rather than being sized in advance.

	Windows and Linux both reach GL through the same dynamic extension loader in `lime`, so
	`glVertexAttribDivisor` and `glDrawElementsInstanced` resolve identically on each. macOS is
	excluded: its compatibility profile caps at GL 2.1, which predates instanced arrays.

	This is the one place where the algorithm changes rather than just the structure, so it is
	opt-in twice over: the driver must report instancing support, *and* the build must define
	`openfl_instanced_tiles`. Without both, `TilemapPass` uses `Context3DTilemap` exactly as before.
**/
#if !openfl_debug
@:fileXml('tags="haxe,release"')
@:noDebug
#end
@:access(openfl.display.Tile)
@:access(openfl.display.TileContainer)
@:access(openfl.display.Tilemap)
@:access(openfl.display.Tileset)
@:access(openfl.display.BitmapData)
@:access(openfl.display.OpenGLRenderer)
@:access(openfl.display3D.Context3D)
@:access(openfl.display3D._internal.Context3DState)
@:access(openfl.display3D.textures.TextureBase)
@:access(openfl.display3D.VertexBuffer3D)
@:access(openfl.display3D.IndexBuffer3D)
@:access(openfl.geom.ColorTransform)
@:access(openfl.geom.Matrix)
@:access(openfl.geom.Rectangle)
@SuppressWarnings("checkstyle:FieldDocComment")
class InstancedTilePass
{
	/** Floats per instance record: 2x3 transform + alpha, UV rect, color multiplier, color offset. **/
	public static inline var FLOATS_PER_INSTANCE:Int = 20;

	private static inline var ATTRIB_CORNER:Int = 0;
	private static inline var ATTRIB_TRANSFORM_AXES:Int = 1;
	private static inline var ATTRIB_TRANSLATE_ALPHA:Int = 2;
	private static inline var ATTRIB_SRC_RECT:Int = 3;
	private static inline var ATTRIB_COLOR_MULTIPLIER:Int = 4;
	private static inline var ATTRIB_COLOR_OFFSET:Int = 5;

	private static var __vertexSource:String = "attribute vec2 aCorner;
		attribute vec4 aTransformAxes;
		attribute vec4 aTranslateAlpha;
		attribute vec4 aSrcRect;
		attribute vec4 aColorMultiplier;
		attribute vec4 aColorOffset;

		uniform mat4 uMatrix;

		varying vec2 vTexCoord;
		varying float vAlpha;
		varying vec4 vColorMultiplier;
		varying vec4 vColorOffset;

		void main(void) {

			// aCorner is one of (0,0) (1,0) (0,1) (1,1); the axes already have the tile size
			// folded in, so this is the full quad-corner transform in two multiply-adds
			vec2 position = aTranslateAlpha.xy + aTransformAxes.xy * aCorner.x + aTransformAxes.zw * aCorner.y;

			vTexCoord = mix (aSrcRect.xy, aSrcRect.zw, aCorner);
			vAlpha = aTranslateAlpha.w;
			vColorMultiplier = aColorMultiplier;
			vColorOffset = aColorOffset / 255.0;

			gl_Position = uMatrix * vec4 (position, 0.0, 1.0);

		}";

	private static var __fragmentSource:String = "#ifdef GL_ES
		#ifdef GL_FRAGMENT_PRECISION_HIGH
		precision highp float;
		#else
		precision mediump float;
		#endif
		#endif

		varying vec2 vTexCoord;
		varying float vAlpha;
		varying vec4 vColorMultiplier;
		varying vec4 vColorOffset;

		uniform sampler2D uTexture;
		uniform bool uHasColorTransform;

		void main(void) {

			vec4 color = texture2D (uTexture, vTexCoord);

			if (color.a == 0.0) {

				gl_FragColor = vec4 (0.0, 0.0, 0.0, 0.0);

			} else if (uHasColorTransform) {

				color = vec4 (color.rgb / color.a, color.a);

				mat4 colorMultiplier = mat4 (0);
				colorMultiplier[0][0] = vColorMultiplier.x;
				colorMultiplier[1][1] = vColorMultiplier.y;
				colorMultiplier[2][2] = vColorMultiplier.z;
				colorMultiplier[3][3] = 1.0;

				color = clamp (vColorOffset + (color * colorMultiplier), 0.0, 1.0);

				if (color.a > 0.0) {

					gl_FragColor = vec4 (color.rgb * color.a * vAlpha, color.a * vAlpha);

				} else {

					gl_FragColor = vec4 (0.0, 0.0, 0.0, 0.0);

				}

			} else {

				gl_FragColor = color * vAlpha;

			}

		}";

	private static var __context:Context3D;
	private static var __program:GLProgram;
	private static var __uMatrix:GLUniformLocation;
	private static var __uTexture:GLUniformLocation;
	private static var __uHasColorTransform:GLUniformLocation;
	private static var __quadBuffer:VertexBuffer3D;
	private static var __quadIndices:IndexBuffer3D;
	private static var __instanceBuffer:VertexBuffer3D;
	private static var __instanceData:Float32Array;
	private static var __instanceCapacity:Int;

	// Per-build state, reset at the start of each tilemap
	// glUniformMatrix4fv wants a typed array, while __getMatrix hands back a plain Array
	private static var __matrixValue:Float32Array;
	private static var __numInstances:Int;
	private static var __writePosition:Int;
	private static var __currentBitmapData:BitmapData;
	private static var __currentBlendMode:BlendMode;
	private static var __cacheColorTransform:ColorTransform;
	private static var __supported:Null<Bool>;

	/**
		Whether the instanced path can run: the build opted in, and the driver reports the
		instanced-array entry points.
	**/
	public static function isSupported(device:GLDevice):Bool
	{
		#if !openfl_instanced_tiles
		return false;
		#else
		if (__supported != null) return __supported;

		#if lime
		var gl2:WebGL2RenderContext = device.context.__context.webgl2;
		__supported = (gl2 != null);
		#else
		__supported = false;
		#end

		return __supported;
		#end
	}

	/**
		Draws `tilemap` through the instanced path.

		Returns `false` without drawing anything if the path cannot be set up, so the caller can
		fall back to `Context3DTilemap`.
	**/
	public static function renderDrawable(tilemap:Tilemap, device:GLDevice):Bool
	{
		#if (lime && openfl_instanced_tiles)
		var renderer = device.renderer;

		renderer.__updateCacheBitmap(tilemap, false);

		if (tilemap.__cacheBitmap != null && !tilemap.__isCacheBitmapRender)
		{
			Context3DBitmap.render(tilemap.__cacheBitmap, renderer);
			renderer.__renderEvent(tilemap);
			return true;
		}

		if (!tilemap.__renderable || tilemap.__worldAlpha <= 0 || tilemap.__group.__tiles.length == 0)
		{
			tilemap.__group.__dirty = false;
			return true;
		}

		// Per-tile shaders would each need their own instanced program; that is a separate pass,
		// so hand those tilemaps back to the general path rather than dropping the shader
		if (tilemap.__worldShader != null) return false;

		var context = device.context;
		if (!__init(context)) return false;

		Context3DDisplayObject.render(tilemap, renderer);

		var gl2:WebGL2RenderContext = context.__context.webgl2;
		var gl = device.gl;

		__numInstances = 0;
		__writePosition = 0;
		__currentBitmapData = null;
		__currentBlendMode = tilemap.__worldBlendMode;

		if (!tilemap.tileBlendModeEnabled) renderer.__setBlendMode(__currentBlendMode);

		renderer.__pushMaskObject(tilemap);

		var clipRect = Rectangle.__pool.get();
		clipRect.setTo(0, 0, tilemap.__width, tilemap.__height);
		renderer.__pushMaskRect(clipRect, tilemap.__renderTransform);

		// Bind the program and the static quad once for the whole tilemap
		context.setProgram(null);
		context.__flushGL();
		gl.useProgram(__program);
		if (__matrixValue == null) __matrixValue = new Float32Array(16);

		var matrixValues = renderer.__getMatrix(tilemap.__renderTransform, AUTO);
		for (i in 0...16)
		{
			__matrixValue[i] = matrixValues[i];
		}

		gl.uniformMatrix4fv(__uMatrix, false, __matrixValue);
		gl.uniform1i(__uTexture, 0);
		gl.uniform1i(__uHasColorTransform, tilemap.tileColorTransformEnabled ? 1 : 0);

		__bindQuad(context, gl2, gl);

		var rect = Rectangle.__pool.get();
		var matrix = Matrix.__pool.get();
		var parentTransform = Matrix.__pool.get();

		__buildContainer(tilemap, tilemap.__group, device, gl2, parentTransform, tilemap.__tileset, tilemap.__worldAlpha,
			tilemap.tileColorTransformEnabled, tilemap.__worldColorTransform, tilemap.tileBlendModeEnabled, __currentBlendMode, rect);

		__flush(tilemap, device, gl2, gl);

		Rectangle.__pool.release(rect);
		Rectangle.__pool.release(clipRect);
		Matrix.__pool.release(matrix);
		Matrix.__pool.release(parentTransform);

		tilemap.__group.__dirty = false;

		__unbind(context, gl2, gl);

		renderer.__popMaskRect();
		renderer.__popMaskObject(tilemap);
		renderer.__renderEvent(tilemap);

		return true;
		#else
		return false;
		#end
	}

	#if (lime && openfl_instanced_tiles)
	private static function __init(context:Context3D):Bool
	{
		if (__program != null && __context == context) return true;

		var gl = context.gl;

		var vertexShader = gl.createShader(gl.VERTEX_SHADER);
		gl.shaderSource(vertexShader, __vertexSource);
		gl.compileShader(vertexShader);
		if (!GLShaderDiagnostics.checkShader(gl, vertexShader, "vertex", __vertexSource)) return false;

		var fragmentShader = gl.createShader(gl.FRAGMENT_SHADER);
		gl.shaderSource(fragmentShader, __fragmentSource);
		gl.compileShader(fragmentShader);
		if (!GLShaderDiagnostics.checkShader(gl, fragmentShader, "fragment", __fragmentSource)) return false;

		var program = gl.createProgram();
		gl.attachShader(program, vertexShader);
		gl.attachShader(program, fragmentShader);

		// Bound explicitly rather than queried, because the divisor is set per location and the
		// per-instance locations have to be the ones the instance buffer is described against
		gl.bindAttribLocation(program, ATTRIB_CORNER, "aCorner");
		gl.bindAttribLocation(program, ATTRIB_TRANSFORM_AXES, "aTransformAxes");
		gl.bindAttribLocation(program, ATTRIB_TRANSLATE_ALPHA, "aTranslateAlpha");
		gl.bindAttribLocation(program, ATTRIB_SRC_RECT, "aSrcRect");
		gl.bindAttribLocation(program, ATTRIB_COLOR_MULTIPLIER, "aColorMultiplier");
		gl.bindAttribLocation(program, ATTRIB_COLOR_OFFSET, "aColorOffset");

		gl.linkProgram(program);
		if (!GLShaderDiagnostics.checkProgram(gl, program, __fragmentSource)) return false;

		__context = context;
		__program = program;
		__uMatrix = gl.getUniformLocation(program, "uMatrix");
		__uTexture = gl.getUniformLocation(program, "uTexture");
		__uHasColorTransform = gl.getUniformLocation(program, "uHasColorTransform");

		// The unit quad, uploaded once and replicated per instance by the GPU
		var quad = new Float32Array([0, 0, 1, 0, 0, 1, 1, 1]);
		__quadBuffer = context.createVertexBuffer(4, 2, STATIC_DRAW);
		__quadBuffer.uploadFromTypedArray(quad);

		var indices = new UInt16Array([0, 1, 2, 2, 1, 3]);
		__quadIndices = context.createIndexBuffer(6, STATIC_DRAW);
		__quadIndices.uploadFromTypedArray(indices);

		__instanceCapacity = 0;
		__instanceData = null;
		__instanceBuffer = null;

		return true;
	}

	private static function __bindQuad(context:Context3D, gl2:WebGL2RenderContext, gl:Dynamic):Void
	{
		context.__bindGLArrayBuffer(__quadBuffer.__id);
		gl.enableVertexAttribArray(ATTRIB_CORNER);
		gl.vertexAttribPointer(ATTRIB_CORNER, 2, gl.FLOAT, false, 8, 0);
		gl2.vertexAttribDivisor(ATTRIB_CORNER, 0);
	}

	private static function __bindInstances(context:Context3D, gl2:WebGL2RenderContext, gl:Dynamic):Void
	{
		var stride = FLOATS_PER_INSTANCE * 4;

		context.__bindGLArrayBuffer(__instanceBuffer.__id);

		__bindInstanceAttrib(gl2, gl, ATTRIB_TRANSFORM_AXES, stride, 0);
		__bindInstanceAttrib(gl2, gl, ATTRIB_TRANSLATE_ALPHA, stride, 16);
		__bindInstanceAttrib(gl2, gl, ATTRIB_SRC_RECT, stride, 32);
		__bindInstanceAttrib(gl2, gl, ATTRIB_COLOR_MULTIPLIER, stride, 48);
		__bindInstanceAttrib(gl2, gl, ATTRIB_COLOR_OFFSET, stride, 64);
	}

	private static inline function __bindInstanceAttrib(gl2:WebGL2RenderContext, gl:Dynamic, index:Int, stride:Int, offset:Int):Void
	{
		gl.enableVertexAttribArray(index);
		gl.vertexAttribPointer(index, 4, gl.FLOAT, false, stride, offset);
		gl2.vertexAttribDivisor(index, 1);
	}

	private static function __unbind(context:Context3D, gl2:WebGL2RenderContext, gl:Dynamic):Void
	{
		// Divisors are per-attribute-location driver state that outlives this draw. Leaving them
		// set would make every subsequent non-instanced draw read one vertex per primitive
		for (index in ATTRIB_CORNER...(ATTRIB_COLOR_OFFSET + 1))
		{
			gl2.vertexAttribDivisor(index, 0);
			gl.disableVertexAttribArray(index);
		}

		gl.useProgram(null);

		// Context3D still believes its own cached program and buffer bindings are current
		context.__contextState.program = null;
		context.__contextState.shader = null;
		context.__contextState.__currentGLArrayBuffer = null;
	}

	private static function __ensureCapacity(count:Int):Void
	{
		if (count <= __instanceCapacity) return;

		__instanceData = GeometryBatch.growFloats(__instanceData, count * FLOATS_PER_INSTANCE);
		__instanceCapacity = Std.int(__instanceData.length / FLOATS_PER_INSTANCE);
	}

	private static function __buildContainer(tilemap:Tilemap, group:TileContainer, device:GLDevice, gl2:WebGL2RenderContext, parentTransform:Matrix,
			defaultTileset:Tileset, worldAlpha:Float, colorTransformEnabled:Bool, defaultColorTransform:ColorTransform, blendModeEnabled:Bool,
			defaultBlendMode:BlendMode, rect:Rectangle):Void
	{
		var renderer = device.renderer;
		var tileTransform = Matrix.__pool.get();
		var roundPixels = renderer.__roundPixels;

		var tileset:Tileset;
		var alpha:Float;
		var colorTransform:ColorTransform = null;
		var blendMode:BlendMode = defaultBlendMode;
		var tileData:TileData;
		var tileRect:Rectangle;
		var bitmapData:BitmapData;

		for (tile in group.__tiles)
		{
			tileTransform.setTo(1, 0, 0, 1, -tile.originX, -tile.originY);
			tileTransform.concat(tile.matrix);
			tileTransform.concat(parentTransform);

			if (roundPixels)
			{
				tileTransform.tx = Math.round(tileTransform.tx);
				tileTransform.ty = Math.round(tileTransform.ty);
			}

			tileset = tile.tileset != null ? tile.tileset : defaultTileset;

			alpha = tile.alpha * worldAlpha;
			tile.__dirty = false;

			if (!tile.visible || alpha <= 0) continue;

			if (colorTransformEnabled) colorTransform = __combineColorTransform(defaultColorTransform, tile.colorTransform);
			if (blendModeEnabled) blendMode = (tile.__blendMode != null) ? tile.__blendMode : defaultBlendMode;

			if (tile.__length > 0)
			{
				__buildContainer(tilemap, cast tile, device, gl2, tileTransform, tileset, alpha, colorTransformEnabled, colorTransform, blendModeEnabled,
					blendMode, rect);
				continue;
			}

			if (tileset == null) continue;

			bitmapData = tileset.__bitmapData;
			if (bitmapData == null) continue;

			var uvX:Float, uvY:Float, uvWidth:Float, uvHeight:Float;

			if (tile.id == -1)
			{
				tileRect = tile.__rect;
				if (tileRect == null || tileRect.width <= 0 || tileRect.height <= 0) continue;

				var invWidth = 1.0 / bitmapData.width;
				var invHeight = 1.0 / bitmapData.height;

				uvX = tileRect.x * invWidth;
				uvY = tileRect.y * invHeight;
				uvWidth = tileRect.right * invWidth;
				uvHeight = tileRect.bottom * invHeight;
			}
			else
			{
				tileData = tileset.__data[tile.id];
				if (tileData == null) continue;

				rect.setTo(tileData.x, tileData.y, tileData.width, tileData.height);
				tileRect = rect;

				uvX = tileData.__uvX;
				uvY = tileData.__uvY;
				uvWidth = tileData.__uvWidth;
				uvHeight = tileData.__uvHeight;
			}

			// A batch can only span one texture and one blend state
			if ((__currentBitmapData != null && bitmapData != __currentBitmapData) || blendMode != __currentBlendMode)
			{
				__flush(tilemap, device, gl2, device.gl);
			}

			__currentBitmapData = bitmapData;
			__currentBlendMode = blendMode;

			__ensureCapacity(__numInstances + 1);

			var offset = __writePosition;
			var data = __instanceData;

			data[offset + 0] = tileRect.width * tileTransform.a;
			data[offset + 1] = tileRect.width * tileTransform.b;
			data[offset + 2] = tileRect.height * tileTransform.c;
			data[offset + 3] = tileRect.height * tileTransform.d;

			data[offset + 4] = tileTransform.tx;
			data[offset + 5] = tileTransform.ty;
			data[offset + 6] = 0;
			data[offset + 7] = tilemap.tileAlphaEnabled ? alpha : 1;

			data[offset + 8] = uvX;
			data[offset + 9] = uvY;
			data[offset + 10] = uvWidth;
			data[offset + 11] = uvHeight;

			if (colorTransformEnabled && colorTransform != null)
			{
				data[offset + 12] = colorTransform.redMultiplier;
				data[offset + 13] = colorTransform.greenMultiplier;
				data[offset + 14] = colorTransform.blueMultiplier;
				data[offset + 15] = colorTransform.alphaMultiplier;

				data[offset + 16] = colorTransform.redOffset;
				data[offset + 17] = colorTransform.greenOffset;
				data[offset + 18] = colorTransform.blueOffset;
				data[offset + 19] = colorTransform.alphaOffset;
			}
			else
			{
				data[offset + 12] = 1;
				data[offset + 13] = 1;
				data[offset + 14] = 1;
				data[offset + 15] = 1;

				data[offset + 16] = 0;
				data[offset + 17] = 0;
				data[offset + 18] = 0;
				data[offset + 19] = 0;
			}

			__writePosition += FLOATS_PER_INSTANCE;
			__numInstances++;
		}

		group.__dirty = false;
		Matrix.__pool.release(tileTransform);
	}

	private static function __combineColorTransform(parent:ColorTransform, tile:ColorTransform):ColorTransform
	{
		if (tile == null) return parent;
		if (parent == null) return tile;

		if (__cacheColorTransform == null) __cacheColorTransform = new ColorTransform();

		var result = __cacheColorTransform;
		result.redMultiplier = parent.redMultiplier * tile.redMultiplier;
		result.greenMultiplier = parent.greenMultiplier * tile.greenMultiplier;
		result.blueMultiplier = parent.blueMultiplier * tile.blueMultiplier;
		result.alphaMultiplier = parent.alphaMultiplier * tile.alphaMultiplier;
		result.redOffset = parent.redOffset + tile.redOffset;
		result.greenOffset = parent.greenOffset + tile.greenOffset;
		result.blueOffset = parent.blueOffset + tile.blueOffset;
		result.alphaOffset = parent.alphaOffset + tile.alphaOffset;

		return result;
	}

	private static function __flush(tilemap:Tilemap, device:GLDevice, gl2:WebGL2RenderContext, gl:Dynamic):Void
	{
		if (__numInstances == 0 || __currentBitmapData == null) return;

		var context = device.context;
		var renderer = device.renderer;

		if (tilemap.tileBlendModeEnabled) renderer.__setBlendMode(__currentBlendMode);

		if (__instanceBuffer == null || __instanceBuffer.__numVertices < __instanceCapacity)
		{
			__instanceBuffer = context.createVertexBuffer(__instanceCapacity, FLOATS_PER_INSTANCE, DYNAMIC_DRAW);
		}

		GeometryBatch.upload(__instanceBuffer, __instanceData, __writePosition);

		__bindInstances(context, gl2, gl);

		gl.activeTexture(gl.TEXTURE0);
		context.__bindGLTexture2D(__currentBitmapData.getTexture(context).__textureID);

		context.__bindGLElementArrayBuffer(__quadIndices.__id);
		gl2.drawElementsInstanced(gl.TRIANGLES, 6, gl.UNSIGNED_SHORT, 0, __numInstances);

		#if gl_stats
		Context3DStats.incrementDrawCall(DrawCallContext.STAGE);
		#end

		__numInstances = 0;
		__writePosition = 0;
	}
	#end
}
#end
