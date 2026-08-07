package openfl.display._internal;

#if !flash
import openfl.display.IBitmapDrawable;

/**
	One node of the render pipeline: the code that knows how to draw a single kind of drawable.

	A pass declares which drawable types it handles and receives a `GLDevice` rather than the
	renderer itself, so passes can be added, replaced or reordered without any of them knowing
	about the others. `RenderPipeline` owns the registration and the dispatch.

	`begin`/`end` bracket a frame. A pass that accumulates geometry across several drawables
	flushes it in `end`; a pass that draws each drawable immediately can leave both empty.
**/
@:access(openfl.display.IBitmapDrawable)
interface IRenderPass
{
	/**
		Whether this pass handles `type`.
	**/
	function accepts(type:IBitmapDrawableType):Bool;

	/**
		Called once before the first drawable of the frame reaches this pass.
	**/
	function begin(device:GLDevice):Void;

	/**
		Draws `drawable`.
	**/
	function execute(drawable:IBitmapDrawable, device:GLDevice):Void;

	/**
		Draws `drawable` as a stencil mask - coverage only, no color.
	**/
	function executeMask(drawable:IBitmapDrawable, device:GLDevice):Void;

	/**
		Flushes anything still accumulated and releases per-frame state.
	**/
	function end(device:GLDevice):Void;
}
#end
