module engine;

import vk;
import stb;
import logger;
import std::collections::map;
import std::collections::elastic_array;
import std::collections::list;

faultdef TEXTURE_LOAD_ERROR;

const MAX_TEXTURE_NAME_LEN  = 32;
const TEXTURE_CHANNEL_COUNT = stb::RGB_ALPHA;

alias TextureName = ElasticArray{char, MAX_TEXTURE_NAME_LEN};

enum TextureLoadState
{
	NOT_LOADED,
	LOADED_FROM_DISK,
	UPLOADED_TO_GPU
}

struct Texture
{
	TextureLoadState load_state;
	uint width;
	uint height;
	uint size;
	uint channels;
	VulkanBuffer vk_staging_buff;
	VulkanImage vk_image;
	VkSampler sampler;
	TextureName name;
}

// NOTE (TODO): don't use tmem because this will be in separate thread later
// NOTE (TODO): strip extension from name
<*
 Loads texture from disk + initializes vulkan structures
 @require texture_name.len <= MAX_TEXTURE_NAME_LEN : "Shouldn't exceed max boundary"
*>
fn void? Texture.init(&tex, String texture_name, VulkanContext* ctx, Allocator temp_alloc = tmem)
{
	char* data = load_from_disk(texture_name, tex, temp_alloc)!;
	defer stb::image_free(data);

	tex.name.push_all((char[])texture_name);

	tex.vk_staging_buff.init(
		ctx,
		tex.size,
		vk::BUFFER_USAGE_TRANSFER_SRC_BIT,
		vk::SHARING_MODE_EXCLUSIVE,
		vk::MEMORY_PROPERTY_HOST_VISIBLE_BIT | vk::MEMORY_PROPERTY_HOST_COHERENT_BIT
	);

	tex.vk_staging_buff.copy_data_into(&ctx.dev, data[:tex.size])!;

	tex.vk_image.init(
		ctx,
		vk::FORMAT_B8G8R8A8_UNORM,
		tex.width,
		tex.height,
		usage: vk::IMAGE_USAGE_COLOR_ATTACHMENT_BIT | vk::IMAGE_USAGE_TRANSFER_DST_BIT | vk::IMAGE_USAGE_SAMPLED_BIT,
	);
}

<*
 Loads texture from disk + initializes vulkan structures
 @require file_name.len <= MAX_TEXTURE_NAME_LEN : "Shouldn't exceed max boundary"
*>
fn Texture? create_texture(String file_name, VulkanContext* ctx, Allocator temp_alloc = tmem)
{
	Texture new_tex @noinit;
	new_tex.init(file_name, ctx, temp_alloc)!;
	return new_tex;
}

fn void Texture.cmd_transfer_to_gpu(&tex, VulkanCmdBuffer cmd_buffer, VulkanContext* ctx)
{
	tex.vk_image.cmd_transition_layout(
		cmd_buffer,
		vk::IMAGE_LAYOUT_UNDEFINED,
		vk::IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
		vk::PIPELINE_STAGE_2_TOP_OF_PIPE_BIT,
		vk::PIPELINE_STAGE_TRANSFER_BIT,
		0,
		vk::ACCESS_TRANSFER_WRITE_BIT
	);

	vk::cmd_copy_data_from_buff_to_img(
		cmd_buffer,
		tex.vk_staging_buff,
		&tex.vk_image,
		vk::IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL
	);

	tex.vk_image.cmd_transition_layout(
		cmd_buffer,
		vk::IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
		vk::IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
		vk::PIPELINE_STAGE_TRANSFER_BIT,
		vk::PIPELINE_STAGE_FRAGMENT_SHADER_BIT,
		vk::ACCESS_TRANSFER_WRITE_BIT,
		vk::ACCESS_SHADER_READ_BIT,
	);

	VkSamplerCreateInfo sampler_ci = {
		.sType = vk::STRUCTURE_TYPE_SAMPLER_CREATE_INFO,
		.magFilter = vk::FILTER_LINEAR,
		.minFilter = vk::FILTER_LINEAR,
		.mipmapMode = vk::SAMPLER_MIPMAP_MODE_LINEAR,
		.addressModeU = vk::SAMPLER_ADDRESS_MODE_REPEAT,
		.addressModeV = vk::SAMPLER_ADDRESS_MODE_REPEAT,
		.addressModeW = vk::SAMPLER_ADDRESS_MODE_REPEAT,
		.mipLodBias = 0.0f,
		.anisotropyEnable = vk::TRUE,
		.maxAnisotropy = 16,
		.compareEnable = vk::FALSE,
		.compareOp = vk::COMPARE_OP_ALWAYS,
		.minLod = 0.0f,
		.maxLod = 0.0f,
		.borderColor = vk::BORDER_COLOR_INT_OPAQUE_BLACK,
		.unnormalizedCoordinates = vk::FALSE,
		};

	vk::check(vk::createSampler(ctx.dev.log_dev, &sampler_ci, ctx.vk_alloc, &tex.sampler));

	tex.load_state = UPLOADED_TO_GPU;
}

<*
 @require !!ctx.dev.log_dev : "Device should exist"
