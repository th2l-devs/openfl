package openfl.display._internal;

#if !flash
import openfl.utils._internal.Float32Array;
import openfl.display3D.Context3D;
import openfl.display3D.VertexBuffer3D;

@SuppressWarnings("checkstyle:FieldDocComment")
class Context3DBuffer
{
	public var dataPerVertex:Int;
	public var elementCount:Int;
	public var elementType:Context3DElementType;
	public var vertexBuffer:VertexBuffer3D;
	public var vertexBufferData:Float32Array;
	public var vertexCount:Int;

	private var context3D:Context3D;

	public function new(context3D:Context3D, elementType:Context3DElementType, elementCount:Int, dataPerVertex:Int)
	{
		this.context3D = context3D;
		this.elementType = elementType;
		this.dataPerVertex = dataPerVertex;

		vertexCount = 0;

		resize(elementCount);
	}

	public function flushVertexBufferData():Void
	{
		if (vertexBufferData.length > vertexCount)
		{
			vertexCount = vertexBufferData.length;
			vertexBuffer = context3D.createVertexBuffer(vertexCount, dataPerVertex, DYNAMIC_DRAW);
		}

		var usedLength = switch (elementType)
		{
			case QUADS: elementCount * 4 * dataPerVertex;
			case TRIANGLES, TRIANGLE_INDICES: elementCount * 3 * dataPerVertex;
		}

		GeometryBatch.upload(vertexBuffer, vertexBufferData, usedLength);
	}

	public function resize(elementCount:Int, dataPerVertex:Int = -1):Void
	{
		this.elementCount = elementCount;

		if (dataPerVertex == -1) dataPerVertex = this.dataPerVertex;

		if (dataPerVertex != this.dataPerVertex)
		{
			vertexBuffer = null;
			vertexCount = 0;

			this.dataPerVertex = dataPerVertex;
		}

		var numVertices = 0;

		switch (elementType)
		{
			case QUADS:
				numVertices = elementCount * 4;

			case TRIANGLES:
				numVertices = elementCount * 3;

			case TRIANGLE_INDICES:
				// TODO: Different index/triangle buffer lengths
				numVertices = elementCount * 3;

			default:
		}

		vertexBufferData = GeometryBatch.growFloats(vertexBufferData, numVertices * dataPerVertex);
	}
}

enum Context3DElementType
{
	QUADS;
	TRIANGLES;
	TRIANGLE_INDICES;
}
#end
