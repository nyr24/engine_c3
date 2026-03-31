module engine::vk;

import vk;
import logger;
import std::collections::elastic_array;
import std::collections::list;
import std::io;

const MAX_PIPELINE_COUNT            = 5u;
const MAX_ATTRIB_COUNT              = 10u;
const MAX_DESCRIPTOR_BINDING_COUNT  = 10u;
const MAX_DESCRIPTOR_LAYOUT_COUNT   = 10u;
const MAX_DESCRIPTOR_POOL_COUNT     = 10u;
const MAX_PUSH_CONSTANT_RANGE_COUNT = 5u;
const INIT_POOL_COUNT               = 4u;

faultdef POOL_OUT_OF_MEMORY;

// VulkanShader & VulkanPipeline

struct VulkanShader
{
	VulkanContext* ctx;
	ElasticArray{VulkanPipeline, MAX_PIPELINE_COUNT} pipelines;
	ElasticArray{VulkanDescriptorSetLayout, MAX_DESCRIPTOR_LAYOUT_COUNT} descriptor_layouts;
	// for creating new pools easily
	ElasticArray{VkDescriptorPoolSize, MAX_DESCRIPTOR_BINDING_COUNT} pool_sizes;
	List{VulkanDescriptorPool} descriptor_pools;
	VulkanShaderModule mod;
	uint curr_pipeline;
	uint max_entities;
	VulkanShaderStageKindBits stage_bits;
}

struct EntityShaderState
{
	uint sets_start_index;
	ushort sets_len;
	ushort pool_index;
}

struct VulkanPipeline
{
	VkPipeline handle;
	VkPipelineBindPoint bind_point;
	VkPipelineLayout layout;
}

struct VulkanDescriptorSetLayout
{
	VkDescriptorSetLayout handle;
	ElasticArray{VkDescriptorSetLayoutBinding, MAX_DESCRIPTOR_BINDING_COUNT} bindings;
}

// NOTE: knows max_sets from shader
// list can't allocate over max_sets
struct VulkanDescriptorPool
{
	VkDescriptorPool handle;
	List{VkDescriptorSet} sets;
}

struct VulkanShaderConfig
{
	VulkanShaderStageKindBits stage_bits;
	DescriptorSetInfo[] descriptor_set_infos;
	VkVertexInputAttributeDescription[] attrib_descriptions;
	VulkanPipelineConfig[] pipeline_configs;
	VkPushConstantRange[] push_constant_ranges;
	uint max_entities_per_frame;
	char vertex_binding_index;
}

struct VulkanPipelineConfig
{
	VkPipelineBindPoint bind_point;
	VkPrimitiveTopology primitive_topology;
	VkPolygonMode polygon_mode;
	float line_width;
	VkSampleCountFlagBits sample_count;
	bool enable_color_blend;
}

struct VulkanShaderModule
{
	VkShaderModule handle;
	// TODO: make this a bit mask
	ElasticArray{VulkanShaderStage, VulkanShaderStageKind::len} stages;
}

struct VulkanShaderStage
{
	ZString entry_name;
	VulkanShaderStageKind kind;
}

struct PoolAllocationResult
{
	uint start_index;
	ushort len;
}

struct DescriptorSetInfo
{
	VkDescriptorSetLayoutBinding[] bindings;
	VkDescriptorType[] types;
}

struct DescriptorUpdateInfo
{
	uint set_index;
	VkDescriptorType type;
	union
	{
		VkDescriptorImageInfo image_info;
		VkDescriptorBufferInfo buff_info;
		VkBufferView* texel_buff_info;
	}
}

constdef VulkanShaderStageKind : inline char
{
	VERTEX              = 1 << 0,
	FRAGMENT            = 1 << 1,
	COMPUTE             = 1 << 2,
	GEOMETRY            = 1 << 3,
	TESSELATION_CONTROL = 1 << 4,
	TESSELATION_EVAL    = 1 << 5,
}

alias VulkanShaderStageKindBits = char;

