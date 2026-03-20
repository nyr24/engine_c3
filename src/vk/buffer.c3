module engine::vk;

import vk;
import logger;
import std::collections::elastic_array;
import std::math;

faultdef MEMORY_MAP_FAILED;

// ------ Buffer ------

struct VulkanBuffer
{
	VkBuffer handle;
	VkDeviceMemory mem;
	usz size;
}

fn VulkanBuffer? create_buffer(
	VulkanContext* ctx,
	VkDeviceSize size,
	VkBufferUsageFlagBits usage,
	VkSharingMode sharing_mode,
	VkMemoryPropertyFlagBits memory_properties
)
{
	VulkanBuffer vk_buff @noinit;
	vk_buff.init(ctx, size, usage, sharing_mode, memory_properties);
	return vk_buff;
}

fn void VulkanBuffer.init(
	&buff,
	VulkanContext* ctx,
	VkDeviceSize size,
	VkBufferUsageFlagBits usage,
	VkSharingMode sharing_mode,
	VkMemoryPropertyFlagBits memory_properties
)
{
	VkBufferCreateInfo buff_ci = {
		.sType = vk::STRUCTURE_TYPE_BUFFER_CREATE_INFO,
		.size = size,
		.usage = usage,
		.sharingMode = sharing_mode,
	};

	vk_check(vk::createBuffer(ctx.dev.log_dev, &buff_ci, ctx.vk_alloc, &buff.handle));

	VkMemoryRequirements mem_reqs @noinit;
	vk::getBufferMemoryRequirements(ctx.dev.log_dev, buff.handle, &mem_reqs);

	uint memory_index = ctx.dev.find_mem_type_index(
		mem_reqs.memoryTypeBits,
		memory_properties
	)!!;

	VkMemoryAllocateInfo alloc_info = {
		.sType = vk::STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
		.allocationSize = mem_reqs.size,
		.memoryTypeIndex = memory_index,
	};

	vk_check(vk::allocateMemory(ctx.dev.log_dev, &alloc_info, ctx.vk_alloc, &buff.mem));
	vk_check(vk::bindBufferMemory(ctx.dev.log_dev, buff.handle, buff.mem, 0));
	buff.size = size;
}

<*
 @require data.len - offset >= buff.size : "Should be enough space"
*>
fn void? VulkanBuffer.copy_data_into(
	&buff,
	VulkanDevice* dev,
	char[] data,
	uint offset = 0
)
{
	void* mapped_data;
	if (vk::mapMemory(
		dev.log_dev,
		buff.mem,
		offset,
		data.len,
		0,
		&mapped_data
	)
		!= vk::SUCCESS)
	{
		return MEMORY_MAP_FAILED~;
	}
	mem::copy(mapped_data, data.ptr, data.len);
	vk::unmapMemory(dev.log_dev, buff.mem);
}

fn void VulkanBuffer.destroy(&buff, VulkanContext* ctx)
{
	if (buff.handle)
	{
		vk::destroyBuffer(ctx.dev.log_dev, buff.handle, ctx.vk_alloc);
		buff.handle = null;
	}
	if (buff.mem)
	{
		vk::freeMemory(ctx.dev.log_dev, buff.mem, ctx.vk_alloc);
		buff.mem = null;
	}
}

// --- ElementBuffer ---

struct VulkanElementBuffer <IndexType>
{
	uint vertices_size_bytes;
	uint all_size_bytes;
	VulkanBuffer staging_buff;
	VulkanBuffer main_buff;
}

<*
 @require IndexType.kindof == UNSIGNED_INT : "Type should be unsigned integer"
