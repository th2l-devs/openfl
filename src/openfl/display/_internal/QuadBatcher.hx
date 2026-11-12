package openfl.display._internal;

#if (lime && !flash && !js && !openfl_disable_quad_batch)
import openfl.display.Bitmap;
import openfl.display.BitmapData;
import openfl.display.BlendMode;
import openfl.display.DisplayObject;
import openfl.display.Graphics;
import openfl.display.OpenGLRenderer;
import openfl.display.PixelSnapping;
import openfl.display3D.Context3D;
import openfl.display3D.IndexBuffer3D;
import openfl.display3D.VertexBuffer3D;
import openfl.display3D._internal.GLProgram;
import openfl.display3D._internal.GLShaderDiagnostics;
import openfl.display3D._internal.GLUniformLocation;
import openfl.geom.ColorTransform;
import openfl.geom.Matrix;
import openfl.utils._internal.Float32Array;
import openfl.utils._internal.UInt16Array;

@:access(openfl.display.Bitmap)
@:access(openfl.display.BitmapData)
@:access(openfl.display.DisplayObject)
@:access(openfl.display.Graphics)
@:access(openfl.display.OpenGLRenderer)
@:access(openfl.display.Stage)
@:access(openfl.display3D.Context3D)
@:access(openfl.display3D.VertexBuffer3D)
@:access(openfl.display3D.IndexBuffer3D)
@:access(openfl.display3D.textures.TextureBase)
@:access(openfl.geom.ColorTransform)
@:access(openfl.geom.Matrix)
@:access(openfl.display._internal.Context3DGraphics)
class QuadBatcher
{
	public static var enabled:Bool = true;
	public static var pending(default, null):Bool = false;

	static inline var MAX_QUADS:Int = 2048;
	static inline var FLOATS:Int = 14;
	static inline var MAX_SLOTS:Int = 8;

	static var __context:Context3D;
	static var __program:GLProgram;
	static var __failed:Bool = false;
	static var __uMatrix:GLUniformLocation;
	static var __vertexBuffer:VertexBuffer3D;
	static var __indexBuffer:IndexBuffer3D;
	static var __data:Float32Array;
	static var __matrixValue:Float32Array;
	static var __slotCount:Int = 0;
	static var __maxSlots:Int = MAX_SLOTS;

	static var __renderer:OpenGLRenderer;
	static var __target:Dynamic;
	static var __blend:BlendMode;
	static var __quads:Int = 0;
	static var __textures:Array<BitmapData> = [for (i in 0...MAX_SLOTS) null];
	static var __smooth:Array<Bool> = [for (i in 0...MAX_SLOTS) false];
	static var __glTextures:Array<openfl.display3D.textures.TextureBase> = [for (i in 0...MAX_SLOTS) null];
	static var __flushing:Bool = false;

	static var __linear:SamplerState = new SamplerState(CLAMP, LINEAR, MIPNONE);
	static var __nearest:SamplerState = new SamplerState(CLAMP, NEAREST, MIPNONE);
	static var __matrix:Matrix = new Matrix();
	static var __fillTransform:ColorTransform = new ColorTransform();

	static var __vertexSource:String = "attribute vec2 aPosition;
		attribute vec2 aTexCoord;
		attribute float aSlot;
		attribute float aAlpha;
		attribute vec4 aColorMultiplier;
		attribute vec4 aColorOffset;
		uniform mat4 uMatrix;
		varying vec2 vTexCoord;
		varying float vSlot;
		varying float vAlpha;
		varying vec4 vColorMultiplier;
		varying vec4 vColorOffset;
		void main(void) {
			vTexCoord = aTexCoord;
			vSlot = aSlot;
			vAlpha = aAlpha;
			vColorMultiplier = aColorMultiplier;
			vColorOffset = aColorOffset / 255.0;
			gl_Position = uMatrix * vec4(aPosition, 0.0, 1.0);
		}";