fn VulkanShader create_shader(VulkanContext* ctx, String file_name, VulkanShaderConfig* config)
{
	VulkanShader shader;
	shader.ctx = ctx;
	shader.mod = create_shader_module(ctx, file_name, config.stage_bits)!!;
	shader.stage_bits = config.stage_bits;

	shader.create_descriptor_state(ctx, config);

	ElasticArray{VkDescriptorSetLayout, MAX_DESCRIPTOR_LAYOUT_COUNT} layouts;
	foreach (layout : shader.descriptor_layouts)
	{
		layouts.push(layout.handle);
	}

	VkPipelineLayoutCreateInfo pipeline_layouts_ci = {
		.sType = vk::STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
		.setLayoutCount = (uint)layouts.size,
		.pSetLayouts = layouts.data(),
		.pushConstantRangeCount = (uint)config.push_constant_ranges.len,
		.pPushConstantRanges = config.push_constant_ranges.ptr,
	};

	// will be shared across all pipelines for this shader
	VkPipelineLayout pipeline_layout;
	check(vk::createPipelineLayout(ctx.dev.log_dev, &pipeline_layouts_ci, ctx.vk_alloc, &pipeline_layout));

	shader.pipelines.resize(config.pipeline_configs.len);

	foreach (&pipe : shader.pipelines)
	{
		pipe.layout = pipeline_layout;
	}

	foreach (uint i, &pipe_conf : config.pipeline_configs)
	{
		shader.create_pipeline(
			&shader.pipelines[i],
			ctx,
			pipe_conf,
			config.attrib_descriptions,
			config.vertex_binding_index,
		);
	}

	return shader;
}

fn void VulkanShader.create_pipeline(
	&shader,
	VulkanPipeline* out_pipeline,
	VulkanContext* ctx,
	VulkanPipelineConfig* config,
	VkVertexInputAttributeDescription[] attrib_descriptions,
	char vertex_bind_ind,
)
{
	VkDynamicState[*] dynamic_states = { vk::DYNAMIC_STATE_VIEWPORT, vk::DYNAMIC_STATE_SCISSOR };

	VkPipelineDynamicStateCreateInfo dynamic_state = {
		.sType = vk::STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO,
		.dynamicStateCount = (uint)dynamic_states.len,
		.pDynamicStates = &dynamic_states,
	};

	VkVertexInputBindingDescription binding_descr = get_binding_descr(vertex_bind_ind);

	VkPipelineVertexInputStateCreateInfo vertex_ci = {
		.sType = vk::STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
		.vertexBindingDescriptionCount = 1,
		.pVertexBindingDescriptions = &binding_descr,
		.vertexAttributeDescriptionCount = (uint)attrib_descriptions.len,
		.pVertexAttributeDescriptions = attrib_descriptions.ptr,
	};

	VkPipelineInputAssemblyStateCreateInfo input_assembly_ci = {
		.sType = vk::STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
		.topology = config.primitive_topology,
	};

	VkPipelineViewportStateCreateInfo viewport_ci = {
		.sType = vk::STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,
		.viewportCount = 1,
		.pViewports = &ctx.renderer.viewport,
		.scissorCount = 1,
        .pScissors = &ctx.renderer.scissors
	};

	VkPipelineRasterizationStateCreateInfo rasterization_ci = {
		.sType = vk::STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
		.depthClampEnable = vk::FALSE,
		.rasterizerDiscardEnable = vk::FALSE,
		.polygonMode = config.polygon_mode,
		.cullMode = vk::CULL_MODE_BACK_BIT,
		.frontFace = vk::FRONT_FACE_COUNTER_CLOCKWISE,
		.depthBiasEnable = vk::FALSE,
		.lineWidth = config.line_width,
	};

	VkPipelineMultisampleStateCreateInfo multisample_ci = {
		.sType = vk::STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
		.rasterizationSamples = config.sample_count,
		.sampleShadingEnable = vk::FALSE,
	};

	VkPipelineColorBlendAttachmentState color_blending_attachment = {
		.blendEnable = (VkBool32)config.enable_color_blend,
		.srcColorBlendFactor = vk::BLEND_FACTOR_SRC_ALPHA,
		.dstColorBlendFactor = vk::BLEND_FACTOR_ONE_MINUS_SRC_ALPHA,
		.colorBlendOp = vk::BLEND_OP_ADD,
		.srcAlphaBlendFactor = vk::BLEND_FACTOR_ONE,
		.dstAlphaBlendFactor = vk::BLEND_FACTOR_ZERO,
		.alphaBlendOp = vk::BLEND_OP_ADD,
		.colorWriteMask = vk::COLOR_COMPONENT_R_BIT | vk::COLOR_COMPONENT_G_BIT | vk::COLOR_COMPONENT_B_BIT
			| vk::COLOR_COMPONENT_A_BIT,
	};

	VkPipelineColorBlendStateCreateInfo color_blending_state = {
		.logicOpEnable = vk::FALSE,
		.logicOp = vk::LOGIC_OP_COPY,
		.attachmentCount = 1,
		.pAttachments = &color_blending_attachment,
	};

	VkPipelineRenderingCreateInfo rendering_ci = {
		.sType = vk::STRUCTURE_TYPE_PIPELINE_RENDERING_CREATE_INFO,
		.colorAttachmentCount = 1,
		.pColorAttachmentFormats = &ctx.swapchain.surface_fmt.format,
		.depthAttachmentFormat = ctx.dev.depth_fmt,
	};

	VkPipelineDepthStencilStateCreateInfo depth_stencil_state = {
		.sType = vk::STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
		.pNext = null,
		.depthTestEnable = vk::TRUE,
		.depthWriteEnable = vk::TRUE,
		.depthCompareOp = vk::COMPARE_OP_LESS, // lower depth => write pixel
		.depthBoundsTestEnable = vk::FALSE,
		.stencilTestEnable = vk::FALSE,
	};

	ElasticArray{VkPipelineShaderStageCreateInfo, VulkanShaderStageKind::len} shader_stages;
	shader_stages.resize(shader.mod.stages.size);
	shader.mod.get_shader_stage_infos(shader_stages.view());

	VkGraphicsPipelineCreateInfo pipeline_ci = {
		.sType = vk::STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,
		.pNext = &rendering_ci,
		.stageCount = (uint)shader_stages.size,
		.pStages = shader_stages.data(),
		.pVertexInputState = &vertex_ci,
		.pInputAssemblyState = &input_assembly_ci,
		.pViewportState = &viewport_ci,
		.pRasterizationState = &rasterization_ci,
		.pMultisampleState = &multisample_ci,
		.pDepthStencilState = &depth_stencil_state,
		.pColorBlendState = &color_blending_state,
		.pDynamicState = &dynamic_state,
		.layout = out_pipeline.layout,
		.renderPass = null,
		.basePipelineHandle = (VkPipeline)null,
		.basePipelineIndex = -1,
	};

	check(vk::createGraphicsPipelines(ctx.dev.log_dev, null, 1, &pipeline_ci, ctx.vk_alloc, &out_pipeline.handle));
	out_pipeline.bind_point = config.bind_point;
	
	logger::logn(INFO, "Pipeline was successfully created!");
}

