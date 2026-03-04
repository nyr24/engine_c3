module vk;

import engine;
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
		.s_type = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
		.size = size,
		.usage = usage,
		.sharing_mode = sharing_mode,
	};

	vk_check(vkCreateBuffer(ctx.dev.log_dev, &buff_ci, null, &buff.handle));

	VkMemoryRequirements mem_reqs @noinit;
	vkGetBufferMemoryRequirements(ctx.dev.log_dev, buff.handle, &mem_reqs);

	uint memory_index = ctx.dev.find_mem_type_index(
		mem_reqs.memory_type_bits,
		memory_properties
	)!!;

	VkMemoryAllocateInfo alloc_info = {
		.s_type = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
		.allocation_size = mem_reqs.size,
		.memory_type_index = memory_index,
	};

	vk_check(
		vkAllocateMemory(ctx.dev.log_dev, &alloc_info, ctx.vk_alloc, &buff.mem)
	);
	vk_check(vkBindBufferMemory(ctx.dev.log_dev, buff.handle, buff.mem, 0));
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
	if (vkMapMemory(
		dev.log_dev,
		buff.mem,
		offset,
		data.len,
		0,
		&mapped_data
	)
		!= VK_SUCCESS)
	{
		return MEMORY_MAP_FAILED~;
	}
	mem::copy(mapped_data, data.ptr, data.len);
	vkUnmapMemory(dev.log_dev, buff.mem);
}

fn void VulkanBuffer.destroy(&buff, VulkanContext* ctx)
{
	if (buff.handle)
	{
		vkDestroyBuffer(ctx.dev.log_dev, buff.handle, ctx.vk_alloc);
		buff.handle = null;
	}
	if (buff.mem)
	{
		vkFreeMemory(ctx.dev.log_dev, buff.mem, ctx.vk_alloc);
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
		VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
		VK_SHARING_MODE_EXCLUSIVE,
		VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT
			| VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
	);

	elem_buff.main_buff.init(
		ctx,
		capacity_bytes,
		VK_BUFFER_USAGE_TRANSFER_DST_BIT | VK_BUFFER_USAGE_VERTEX_BUFFER_BIT
			| VK_BUFFER_USAGE_INDEX_BUFFER_BIT,
		VK_SHARING_MODE_EXCLUSIVE,
		VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
	);

	void* mapped_data;
	if (vkMapMemory(ctx.dev.log_dev, elem_buff.staging_buff.mem, 0, capacity_bytes, 0, &mapped_data)
		!= VK_SUCCESS)
	{
		return MEMORY_MAP_FAILED~;
	}

	mem::copy(mapped_data, vertices.ptr, vertices_size_bytes);
	mem::copy(
		(char*)mapped_data + vertices_size_bytes,
		(char*)indices.ptr,
		indices_size_bytes
	);

	vkUnmapMemory(ctx.dev.log_dev, elem_buff.staging_buff.mem);
	elem_buff.vertices_size_bytes = vertices_size_bytes;
	elem_buff.all_size_bytes = capacity_bytes;
}

fn void VulkanElementBuffer.bind(&elem_buff, VulkanCmdBuffer cmd_buffer, VkDeviceSize[] offsets = {})
{
	vkCmdBindVertexBuffers(
		cmd_buffer.handle,
		0,
		1,
		&elem_buff.main_buff.handle,
		offsets
	);
	vkCmdBindIndexBuffer(
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
		return elem_buff.indices_size_bytes() * (1 / IndexType.sizeof);
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
		case VK_INDEX_TYPE_UINT8:
			return char.sizeof;
		case VK_INDEX_TYPE_UINT16:
			return ushort.sizeof;
		case VK_INDEX_TYPE_UINT32:
			return uint.sizeof;
		default:
			return uint.sizeof;
	}
}

macro VkIndexType convert_type_to_vk_index($Type) @const @local
{
	$switch ($Type):
		$case char: return VK_INDEX_TYPE_UINT8;
		$case ushort: return VK_INDEX_TYPE_UINT16;
		$case uint: return VK_INDEX_TYPE_UINT32;
		$default: unreachable("Index type can only be one of: char, ushort, uint");
	$endswitch
}

macro typeid convert_vk_index_to_type(VkIndexType vk_index) @local
{
	switch (vk_index) {
		case VK_INDEX_TYPE_UINT8: return char;
		case VK_INDEX_TYPE_UINT16: return ushort;
		case VK_INDEX_TYPE_UINT32: return uint;
		default: unreachable("Unknown vkIndexType: %s", vk_index);
	}
}

// ------ Global UBO ------

// Needs to be at least 256 bytes for Nvidia cards
struct GlobalUniformData
{
	Mat4 view;
	Mat4 proj;
	// Mat4 reserved_0;
	// Mat4 reserved_1;
}

struct LocalUniformData
{
	Vec4 diffuse_color;
	Vec4 reserved_0;
	Vec4 reserved_1;
	Vec4 reserved_2;
}

struct VulkanGlobalUBO
{
	GlobalUniformData  uniform_data;
	void*              mapped_mem;
	VulkanBuffer       buffer;
}

fn void? VulkanGlobalUBO.init(&ubo, VulkanContext* ctx)
{
	ubo.buffer.init(
		ctx,
		GlobalUniformData.sizeof,
		VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT,
		VK_SHARING_MODE_EXCLUSIVE,
		VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT
			| VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT
			| VK_MEMORY_PROPERTY_HOST_COHERENT_BIT
	);

	if (vkMapMemory(
		ctx.dev.log_dev,
		ubo.buffer.mem,
		0,
		VulkanGlobalUBO.sizeof,
		0,
		&ubo.mapped_mem
	)
		!= VK_SUCCESS)
	{
		return MEMORY_MAP_FAILED~;
	}
}

fn void VulkanGlobalUBO.update(&ubo, Mat4 view, Mat4 proj)
{
	ubo.uniform_data.view = view;
	ubo.uniform_data.proj = proj;
	mem::copy(
		ubo.mapped_mem,
		&ubo.uniform_data,
		GlobalUniformData.sizeof
	);
}

fn void VulkanGlobalUBO.update_view(&ubo, Mat4 view)
{
	ubo.uniform_data.view = view;
	mem::copy(
		(char*)ubo.mapped_mem
			+ $offsetof(ubo.uniform_data.view),
		(char*)&ubo.uniform_data
			+ $offsetof(ubo.uniform_data.view),
		Mat4.sizeof
	);
}

fn void VulkanGlobalUBO.update_proj(&ubo, Mat4 proj)
{
	ubo.uniform_data.proj = proj;
	mem::copy(
		(char*)ubo.mapped_mem
			+ $offsetof(ubo.uniform_data.proj),
		(char*)&ubo.uniform_data
			+ $offsetof(ubo.uniform_data.proj),
		Mat4.sizeof
	);
}

fn void VulkanGlobalUBO.destroy(&ubo, VulkanContext* ctx)
{
	vkUnmapMemory(ctx.dev.log_dev, ubo.buffer.mem);
	ubo.buffer.destroy(ctx);
}

// ------ Local Ubo ------

struct VulkanPushConstantBlock
{
	Mat4 model;
}

fn void VulkanPushConstantBlock.update(&push_cnst, Mat4 new_model)
{
	push_cnst.model = new_model;
}