	static var __fragmentSource:String = "varying vec2 vTexCoord;
		varying float vSlot;
		varying float vAlpha;
		varying vec4 vColorMultiplier;
		varying vec4 vColorOffset;
		uniform sampler2D uTexture0;
		uniform sampler2D uTexture1;
		uniform sampler2D uTexture2;
		uniform sampler2D uTexture3;
		uniform sampler2D uTexture4;
		uniform sampler2D uTexture5;
		uniform sampler2D uTexture6;
		uniform sampler2D uTexture7;
		vec4 sampleSlot() {
			if (vSlot < 0.5) return texture2D(uTexture0, vTexCoord);
			if (vSlot < 1.5) return texture2D(uTexture1, vTexCoord);
			if (vSlot < 2.5) return texture2D(uTexture2, vTexCoord);
			if (vSlot < 3.5) return texture2D(uTexture3, vTexCoord);
			if (vSlot < 4.5) return texture2D(uTexture4, vTexCoord);
			if (vSlot < 5.5) return texture2D(uTexture5, vTexCoord);
			if (vSlot < 6.5) return texture2D(uTexture6, vTexCoord);
			return texture2D(uTexture7, vTexCoord);
		}
		void main(void) {
			vec4 color = sampleSlot();
			if (color.a == 0.0) {
				gl_FragColor = vec4(0.0, 0.0, 0.0, 0.0);
			} else if (vColorMultiplier.w > 0.5) {
				color = vec4(color.rgb / color.a, color.a);
				color = clamp(vColorOffset + color * vec4(vColorMultiplier.rgb, 1.0), 0.0, 1.0);
				if (color.a > 0.0) {
					gl_FragColor = vec4(color.rgb * color.a * vAlpha, color.a * vAlpha);
				} else {
					gl_FragColor = vec4(0.0, 0.0, 0.0, 0.0);
				}
			} else {
				gl_FragColor = color * vAlpha;
			}
		}";

	public static inline function sync():Void
	{
		if (pending) flush();
	}

	static inline function batchableBlend(mode:BlendMode):Bool
	{
		return mode == null || mode == NORMAL || mode == ADD;
	}

	static function accepts(object:DisplayObject, renderer:OpenGLRenderer):Bool
	{
		if (!enabled || __failed) return false;
		if (renderer.__defaultRenderTarget != null || renderer.__context3D.__state.renderToTexture != null) return false;
		if (object.__worldShader != null || object.__mask != null || object.__scrollRect != null) return false;
		if (!batchableBlend(object.__worldBlendMode)) return false;
		return __ready(renderer.__context3D);
	}

	public static function pushBitmap(bitmap:Bitmap, renderer:OpenGLRenderer):Bool
	{
		if (!accepts(bitmap, renderer)) return false;
		final bitmapData = bitmap.__bitmapData;
		final smooth = renderer.__allowSmoothing && (bitmap.smoothing || renderer.__upscaled);
		__begin(renderer, bitmap.__worldBlendMode);
		__pushTexture(renderer, bitmapData, smooth, bitmap.__renderTransform, bitmap.pixelSnapping, bitmapData.width, bitmapData.height,
			bitmap.__worldAlpha, bitmap.__worldColorTransform);
		return true;
	}

	public static function pushShape(shape:DisplayObject, renderer:OpenGLRenderer):Bool
	{
		final graphics = shape.__graphics;
		if (graphics == null || !accepts(shape, renderer)) return false;

		final drawable = graphics.__visible && graphics.__commands.length > 0;
		final hardware = drawable && !(graphics.__bitmap != null && !graphics.__dirty) && Context3DGraphics.isCompatible(graphics);

		if (hardware)
		{
			if (!__colorRectsOnly(graphics)) return false;

			graphics.__bitmap = null;
			#if (openfl_disable_hdpi || openfl_disable_hdpi_graphics)
			graphics.__update(renderer.__worldTransform, 1);
			#else
			graphics.__update(renderer.__worldTransform, renderer.__pixelRatio);
			#end

			if (graphics.__bounds != null && graphics.__width >= 1 && graphics.__height >= 1)
			{
				__begin(renderer, shape.__worldBlendMode);
				__pushColorRects(renderer, shape, graphics);
			}

			graphics.__dirty = false;
			graphics.__hardwareDirty = false;
			return true;
		}

		Context3DGraphics.render(graphics, renderer);

		if (graphics.__bitmap != null && graphics.__visible)
		{
			__matrix.identity();
			__matrix.scale(1 / graphics.__bitmapScaleX, 1 / graphics.__bitmapScaleY);
			__matrix.concat(graphics.__worldTransform);
			final bitmap = graphics.__bitmap;
			__begin(renderer, shape.__worldBlendMode);
			__pushTexture(renderer, bitmap, true, __matrix, AUTO, bitmap.width, bitmap.height, shape.__worldAlpha, shape.__worldColorTransform);
		}

		return true;
	}