*>
fn void Texture.destroy(&tex, VulkanContext* ctx)
{
	vk::deviceWaitIdle(ctx.dev.log_dev);
	tex.vk_image.destroy(ctx);
	tex.vk_staging_buff.destroy(ctx);

	if (tex.sampler)
	{
		vk::destroySampler(ctx.dev.log_dev, tex.sampler, ctx.vk_alloc);
		tex.sampler = null;
	}

	tex.load_state = NOT_LOADED;
}

fn VkDescriptorImageInfo Texture.to_vk_descriptor_info(&tex)
{
	return {
		.sampler = tex.sampler,
		.imageView = tex.vk_image.view,
		.imageLayout = vk::IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
	};
}

fn char*? load_from_disk(String file_name, Texture* out_tex, Allocator temp_alloc = tmem) @local
{
	String full_path = TEXTURES_PATH.concat(temp_alloc, file_name);
	defer alloc::free(temp_alloc, full_path);

	char* data = stb::load((ZString)full_path, (CInt*)&out_tex.width, (CInt*)&out_tex.height, (CInt*)&out_tex.channels, TEXTURE_CHANNEL_COUNT);

	if (!data)
	{
		logger::logn(
			ERROR,
			"Error loading texture: name - %s, file_path: %s, reason: %s",
			file_name,
			full_path,
			stb::failure_reason()
		);
		stb::err("", "");
		return TEXTURE_LOAD_ERROR~;
	}
	out_tex.size = out_tex.width * out_tex.height * TEXTURE_CHANNEL_COUNT;
	out_tex.load_state = LOADED_FROM_DISK;
	return data;
}

// --- Texture System ---

struct TextureSystem
{
	List{Texture} textures;
	HashMap{String, uint} lookup_table;
}

struct SlotInfo
{
	Texture* ref;
	uint index;
}

const float TABLE_LOAD_FACTOR = 0.95;

fn void TextureSystem.init(&tex_sys, Allocator alloc, uint capacity)
{
	tex_sys.textures.init(alloc, capacity);
	tex_sys.textures.resize_to_cap();
	mem::clear(tex_sys.textures.data(), tex_sys.textures.byte_size());
	tex_sys.lookup_table.init(alloc, capacity, TABLE_LOAD_FACTOR);
}

<*
 @require input_name.len <= MAX_TEXTURE_NAME_LEN : "Shouldn't exceed max name length"
*>
fn uint? TextureSystem.load_texture(&tex_sys, App* app_ctx, String input_name)
{
	if (try uint existing_index = tex_sys.lookup_table.get(input_name))
	{
		return existing_index;
	}

	SlotInfo new_slot = find_free_slot(tex_sys);
	new_slot.ref.init(input_name, &app_ctx.vk_ctx, tmem)!;
	tex_sys.lookup_table.set((String)new_slot.ref.name.view(), new_slot.index);

	return new_slot.index;
}

<*
 @require cmd_buff.state == RECORDING_BEGIN : "Should be in ready state"
 @require index < tex_sys.textures.size : "Texture index shouldn't exceed bounds"
*>
fn void TextureSystem.cmd_transfer_texture_to_gpu(&tex_sys, VulkanContext* vk_ctx, uint index, VulkanCmdBuffer cmd_buff)
{
	Texture* tex = tex_sys.get_texture_by_index(index);
	tex.cmd_transfer_to_gpu(cmd_buff, vk_ctx);
}

<*
 @require cmd_buff.state == RECORDING_BEGIN : "Should be in ready state"
*>
fn void TextureSystem.cmd_transfer_multiple_textures_to_gpu(&tex_sys, VulkanContext* vk_ctx, uint[] indices, VulkanCmdBuffer cmd_buff)
{
	foreach (ind : indices)
	{
		tex_sys.cmd_transfer_texture_to_gpu(vk_ctx, ind, cmd_buff);
	}
}

<*
 @require index < tex_sys.textures.size : "Texture index shouldn't exceed bounds"
*>
fn Texture* TextureSystem.get_texture_by_index(&tex_sys, uint index) @inline
{
	return &tex_sys.textures[index];
}

fn Texture*? TextureSystem.get_texture_by_name(&tex_sys, String name)
{
	uint index = tex_sys.lookup_table.get(name)!;
	return tex_sys.get_texture_by_index(index);
}

<*
 @require index < tex_sys.textures.size : "Texture index shouldn't exceed bounds"
*>
fn void TextureSystem.remove_texture(&tex_sys, uint index)
{
	Texture* tex = &tex_sys.textures[index];
	(void)tex_sys.lookup_table.remove((String)tex.name.array_view());
	tex.load_state = NOT_LOADED;
}

fn void TextureSystem.destroy(&tex_sys)
{
	tex_sys.textures.free();
	tex_sys.lookup_table.free();
}

fn SlotInfo find_free_slot(TextureSystem* tex_sys) @local
{
	foreach (uint i, &slot : tex_sys.textures)
	{
		if (slot.load_state == NOT_LOADED)
		{
			return { .ref = slot, .index = i };
		}
	}
	tex_sys.textures.push({});
	return { .ref = tex_sys.textures.last_ref(), .index = (uint)(tex_sys.textures.size - 1) };
}