// --- VulkanPipeline ---

fn VulkanPipeline* VulkanShader.get_curr_pipeline(&shader) @inline
{
	return &shader.pipelines[shader.curr_pipeline];
}

fn void VulkanShader.cmd_bind_curr_pipeline(&shader, VulkanCmdBuffer cmd_buffer)
{
	VulkanPipeline* pipeline = shader.get_curr_pipeline();
	pipeline.cmd_bind(cmd_buffer);
}

fn void VulkanPipeline.cmd_bind(&pipeline, VulkanCmdBuffer cmd_buffer)
{
	vk::cmdBindPipeline(cmd_buffer.handle, pipeline.bind_point, pipeline.handle);
}

fn void VulkanShader.create_descriptor_state(&shader, VulkanContext* ctx, VulkanShaderConfig* conf)
{
	shader.max_entities = conf.max_entities_per_frame;

	// create layout for each set
	foreach (uint i, set_info : conf.descriptor_set_infos)
	{
		shader.descriptor_layouts.push(create_descriptor_set_layout(ctx, set_info.bindings));
		foreach (type : set_info.types)
		{
			shader.pool_sizes.push({ type, shader.max_entities * engine::FRAMES_IN_FLIGHT });
		}
	}

	shader.descriptor_pools.init(&ctx.app_ctx.persistent_alloc, INIT_POOL_COUNT);
	shader.allocate_pool(ctx);
}

fn VulkanDescriptorPool* VulkanShader.allocate_pool(&shader, VulkanContext* ctx)
{
	shader.descriptor_pools.push(
		create_descriptor_pool(ctx, shader.pool_sizes.view(), shader.max_entities * engine::FRAMES_IN_FLIGHT)
	);
	return shader.descriptor_pools.last_ref();
}

<*
 @require shader.descriptor_layouts.size > 0 : "Should be more than 0 layouts in the shader"