	static function __colorRectsOnly(graphics:Graphics):Bool
	{
		final commands = graphics.__hardwareCommands != null ? graphics.__hardwareCommands : graphics.__commands;
		final data = new DrawCommandReader(commands);
		var ok = true;

		for (type in commands.types)
		{
			switch (type)
			{
				case BEGIN_FILL, END_FILL, MOVE_TO, DRAW_RECT:
					data.skip(type);

				case DRAW_QUADS:
					final c = data.readDrawQuads();
					if (c.indices != null || c.transforms != null || c.rects == null)
					{
						ok = false;
						break;
					}

				default:
					ok = false;
					break;
			}
		}

		data.destroy();
		return ok;
	}

	static function __pushColorRects(renderer:OpenGLRenderer, shape:DisplayObject, graphics:Graphics):Void
	{
		final commands = graphics.__hardwareCommands != null ? graphics.__hardwareCommands : graphics.__commands;
		final data = new DrawCommandReader(commands);
		final blank = Context3DGraphics.blankBitmapData;
		final transform = graphics.__owner.__renderTransform;
		final worldTransform = shape.__worldColorTransform;
		var filling = false;
		var alpha = 0.0;

		for (type in commands.types)
		{
			switch (type)
			{
				case BEGIN_FILL:
					final c = data.readBeginFill();
					final color = Std.int(c.color);
					final ct = __fillTransform;
					ct.redMultiplier = ct.greenMultiplier = ct.blueMultiplier = ct.alphaMultiplier = 1;
					ct.redOffset = (color >> 16) & 0xFF;
					ct.greenOffset = (color >> 8) & 0xFF;
					ct.blueOffset = color & 0xFF;
					ct.alphaOffset = 0;
					if (worldTransform != null) ct.__combine(worldTransform);
					alpha = (Std.int(c.alpha * 0xFF) / 0xFF) * shape.__worldAlpha;
					filling = true;

				case DRAW_RECT:
					final c = data.readDrawRect();
					if (filling) __pushQuad(renderer, blank, true, transform, AUTO, c.x, c.y, c.width, c.height, 0.5, 0.5, 0.5, 0.5, alpha, __fillTransform);

				case DRAW_QUADS:
					final c = data.readDrawQuads();
					if (filling)
					{
						final rects = c.rects;
						var i = 0;
						while (i + 3 < rects.length)
						{
							__pushQuad(renderer, blank, true, transform, AUTO, rects[i], rects[i + 1], rects[i + 2], rects[i + 3], 0.5, 0.5, 0.5, 0.5, alpha,
								__fillTransform);
							i += 4;
						}
					}

				case END_FILL:
					data.skip(type);
					filling = false;

				default:
					data.skip(type);
			}
		}

		data.destroy();
	}

	static function __begin(renderer:OpenGLRenderer, blend:BlendMode):Void
	{
		if (blend == null) blend = NORMAL;
		final target:Dynamic = renderer.__context3D.__state.renderToTexture;
		if (pending && (renderer != __renderer || blend != __blend || target != __target)) flush();
		if (!pending)
		{
			final projection = renderer.__flipped ? renderer.__projectionFlipped : renderer.__projection;
			for (i in 0...16)
				__matrixValue[i] = projection[i];
			__target = target;
		}
		__renderer = renderer;
		__blend = blend;
	}

	static function __pushTexture(renderer:OpenGLRenderer, bitmapData:BitmapData, smooth:Bool, transform:Matrix, snapping:PixelSnapping, width:Float, height:Float, alpha:Float, colorTransform:ColorTransform):Void
	{
		__pushQuad(renderer, bitmapData, smooth, transform, snapping, 0, 0, width, height, 0, 0, 1, 1, alpha, colorTransform);
	}

	static function __slotFor(bitmapData:BitmapData, smooth:Bool):Int
	{
		for (i in 0...__slotCount)
		{
			if (__textures[i] == bitmapData)
			{
				if (__smooth[i] == smooth) return i;
				return -1;
			}
		}
		if (__slotCount >= __maxSlots) return -1;
		__textures[__slotCount] = bitmapData;
		__smooth[__slotCount] = smooth;
		return __slotCount++;
	}