*>
fn void? init_elem_buffer(
	VulkanElementBuffer* elem_buff,
	VulkanContext* ctx,
	Vertex[] vertices,
	IndexType[] indices,
) <IndexType>
{
	uint vertices_size_bytes = (uint)(vertices.len * Vertex.sizeof);
	uint indices_size_bytes = (uint)(indices.len * IndexType.sizeof);
	uint capacity_bytes = vertices_size_bytes + indices_size_bytes;

	elem_buff.staging_buff.init(
		ctx,
		capacity_bytes,
		vk::BUFFER_USAGE_TRANSFER_SRC_BIT,
		vk::SHARING_MODE_EXCLUSIVE,
		vk::MEMORY_PROPERTY_HOST_VISIBLE_BIT
			| vk::MEMORY_PROPERTY_HOST_COHERENT_BIT,
	);

	elem_buff.main_buff.init(
		ctx,
		capacity_bytes,
		vk::BUFFER_USAGE_TRANSFER_DST_BIT | vk::BUFFER_USAGE_VERTEX_BUFFER_BIT
			| vk::BUFFER_USAGE_INDEX_BUFFER_BIT,
		vk::SHARING_MODE_EXCLUSIVE,
		vk::MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
	);

	void* mapped_data;
	if (vk::mapMemory(ctx.dev.log_dev, elem_buff.staging_buff.mem, 0, capacity_bytes, 0, &mapped_data)
		!= vk::SUCCESS)
	{
		return MEMORY_MAP_FAILED~;
	}

	mem::copy(mapped_data, vertices.ptr, vertices_size_bytes);
	mem::copy(
		(char*)mapped_data + vertices_size_bytes,
		(char*)indices.ptr,
		indices_size_bytes
	);

	vk::unmapMemory(ctx.dev.log_dev, elem_buff.staging_buff.mem);
	elem_buff.vertices_size_bytes = vertices_size_bytes;
	elem_buff.all_size_bytes = capacity_bytes;
}

fn void VulkanElementBuffer.bind(&elem_buff, VulkanCmdBuffer cmd_buffer, VkDeviceSize[] offsets = {0})
{
	vk::cmdBindVertexBuffers(
		cmd_buffer.handle,
		0,
		1,
		&elem_buff.main_buff.handle,
		offsets
	);
	vk::cmdBindIndexBuffer(
		cmd_buffer.handle,
		elem_buff.main_buff.handle,
		elem_buff.vertices_size_bytes,
		convert_type_to_vk_index(IndexType),
	);
}

fn uint VulkanElementBuffer.indices_size_bytes(&elem_buff) @inline
{
	return elem_buff.all_size_bytes - elem_buff.vertices_size_bytes;
}

macro uint VulkanElementBuffer.indices_count(&elem_buff)
{
	$if IndexType.sizeof > char.sizeof:
		return elem_buff.indices_size_bytes() / IndexType.sizeof;
	$else
		return elem_buff.indices_size_bytes();
	$endif
}

fn void VulkanElementBuffer.destroy(&elem_buff, VulkanContext* ctx)
{
	elem_buff.staging_buff.destroy(ctx);
	elem_buff.main_buff.destroy(ctx);
}

fn GeometryView VulkanElementBuffer.get_full_geometry_view(&elem_buff)
{
	GeometryView view;
	view.init(0, elem_buff.indices_count(), 0);
	return view;
}

fn usz vk_index_sizeof(VkIndexType vk_ind) @inline @local
{
	switch (vk_ind)
	{
		case vk::INDEX_TYPE_UINT8:
			return char.sizeof;
		case vk::INDEX_TYPE_UINT16:
			return ushort.sizeof;
		case vk::INDEX_TYPE_UINT32:
			return uint.sizeof;
		default:
			return uint.sizeof;
	}
}

macro VkIndexType convert_type_to_vk_index($Type) @const @local
{
	$switch ($Type):
		$case char: return vk::INDEX_TYPE_UINT8;
		$case ushort: return vk::INDEX_TYPE_UINT16;
		$case uint: return vk::INDEX_TYPE_UINT32;
		$default: unreachable("Index type can only be one of: char, ushort, uint");
	$endswitch
}