*>
fn EntityShaderState VulkanShader.acquire_entity_resources(&shader, VulkanContext* ctx)
{
	// doubling layouts for each frame in flight
	ElasticArray{VkDescriptorSetLayout, MAX_DESCRIPTOR_LAYOUT_COUNT * engine::FRAMES_IN_FLIGHT} all_layouts;

	for (uint i = 0; i < engine::FRAMES_IN_FLIGHT; ++i)
	{
		foreach (uint j, layout : shader.descriptor_layouts)
		{
			all_layouts.push(layout.handle);
		}
	}

	foreach (ushort i, &pool : shader.descriptor_pools)
	{
		if (try PoolAllocationResult alloc_res = pool.allocate_sets(&ctx.dev, all_layouts.view()))
		{
			return { .pool_index = i, .sets_start_index = alloc_res.start_index, .sets_len = alloc_res.len };
		}
	}

	VulkanDescriptorPool* new_pool = shader.allocate_pool(ctx);
	PoolAllocationResult alloc_res = new_pool.allocate_sets(&ctx.dev, all_layouts.view())!!;
	return {
		.pool_index = (ushort)(shader.descriptor_pools.size - 1),
		.sets_start_index = alloc_res.start_index,
		.sets_len = alloc_res.len
	};
}

fn VkDescriptorSet[] VulkanShader.access_entity_resources(
	&shader,
	EntityShaderState entity_state,
	uint curr_frame
)
{
	return shader.descriptor_pools[entity_state.pool_index].access_sets(
		entity_state.sets_start_index,
		entity_state.sets_len
	)[curr_frame * shader.descriptor_layouts.size : shader.descriptor_layouts.size];
}

fn void VulkanShader.free_entity_resources(&shader, VulkanContext* ctx, EntityShaderState entity_state)
{
	shader.descriptor_pools[entity_state.pool_index].free_sets(
		ctx,
		entity_state.sets_start_index,
		entity_state.sets_len
	);
}

fn void VulkanShader.update_entity_resources(
	&shader,
	VulkanContext* ctx,
	EntityShaderState entity_state,
	DescriptorUpdateInfo[] update_infos,
	uint curr_frame
)
{
	VkDescriptorSet[] entity_sets = shader.access_entity_resources(entity_state, curr_frame);
	ElasticArray{VkWriteDescriptorSet, MAX_DESCRIPTOR_BINDING_COUNT} writes;

	foreach (uint i, &update_info : update_infos)
	{
		VkWriteDescriptorSet write = {
			.sType = vk::STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
			.dstSet = entity_sets[update_info.set_index],
			.dstBinding = i,
			.descriptorCount = 1,
			.descriptorType = update_info.type,
		};

		switch (update_info.type)
		{
			case vk::DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER:
				write.pImageInfo = &update_info.image_info;
			case vk::DESCRIPTOR_TYPE_UNIFORM_BUFFER:
				write.pBufferInfo = &update_info.buff_info;
			case vk::DESCRIPTOR_TYPE_UNIFORM_TEXEL_BUFFER:
				write.pTexelBufferView = update_info.texel_buff_info;
			default:
				unreachable("Unknown descriptor set update info type: %s", update_info.type);
		}
		writes.push(write);
	}

	VkWriteDescriptorSet[] writes_view = writes.view();
	vk::updateDescriptorSets(ctx.dev.log_dev, writes_view.len, writes_view.ptr, 0, null);
}

<*
 Uses current shader pipeline to bind sets
*>
fn void VulkanShader.cmd_bind_entity_resources(
	&shader,
	VulkanCmdBuffer cmd_buff,
	EntityShaderState entity_state,
	VulkanPipeline* pipeline,
	uint curr_frame,
	uint first_set = 0,
)
{
	VkDescriptorSet[] entity_sets = shader.access_entity_resources(entity_state, curr_frame);
	cmd_bind_descriptor_sets(cmd_buff, pipeline, entity_sets);
}

// VulkanDescriptorPool

fn VulkanDescriptorPool create_descriptor_pool(VulkanContext* ctx, VkDescriptorPoolSize[] pool_sizes, uint max_sets)
{
	VulkanDescriptorPool pool;
	pool.init(ctx, pool_sizes, max_sets);
	return pool;
}

fn void VulkanDescriptorPool.init(&pool, VulkanContext* ctx, VkDescriptorPoolSize[] pool_sizes, uint max_sets)
{
	VkDescriptorPoolCreateInfo descriptor_pool_ci = {
		.sType = vk::STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
		.maxSets = max_sets,
		.poolSizeCount = (uint)pool_sizes.len,
		.pPoolSizes = pool_sizes.ptr,
	};
	check(vk::createDescriptorPool(ctx.dev.log_dev, &descriptor_pool_ci, ctx.vk_alloc, &pool.handle));
	pool.sets.init(&ctx.app_ctx.persistent_alloc, max_sets);
}