	static function __pushQuad(renderer:OpenGLRenderer, bitmapData:BitmapData, smooth:Bool, transform:Matrix, snapping:PixelSnapping, x:Float, y:Float,
			width:Float, height:Float, u0:Float, v0:Float, u1:Float, v1:Float, alpha:Float, colorTransform:ColorTransform):Void
	{
		if (__quads >= MAX_QUADS) flush();

		var slot = __slotFor(bitmapData, smooth);
		if (slot < 0)
		{
			flush();
			slot = __slotFor(bitmapData, smooth);
		}

		final world = renderer.__worldTransform;
		var a = transform.a * world.a + transform.b * world.c;
		var b = transform.a * world.b + transform.b * world.d;
		var c = transform.c * world.a + transform.d * world.c;
		var d = transform.c * world.b + transform.d * world.d;
		var tx = transform.tx * world.a + transform.ty * world.c + world.tx;
		var ty = transform.tx * world.b + transform.ty * world.d + world.ty;

		if (snapping == ALWAYS || (snapping == AUTO && b == 0 && c == 0 && (a < 1.001 && a > 0.999) && (d < 1.001 && d > 0.999)))
		{
			tx = Math.round(tx);
			ty = Math.round(ty);
		}

		var hasTransform = colorTransform != null && !colorTransform.__isDefault(true);
		var mr = 1.0, mg = 1.0, mb = 1.0, or = 0.0, og = 0.0, ob = 0.0, oa = 0.0;
		if (hasTransform)
		{
			mr = colorTransform.redMultiplier;
			mg = colorTransform.greenMultiplier;
			mb = colorTransform.blueMultiplier;
			or = colorTransform.redOffset;
			og = colorTransform.greenOffset;
			ob = colorTransform.blueOffset;
			oa = colorTransform.alphaOffset;
		}

		final x1 = x + width, y1 = y + height;
		var o = __quads * 4 * FLOATS;
		final data = __data;
		inline function vertex(px:Float, py:Float, u:Float, v:Float):Void
		{
			data[o] = a * px + c * py + tx;
			data[o + 1] = b * px + d * py + ty;
			data[o + 2] = u;
			data[o + 3] = v;
			data[o + 4] = slot;
			data[o + 5] = alpha;
			data[o + 6] = mr;
			data[o + 7] = mg;
			data[o + 8] = mb;
			data[o + 9] = hasTransform ? 1 : 0;
			data[o + 10] = or;
			data[o + 11] = og;
			data[o + 12] = ob;
			data[o + 13] = oa;
			o += FLOATS;
		}
		vertex(x, y, u0, v0);
		vertex(x1, y, u1, v0);
		vertex(x, y1, u0, v1);
		vertex(x1, y1, u1, v1);

		__quads++;
		pending = true;
	}

	static function __ready(context:Context3D):Bool
	{
		if (__failed) return false;
		if (__program != null && __context == context) return true;

		final gl = context.gl;
		final prefix = "#ifdef GL_ES\nprecision mediump float;\n#endif\n";

		final vertexShader = gl.createShader(gl.VERTEX_SHADER);
		gl.shaderSource(vertexShader, prefix + __vertexSource);
		gl.compileShader(vertexShader);
		if (!GLShaderDiagnostics.checkShader(gl, vertexShader, "vertex", __vertexSource))
		{
			__failed = true;
			return false;
		}

		final fragmentShader = gl.createShader(gl.FRAGMENT_SHADER);
		gl.shaderSource(fragmentShader, prefix + __fragmentSource);
		gl.compileShader(fragmentShader);
		if (!GLShaderDiagnostics.checkShader(gl, fragmentShader, "fragment", __fragmentSource))
		{
			__failed = true;
			return false;
		}

		final program = gl.createProgram();
		gl.attachShader(program, vertexShader);
		gl.attachShader(program, fragmentShader);
		gl.bindAttribLocation(program, 0, "aPosition");
		gl.bindAttribLocation(program, 1, "aTexCoord");
		gl.bindAttribLocation(program, 2, "aSlot");
		gl.bindAttribLocation(program, 3, "aAlpha");
		gl.bindAttribLocation(program, 4, "aColorMultiplier");
		gl.bindAttribLocation(program, 5, "aColorOffset");
		gl.linkProgram(program);
		if (!GLShaderDiagnostics.checkProgram(gl, program, __fragmentSource))
		{
			__failed = true;
			return false;
		}

		final units:Int = gl.getParameter(gl.MAX_TEXTURE_IMAGE_UNITS);
		__maxSlots = units > 0 && units < MAX_SLOTS ? units : MAX_SLOTS;

		gl.useProgram(program);
		for (i in 0...MAX_SLOTS)
		{
			final location = gl.getUniformLocation(program, "uTexture" + i);
			gl.uniform1i(location, i < __maxSlots ? i : 0);
		}
		gl.useProgram(null);
		context.__contextState.program = null;
		context.__contextState.shader = null;

		__context = context;
		__program = program;
		__uMatrix = gl.getUniformLocation(program, "uMatrix");
		__data = new Float32Array(MAX_QUADS * 4 * FLOATS);
		__matrixValue = new Float32Array(16);
		__vertexBuffer = context.createVertexBuffer(MAX_QUADS * 4, FLOATS, DYNAMIC_DRAW);

		final indices = new UInt16Array(MAX_QUADS * 6);
		for (q in 0...MAX_QUADS)
		{
			indices[q * 6] = q * 4;
			indices[q * 6 + 1] = q * 4 + 1;
			indices[q * 6 + 2] = q * 4 + 2;
			indices[q * 6 + 3] = q * 4 + 2;
			indices[q * 6 + 4] = q * 4 + 1;
			indices[q * 6 + 5] = q * 4 + 3;
		}
		__indexBuffer = context.createIndexBuffer(MAX_QUADS * 6, STATIC_DRAW);
		__indexBuffer.uploadFromTypedArray(indices);

		__quads = 0;
		__slotCount = 0;
		pending = false;
		return true;
	}

