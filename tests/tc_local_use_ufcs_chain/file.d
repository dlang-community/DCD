module tests.tc_local_use_ufcs_chain.file;

module test;

struct GpuBuffer
{
	void* buffer;
}

struct VkContext
{
	GpuBuffer vertexBuffer;
	GpuBuffer indexBuffer;
}

void cleanupGpuBuffer(ref GpuBuffer buf) {}

void cleanupGeometryBuffers(ref VkContext ctx)
{
	ctx.vertexBuffer.cleanupGpuBuffer();
	ctx.indexBuffer.cleanupGpuBuffer();
}