fn PoolAllocationResult? VulkanDescriptorPool.allocate_sets(&pool, VulkanDevice* dev, VkDescriptorSetLayout[] layouts,)
{
	if (pool.sets.size + layouts.len > pool.sets.capacity)
	{
		return POOL_OUT_OF_MEMORY~;
	}

	VkDescriptorSetAllocateInfo alloc_info = {
		.sType = vk::STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
		.descriptorPool = pool.handle,
		.descriptorSetCount = layouts.len,
		.pSetLayouts = (VkDescriptorSetLayout*)layouts.ptr,
	};

	VkDescriptorSet* allocated_sets = pool.sets.entries + pool.sets.size;
	check(vk::allocateDescriptorSets(dev.log_dev, &alloc_info, allocated_sets));
	PoolAllocationResult alloc_res = { .start_index = (uint)pool.sets.size, .len = (ushort)layouts.len };
	pool.sets.move_forward(layouts.len);
	return alloc_res;
}

fn VkDescriptorSet[] VulkanDescriptorPool.access_sets(&pool, uint index, uint len)
{
	return pool.sets.view_range_len(index, len);
}

fn void VulkanDescriptorPool.free_sets(&pool, VulkanContext* ctx, uint start, ushort len)
{
	VkDescriptorSet[] sets_to_free = pool.sets.view_range_len(start, len);
	check(vk::freeDescriptorSets(ctx.dev.log_dev, pool.handle, sets_to_free.len, sets_to_free.ptr));
}

// VulkanDescriptorSetLayout

fn VulkanDescriptorSetLayout create_descriptor_set_layout(VulkanContext* ctx, VkDescriptorSetLayoutBinding[] bindings)
{
	VulkanDescriptorSetLayout layout @noinit;
	layout.init(ctx, bindings);
	return layout;
}

fn void VulkanDescriptorSetLayout.init(&layout, VulkanContext* ctx, VkDescriptorSetLayoutBinding[] bindings)
{
	VkDescriptorSetLayoutCreateInfo layout_ci = {
		.sType = vk::STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
		.bindingCount = bindings.len,
		.pBindings = bindings.ptr,
	};
	layout.bindings.push_all(bindings);
	check(vk::createDescriptorSetLayout(ctx.dev.log_dev, &layout_ci, ctx.vk_alloc, &layout.handle));
}

<*
 @require descriptor_types.len == out_bindings.len
*>
fn void init_descriptor_bindings(
	VkShaderStageFlags stage_flags,
	VkDescriptorType[] descriptor_types,
	VkDescriptorSetLayoutBinding[] out_bindings
)
{
	foreach (uint i, &binding : out_bindings)
	{
		binding.binding = i;
		binding.descriptorType = descriptor_types[i];
		binding.descriptorCount = 1u;
		binding.stageFlags = stage_flags;
		binding.pImmutableSamplers = null;
	}
}

// ---- VulkanShaderModule ---

fn VulkanShaderModule? create_shader_module(
	VulkanContext* ctx,
	String file_name,
	VulkanShaderStageKindBits stage_bits
) => @pool()
{
	DString full_path;
	full_path.tinit(engine::SHADERS_PATH.len + file_name.len);
	full_path.append_bytes(engine::SHADERS_PATH);
	full_path.append_bytes(file_name);

	char[]? file_contents = file::load(tmem, full_path.str_view());
	if (catch err = file_contents)
	{
		logger::logn(ERROR, "Shader file read failed, path: %s", full_path.str_view());
		return err~;
	}

	VkShaderModuleCreateInfo create_info = {
		.sType = vk::STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
		.codeSize = file_contents.len,
		.pCode = (uint*)file_contents.ptr,
	};

	VulkanShaderModule shader_module;
	shader_module.init_shader_stages(stage_bits);

	check(vk::createShaderModule(ctx.dev.log_dev, &create_info, ctx.vk_alloc, &shader_module.handle));
	return shader_module;
}