	public static function flush():Void
	{
		if (!pending || __flushing) return;
		pending = false;
		__flushing = true;

		final renderer = __renderer;
		final context = renderer.__context3D;
		final gl = context.gl;

		if (context != __context || __program == null)
		{
			__quads = 0;
			__slotCount = 0;
			__flushing = false;
			return;
		}

		if (context.__state.renderToTexture == null)
		{
			if (context.__stage != null && context.__stage.context3D == context && !context.__stage.__renderer.__cleared)
			{
				context.__stage.__renderer.__clear();
			}
			else if (!context.__cleared)
			{
				context.clear(0, 0, 0, 0, 1, 0, openfl.display3D.Context3DClearMask.COLOR);
			}
		}

		renderer.__setBlendMode(__blend);
		context.setProgram(null);
		context.__flushGL();

		gl.useProgram(__program);

		gl.uniformMatrix4fv(__uMatrix, false, __matrixValue);

		for (i in 0...__slotCount)
			__glTextures[i] = __textures[i].getTexture(context);

		for (i in 0...__slotCount)
		{
			final texture = __glTextures[i];
			context.__setGLActiveTexture(i);
			if (texture != null)
			{
				texture.__setSamplerState(__smooth[i] && renderer.__allowSmoothing ? __linear : __nearest);
				context.__bindGLTexture2D(texture.__textureID);
			}
			else
			{
				context.__bindGLTexture2D(null);
			}
		}

		GeometryBatch.upload(__vertexBuffer, __data, __quads * 4 * FLOATS);

		final stride = FLOATS * 4;
		context.__bindGLArrayBuffer(__vertexBuffer.__id);
		gl.enableVertexAttribArray(0);
		gl.vertexAttribPointer(0, 2, gl.FLOAT, false, stride, 0);
		gl.enableVertexAttribArray(1);
		gl.vertexAttribPointer(1, 2, gl.FLOAT, false, stride, 8);
		gl.enableVertexAttribArray(2);
		gl.vertexAttribPointer(2, 1, gl.FLOAT, false, stride, 16);
		gl.enableVertexAttribArray(3);
		gl.vertexAttribPointer(3, 1, gl.FLOAT, false, stride, 20);
		gl.enableVertexAttribArray(4);
		gl.vertexAttribPointer(4, 4, gl.FLOAT, false, stride, 24);
		gl.enableVertexAttribArray(5);
		gl.vertexAttribPointer(5, 4, gl.FLOAT, false, stride, 40);

		context.__bindGLElementArrayBuffer(__indexBuffer.__id);
		gl.drawElements(gl.TRIANGLES, __quads * 6, gl.UNSIGNED_SHORT, 0);
		@:privateAccess openfl.display.RenderStats.__drawCalls++;
		@:privateAccess openfl.display.RenderStats.__batchedQuads += __quads;

		for (i in 0...6)
			gl.disableVertexAttribArray(i);
		gl.useProgram(null);
		context.__contextState.program = null;
		context.__contextState.shader = null;

		for (i in 0...__slotCount)
		{
			__textures[i] = null;
			__glTextures[i] = null;
		}
		__quads = 0;
		__slotCount = 0;
		__target = null;
		__flushing = false;
	}
}
#else
class QuadBatcher
{
	public static var enabled:Bool = false;
	public static var pending(default, null):Bool = false;

	public static inline function sync():Void {}

	public static function flush():Void {}

	public static function pushBitmap(bitmap:Dynamic, renderer:Dynamic):Bool
		return false;

	public static function pushShape(shape:Dynamic, renderer:Dynamic):Bool
		return false;
}
#end
