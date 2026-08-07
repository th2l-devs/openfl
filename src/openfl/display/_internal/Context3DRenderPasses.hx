package openfl.display._internal;

#if !flash
import openfl.display.IBitmapDrawable;

/**
	The passes registered by default, one per drawable type.

	Each is a wrapper over the `Context3D*` class that already draws that type. Wrapping them
	first, before changing any of them, is what makes the dispatcher swap in `RenderPipeline`
	mechanical: the drawing code is untouched, only the way it is reached changes. A pass can then
	be rewritten - or replaced with a different implementation entirely, as `TilemapPass` is on
	Windows - behind the interface, without the dispatcher knowing.
**/
#if !openfl_debug
@:fileXml('tags="haxe,release"')
@:noDebug
#end
@:access(openfl.display.IBitmapDrawable)
@SuppressWarnings("checkstyle:FieldDocComment")
class BitmapDataPass implements IRenderPass
{
	public function new() {}

	public function accepts(type:IBitmapDrawableType):Bool
	{
		return type == BITMAP_DATA;
	}

	public function begin(device:GLDevice):Void {}

	public function execute(drawable:IBitmapDrawable, device:GLDevice):Void
	{
		Context3DBitmapData.renderDrawable(cast drawable, device.renderer);
	}

	public function executeMask(drawable:IBitmapDrawable, device:GLDevice):Void
	{
		Context3DBitmapData.renderDrawableMask(cast drawable, device.renderer);
	}

	public function end(device:GLDevice):Void {}
}

/**
	Traverses the display list: containers and the base display-object rendering, plus the mask
	and scrollRect handling that goes with them.
**/
#if !openfl_debug
@:fileXml('tags="haxe,release"')
@:noDebug
#end
@:access(openfl.display.IBitmapDrawable)
@SuppressWarnings("checkstyle:FieldDocComment")
class ObjectPass implements IRenderPass
{
	public function new() {}

	public function accepts(type:IBitmapDrawableType):Bool
	{
		return type == STAGE || type == SPRITE || type == SHAPE || type == SIMPLE_BUTTON;
	}

	public function begin(device:GLDevice):Void {}

	public function execute(drawable:IBitmapDrawable, device:GLDevice):Void
	{
		switch (drawable.__drawableType)
		{
			case STAGE, SPRITE:
				Context3DDisplayObjectContainer.renderDrawable(cast drawable, device.renderer);
			case SIMPLE_BUTTON:
				Context3DSimpleButton.renderDrawable(cast drawable, device.renderer);
			default:
				Context3DDisplayObject.renderDrawable(cast drawable, device.renderer);
		}
	}

	public function executeMask(drawable:IBitmapDrawable, device:GLDevice):Void
	{
		switch (drawable.__drawableType)
		{
			case STAGE, SPRITE:
				Context3DDisplayObjectContainer.renderDrawableMask(cast drawable, device.renderer);
			case SIMPLE_BUTTON:
				Context3DSimpleButton.renderDrawableMask(cast drawable, device.renderer);
			default:
				Context3DDisplayObject.renderDrawableMask(cast drawable, device.renderer);
		}
	}

	public function end(device:GLDevice):Void {}
}

/**
	Draws `Bitmap` instances, including the cache bitmaps that carry filters and isolated groups.
**/
#if !openfl_debug
@:fileXml('tags="haxe,release"')
@:noDebug
#end
@SuppressWarnings("checkstyle:FieldDocComment")
class BitmapPass implements IRenderPass
{
	public function new() {}

	public function accepts(type:IBitmapDrawableType):Bool
	{
		return type == BITMAP;
	}

	public function begin(device:GLDevice):Void {}

	public function execute(drawable:IBitmapDrawable, device:GLDevice):Void
	{
		Context3DBitmap.renderDrawable(cast drawable, device.renderer);
	}

	public function executeMask(drawable:IBitmapDrawable, device:GLDevice):Void
	{
		Context3DBitmap.renderDrawableMask(cast drawable, device.renderer);
	}

	public function end(device:GLDevice):Void {}
}

/**
	Draws `TextField` glyph geometry.
**/
#if !openfl_debug
@:fileXml('tags="haxe,release"')
@:noDebug
#end
@SuppressWarnings("checkstyle:FieldDocComment")
class TextPass implements IRenderPass
{
	public function new() {}

	public function accepts(type:IBitmapDrawableType):Bool
	{
		return type == TEXT_FIELD;
	}

	public function begin(device:GLDevice):Void {}

	public function execute(drawable:IBitmapDrawable, device:GLDevice):Void
	{
		Context3DTextField.renderDrawable(cast drawable, device.renderer);
	}

	public function executeMask(drawable:IBitmapDrawable, device:GLDevice):Void
	{
		Context3DTextField.renderDrawableMask(cast drawable, device.renderer);
	}

	public function end(device:GLDevice):Void {}
}

/**
	Draws `Video` instances.
**/
#if !openfl_debug
@:fileXml('tags="haxe,release"')
@:noDebug
#end
@SuppressWarnings("checkstyle:FieldDocComment")
class VideoPass implements IRenderPass
{
	public function new() {}

	public function accepts(type:IBitmapDrawableType):Bool
	{
		return type == VIDEO;
	}

	public function begin(device:GLDevice):Void {}

	public function execute(drawable:IBitmapDrawable, device:GLDevice):Void
	{
		Context3DVideo.renderDrawable(cast drawable, device.renderer);
	}

	public function executeMask(drawable:IBitmapDrawable, device:GLDevice):Void
	{
		Context3DVideo.renderDrawableMask(cast drawable, device.renderer);
	}

	public function end(device:GLDevice):Void {}
}

/**
	Draws `Tilemap` instances.

	On Windows this hands off to `InstancedTilePass` when the driver supports instanced arrays,
	falling back to `Context3DTilemap` otherwise.
**/
#if !openfl_debug
@:fileXml('tags="haxe,release"')
@:noDebug
#end
@SuppressWarnings("checkstyle:FieldDocComment")
class TilemapPass implements IRenderPass
{
	public function new() {}

	public function accepts(type:IBitmapDrawableType):Bool
	{
		return type == TILEMAP;
	}

	public function begin(device:GLDevice):Void {}

	public function execute(drawable:IBitmapDrawable, device:GLDevice):Void
	{
		#if (windows && cpp)
		if (InstancedTilePass.isSupported(device) && InstancedTilePass.renderDrawable(cast drawable, device)) return;
		#end

		Context3DTilemap.renderDrawable(cast drawable, device.renderer);
	}

	public function executeMask(drawable:IBitmapDrawable, device:GLDevice):Void
	{
		Context3DTilemap.renderDrawableMask(cast drawable, device.renderer);
	}

	public function end(device:GLDevice):Void {}
}
#end