fn void VulkanShaderModule.init_shader_stages(&mod, VulkanShaderStageKindBits stage_bits)
{
	if (stage_bits & VulkanShaderStageKind.VERTEX)
	{
		mod.stages.push({ engine::VERTEX_SHADER_ENTRY_NAME, VulkanShaderStageKind.VERTEX });
	}
	if (stage_bits & VulkanShaderStageKind.FRAGMENT)
	{
		mod.stages.push({ engine::FRAGMENT_SHADER_ENTRY_NAME, VulkanShaderStageKind.FRAGMENT });
	}
	if (stage_bits & VulkanShaderStageKind.COMPUTE)
	{
		mod.stages.push({ engine::COMPUTE_SHADER_ENTRY_NAME, VulkanShaderStageKind.COMPUTE });
	}
	if (stage_bits & VulkanShaderStageKind.GEOMETRY)
	{
		mod.stages.push({ engine::GEOMETRY_SHADER_ENTRY_NAME, VulkanShaderStageKind.GEOMETRY });
	}
	if (stage_bits & VulkanShaderStageKind.TESSELATION_CONTROL)
	{
		mod.stages.push({ engine::TESSELATION_CONTROL_SHADER_ENTRY_NAME, VulkanShaderStageKind.TESSELATION_CONTROL });
	}
	if (stage_bits & VulkanShaderStageKind.TESSELATION_EVAL)
	{
		mod.stages.push({ engine::TESSELATION_EVAL_SHADER_ENTRY_NAME, VulkanShaderStageKind.TESSELATION_EVAL });
	}
}

<*
 @require mod.stages.size == out_stages.len : "Lengths should be equal"
*>
fn void VulkanShaderModule.get_shader_stage_infos(&mod, VkPipelineShaderStageCreateInfo[] out_stages)
{
	foreach (uint i, stage : mod.stages)
	{
		VkPipelineShaderStageCreateInfo stage_ci;
		stage_ci.sType = vk::STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
		stage_ci.stage = map_shader_stage_to_vk_stage(stage.kind);
		stage_ci.pName = (CChar*)stage.entry_name;
		stage_ci.mod = mod.handle;
		out_stages[i] = stage_ci;
	}
}

fn VkShaderStageFlagBits map_shader_stage_to_vk_stage(VulkanShaderStageKind stage) @private
{
	switch (stage)
	{
		case VulkanShaderStageKind.VERTEX: return vk::SHADER_STAGE_VERTEX_BIT;
		case VulkanShaderStageKind.FRAGMENT: return vk::SHADER_STAGE_FRAGMENT_BIT;
		case VulkanShaderStageKind.COMPUTE: return vk::SHADER_STAGE_COMPUTE_BIT;
		case VulkanShaderStageKind.GEOMETRY: return vk::SHADER_STAGE_GEOMETRY_BIT;
		case VulkanShaderStageKind.TESSELATION_CONTROL: return vk::SHADER_STAGE_TESSELLATION_CONTROL_BIT;
		case VulkanShaderStageKind.TESSELATION_EVAL: return vk::SHADER_STAGE_TESSELLATION_EVALUATION_BIT;
		default: unreachable();
	}
}

fn VkVertexInputBindingDescription get_binding_descr(char binding_index) @inline
{
	return { .binding = (uint)binding_index, .stride = Vertex::size, .inputRate = vk::VERTEX_INPUT_RATE_VERTEX, };
}

// destructors

fn void VulkanShader.destroy(&shader, VulkanContext* ctx)
{
	foreach (&layout : shader.descriptor_layouts)
	{
		layout.destroy(ctx);
	}
	foreach (&pipe : shader.pipelines)
	{
		pipe.destroy(ctx);
	}
	foreach (&pool : shader.descriptor_pools)
	{
		pool.destroy(ctx);
	}
	shader.mod.destroy(ctx);
}

fn void VulkanPipeline.destroy(&pipe, VulkanContext* ctx)
{
	if (pipe.handle)
	{
		vk::destroyPipeline(ctx.dev.log_dev, pipe.handle, ctx.vk_alloc);
		pipe.handle = null;
	}
}

fn void VulkanShaderModule.destroy(&mod, VulkanContext* ctx)
{
	if (mod.handle)
	{
		vk::destroyShaderModule(ctx.dev.log_dev, mod.handle, ctx.vk_alloc);
		mod.handle = null;
	}
}

fn void VulkanDescriptorSetLayout.destroy(&layout, VulkanContext* ctx)
{
	if (layout.handle)
	{
		vk::destroyDescriptorSetLayout(ctx.dev.log_dev, layout.handle, ctx.vk_alloc);
		layout.handle = null;
	}
}

fn void VulkanDescriptorPool.destroy(&pool, VulkanContext* ctx)
{
	if (pool.handle)
	{
		vk::destroyDescriptorPool(ctx.dev.log_dev, pool.handle, ctx.vk_alloc);
		pool.handle = null;
	}
}