macro typeid convert_vk_index_to_type(VkIndexType vk_index) @local
{
	switch (vk_index) {
		case vk::INDEX_TYPE_UINT8: return char;
		case vk::INDEX_TYPE_UINT16: return ushort;
		case vk::INDEX_TYPE_UINT32: return uint;
		default: unreachable("Unknown vk::indexType: %s", vk_index);
	}
}

// ------ Global UBO ------

// Needs to be at least 256 bytes for Nvidia cards
// struct GlobalUniformData
// {
// 	Mat4 view;
// 	Mat4 proj;
// 	Mat4 reserved_0;
// 	Mat4 reserved_1;
// }

struct LocalUniformData
{
	Vec4 diffuse_color;
	Vec4 reserved_0;
	Vec4 reserved_1;
	Vec4 reserved_2;
}

// struct VulkanGlobalUBO
// {
// 	GlobalUniformData  uniform_data;
// 	void*              mapped_mem;
// 	VulkanBuffer       buffer;
// }

// fn void? VulkanGlobalUBO.init(
// 	&ubo,
// 	VulkanContext* ctx,
// 	Mat4 view = math::M4_IDENTITY,
// 	Mat4 proj = math::M4_IDENTITY
// )
// {
// 	ubo.buffer.init(
// 		ctx,
// 		GlobalUniformData.sizeof,
// 		vk::BUFFER_USAGE_UNIFORM_BUFFER_BIT,
// 		vk::SHARING_MODE_EXCLUSIVE,
// 		vk::MEMORY_PROPERTY_DEVICE_LOCAL_BIT
// 			| vk::MEMORY_PROPERTY_HOST_VISIBLE_BIT
// 			| vk::MEMORY_PROPERTY_HOST_COHERENT_BIT
// 	);

// 	if (vk::mapMemory(
// 		ctx.dev.log_dev,
// 		ubo.buffer.mem,
// 		0,
// 		GlobalUniformData.sizeof,
// 		0,
// 		&ubo.mapped_mem
// 	)
// 		!= vk::SUCCESS)
// 	{
// 		return MEMORY_MAP_FAILED~;
// 	}

// 	ubo.update(view, proj);
// }

// fn void VulkanGlobalUBO.update(&ubo, Mat4 view, Mat4 proj)
// {
// 	ubo.uniform_data.view = view;
// 	ubo.uniform_data.proj = proj;
// 	mem::copy(
// 		ubo.mapped_mem,
// 		&ubo.uniform_data,
// 		GlobalUniformData.sizeof
// 	);
// }

// fn void VulkanGlobalUBO.update_view(&ubo, Mat4 view)
// {
// 	ubo.uniform_data.view = view;
// 	mem::copy(
// 		(char*)ubo.mapped_mem
// 			+ $offsetof(ubo.uniform_data.view),
// 		(char*)&ubo.uniform_data
// 			+ $offsetof(ubo.uniform_data.view),
// 		Mat4.sizeof
// 	);
// }

// fn void VulkanGlobalUBO.update_proj(&ubo, Mat4 proj)
// {
// 	ubo.uniform_data.proj = proj;
// 	mem::copy(
// 		(char*)ubo.mapped_mem
// 			+ $offsetof(ubo.uniform_data.proj),
// 		(char*)&ubo.uniform_data
// 			+ $offsetof(ubo.uniform_data.proj),
// 		Mat4.sizeof
// 	);
// }

// fn void VulkanGlobalUBO.destroy(&ubo, VulkanContext* ctx)
// {
// 	vk::unmapMemory(ctx.dev.log_dev, ubo.buffer.mem);
// 	ubo.buffer.destroy(ctx);
// }

// ------ Local Ubo ------

// struct VulkanPushConstantBlock
// {
// 	Mat4 mvp;
// }

// fn void VulkanPushConstantBlock.update(&push_cnst, Mat4 new_mvp)
// {
// 	push_cnst.mvp = new_mvp;
// }
