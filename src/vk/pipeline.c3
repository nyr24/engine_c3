module engine::vk;

import vk;
import logger;
import std::collections::elastic_array;
import std::io;

const MAX_PIPELINE_CNT = 5u;
const MAX_ATTRIB_CNT = 10u;
const MAX_DESCRIPTOR_BINDING_CNT = 10u;
const MAX_DESCRIPTOR_LAYOUT_CNT = 10u;
const MAX_DESCRIPTOR_POOL_CNT = 10u;
const MAX_PUSH_CONSTANT_RANGE_CNT = 5u;

// VulkanShader & VulkanPipeline

struct VulkanShader
{
    VulkanContext*                                                    	ctx;
	ElasticArray{VulkanPipeline, MAX_PIPELINE_CNT}	                  	pipelines;
    ElasticArray{VulkanDescriptorSetLayout, MAX_DESCRIPTOR_LAYOUT_CNT}	descriptor_layouts;
    ElasticArray{VulkanDescriptorPool, MAX_DESCRIPTOR_POOL_CNT}			descriptor_pools;
    ElasticArray{VkPushConstantRange, MAX_PUSH_CONSTANT_RANGE_CNT}      push_constant_ranges;
	VulkanShaderModule               			                      	mod;
	uint																curr_pipeline;
	VulkanShaderStageKindBits           								stage_bits;

	// TODO:
	// VulkanLocalUniformBufferObject                        local_ubo;
    // FixedArray<Texture*, MAX_DEFAULT_TEXTURES>            preload_textures;
    // FixedArray<Model*, MAX_DEFAULT_MODELS>            	 preload_models;
}

struct VulkanPipeline
{
	VkPipeline       handle;
    VkPipelineLayout layout;
}

struct VulkanDescriptorSetLayout
{
    VkDescriptorSetLayout handle;
}

struct VulkanDescriptorPool
{
	VkDescriptorPool handle;
}

struct VulkanShaderConfig
{
	VulkanShaderStageKindBits           stage_bits;
	VkDescriptorSetLayoutBinding[][]    descriptor_bindings;
    VkVertexInputAttributeDescription[] attrib_descriptions;
	VulkanPipelineConfig[]              pipeline_configs;
	VkPushConstantRange[] 				push_constant_ranges;
	uint                                max_entities_per_frame;
	char                                vertex_binding_index;
}

struct VulkanPipelineConfig
{
	VkPrimitiveTopology                 primitive_topology;
	VkPolygonMode						polygon_mode;
	float								line_width;
	VkSampleCountFlagBits				sample_count;
    bool                                enable_color_blend;
}

struct VulkanShaderModule
{
	VkShaderModule handle;
	ElasticArray{VulkanShaderStage, VulkanShaderStageKind.len} stages;
}

struct VulkanShaderStage
{
	CChar*				  entry_name;
	VulkanShaderStageKind kind;
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

    VkPipelineLayoutCreateInfo pipeline_layouts_ci = {
        .sType = vk::STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
        .setLayoutCount = (uint)shader.descriptor_layouts.size,
        .pSetLayouts = (VkDescriptorSetLayout*)shader.descriptor_layouts.data(),
        .pushConstantRangeCount = (uint)config.push_constant_ranges.len,
        .pPushConstantRanges = config.push_constant_ranges.ptr,
    };

	// will be shared across all pipelines for this shader 
	VkPipelineLayout pipeline_layout;
    vk_check(vk::createPipelineLayout(ctx.dev.log_dev, &pipeline_layouts_ci, ctx.vk_alloc, &pipeline_layout));

	shader.pipelines.resize(config.pipeline_configs.len);

	foreach (&pipe : shader.pipelines) {
		pipe.layout = pipeline_layout;
	}

	foreach (uint i, &pipe_conf : config.pipeline_configs) {
		shader.create_pipeline(
			ctx,
			pipe_conf,
			config.attrib_descriptions,
			config.vertex_binding_index,
			&shader.pipelines[i]
		);
	}
	
	return shader;
}

fn void VulkanShader.create_pipeline(
	&shader,
	VulkanContext* ctx,
	VulkanPipelineConfig* config,
	VkVertexInputAttributeDescription[] attrib_descriptions,
	char vertex_bind_ind,
	VulkanPipeline* out_pipeline,
)
{
    VkDynamicState[2] dynamic_states = { vk::DYNAMIC_STATE_VIEWPORT, vk::DYNAMIC_STATE_SCISSOR };

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
        .colorWriteMask = vk::COLOR_COMPONENT_R_BIT | vk::COLOR_COMPONENT_G_BIT | vk::COLOR_COMPONENT_B_BIT | vk::COLOR_COMPONENT_A_BIT,
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
        // lower depth => write pixel
        .depthCompareOp = vk::COMPARE_OP_LESS,
        .depthBoundsTestEnable = vk::FALSE,
        .stencilTestEnable = vk::FALSE,
    };

	ElasticArray{VkPipelineShaderStageCreateInfo, VulkanShaderStageKind.len} shader_stages;
	shader_stages.resize(shader.mod.stages.size);
	shader.mod.get_shader_stage_infos(shader_stages.array_view());

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

    vk_check(vk::createGraphicsPipelines(ctx.dev.log_dev, null, 1, &pipeline_ci, ctx.vk_alloc, &out_pipeline.handle));
    logger::logn(INFO, "Graphics pipeline was successfully created!");
}

// --- VulkanPipeline ---

fn VulkanPipeline* VulkanShader.get_curr_pipeline(&shader) @inline
{
	return &shader.pipelines[shader.curr_pipeline];
}

fn void VulkanShader.bind_curr_pipeline(
	&shader,
	VulkanCmdBuffer graphics_cmd_buffer,
)
{
	VulkanPipeline* pipeline = shader.get_curr_pipeline();
	pipeline.bind(graphics_cmd_buffer);
}

fn void VulkanShader.bind_descriptor_sets(&shader, VulkanCmdBuffer cmd_buff, VkPipelineBindPoint bind_point, VkDescriptorSet[] descriptor_sets, uint start_index = 0)
{
	VulkanPipeline* pipeline = shader.get_curr_pipeline();
	pipeline.bind_descriptor_sets(cmd_buff, bind_point, descriptor_sets, start_index);
}

fn void VulkanPipeline.bind(
	&pipeline,
	VulkanCmdBuffer graphics_cmd_buffer,
)
{
    vk::cmdBindPipeline(graphics_cmd_buffer.handle, vk::PIPELINE_BIND_POINT_GRAPHICS, pipeline.handle);
}

fn void VulkanPipeline.bind_descriptor_sets(&pipeline, VulkanCmdBuffer cmd_buff, VkPipelineBindPoint bind_point, VkDescriptorSet[] descriptor_sets, uint start_index = 0)
{
    vk::cmdBindDescriptorSets(cmd_buff.handle, bind_point, pipeline.layout, start_index, descriptor_sets.len, descriptor_sets.ptr, 0, null);
}

fn void VulkanShader.create_descriptor_state(&shader, VulkanContext* ctx, VulkanShaderConfig* conf)
{
	uint entity_count = conf.max_entities_per_frame * engine::FRAMES_IN_FLIGHT;

	foreach (uint i, bindings : conf.descriptor_bindings) {
	    ElasticArray{VkDescriptorType, MAX_DESCRIPTOR_BINDING_CNT} descriptor_types;
	    ElasticArray{VkDescriptorPoolSize, MAX_DESCRIPTOR_POOL_CNT} pool_sizes;

		foreach (&binding : bindings) {
			descriptor_types.push(binding.descriptorType);
	        pool_sizes.push({ .type = binding.descriptorType, .descriptorCount = entity_count });
		}

	    shader.descriptor_pools.push(create_descriptor_pool(ctx, pool_sizes.array_view(), entity_count));
		shader.descriptor_layouts.push(create_descriptor_set_layout(ctx, bindings));
	}
}

fn VkVertexInputBindingDescription get_binding_descr(char binding_index)
{
    return {
        .binding = (uint)binding_index,
        .stride = Vertex.sizeof,
        .inputRate = vk::VERTEX_INPUT_RATE_VERTEX,
    };
}

// ---- VulkanShaderModule ---

fn VulkanShaderModule? create_shader_module(
	VulkanContext* ctx,
	String file_name,
	VulkanShaderStageKindBits stage_bits
) => @pool()
{
	DString full_path;
	full_path.tinit(engine::SHADER_PATH.len + file_name.len);
	full_path.append_bytes(engine::SHADER_PATH);
	full_path.append_bytes(file_name);

	char[]? file_contents = file::load(tmem, full_path.str_view());
	if (catch excuse = file_contents) {
		logger::logn(ERROR, "Shader file read failed, path: %s", full_path.str_view());
		return excuse~;
	}
	
    VkShaderModuleCreateInfo create_info = {
        .sType = vk::STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
        .codeSize = file_contents.len,
        .pCode = (uint*)file_contents.ptr,
    };

    VulkanShaderModule shader_module;
	shader_module.init_shader_stages(stage_bits);

    vk_check(vk::createShaderModule(ctx.dev.log_dev, &create_info, ctx.vk_alloc, &shader_module.handle));
    return shader_module;
}

fn void VulkanShaderModule.init_shader_stages(&mod, VulkanShaderStageKindBits stage_bits)
{
	if (stage_bits & VulkanShaderStageKind.VERTEX) {
		mod.stages.push({ (CChar*)engine::VERTEX_SHADER_ENTRY_NAME, VulkanShaderStageKind.VERTEX });
	}
	if (stage_bits & VulkanShaderStageKind.FRAGMENT) {
		mod.stages.push({ (CChar*)engine::FRAGMENT_SHADER_ENTRY_NAME, VulkanShaderStageKind.FRAGMENT });
	}
	if (stage_bits & VulkanShaderStageKind.COMPUTE) {
		mod.stages.push({ (CChar*)engine::COMPUTE_SHADER_ENTRY_NAME, VulkanShaderStageKind.COMPUTE });
	}
	if (stage_bits & VulkanShaderStageKind.GEOMETRY) {
		mod.stages.push({ (CChar*)engine::GEOMETRY_SHADER_ENTRY_NAME, VulkanShaderStageKind.GEOMETRY });
	}
	if (stage_bits & VulkanShaderStageKind.TESSELATION_CONTROL) {
		mod.stages.push({ (CChar*)engine::TESSELATION_CONTROL_SHADER_ENTRY_NAME, VulkanShaderStageKind.TESSELATION_CONTROL });
	}
	if (stage_bits & VulkanShaderStageKind.TESSELATION_EVAL) {
		mod.stages.push({ (CChar*)engine::TESSELATION_EVAL_SHADER_ENTRY_NAME, VulkanShaderStageKind.TESSELATION_EVAL });
	}
}

<*
	@require mod.stages.size == out_stages.len : "Lengths should be equal"
*>
fn void VulkanShaderModule.get_shader_stage_infos(&mod, VkPipelineShaderStageCreateInfo[] out_stages)
{
	foreach (uint i, stage : mod.stages) {
		VkPipelineShaderStageCreateInfo stage_ci;
		stage_ci.sType = vk::STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
		stage_ci.stage = map_shader_stage_to_vk_stage(stage.kind);
		stage_ci.pName = stage.entry_name;
		stage_ci.mod = mod.handle;
		out_stages[i] = stage_ci;
	}
}

fn VkShaderStageFlagBits map_shader_stage_to_vk_stage(VulkanShaderStageKind stage) @private
{
	switch (stage) {
		case VulkanShaderStageKind.VERTEX: return vk::SHADER_STAGE_VERTEX_BIT;
		case VulkanShaderStageKind.FRAGMENT: return  vk::SHADER_STAGE_FRAGMENT_BIT;
		case VulkanShaderStageKind.COMPUTE: return  vk::SHADER_STAGE_COMPUTE_BIT;
		case VulkanShaderStageKind.GEOMETRY: return  vk::SHADER_STAGE_GEOMETRY_BIT;
		case VulkanShaderStageKind.TESSELATION_CONTROL: return  vk::SHADER_STAGE_TESSELLATION_CONTROL_BIT;
		case VulkanShaderStageKind.TESSELATION_EVAL: return  vk::SHADER_STAGE_TESSELLATION_EVALUATION_BIT;
		default: unreachable();
	}
}

// VulkanDescriptorPool

fn VulkanDescriptorPool create_descriptor_pool(VulkanContext* ctx, VkDescriptorPoolSize[] pool_sizes, uint max_sets)
{
	VulkanDescriptorPool pool @noinit;
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
    vk_check(vk::createDescriptorPool(ctx.dev.log_dev, &descriptor_pool_ci, ctx.vk_alloc, &pool.handle)); 
}

<*
	@require layouts.len == sets.len : "Lengths should be equal"
*>
fn void VulkanDescriptorPool.allocate_sets(&pool, VulkanDevice* dev, VulkanDescriptorSetLayout[] layouts, VkDescriptorSet[] sets)
{
    VkDescriptorSetAllocateInfo alloc_info = {
        .sType = vk::STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
        .descriptorPool = pool.handle,
        .descriptorSetCount = layouts.len,
        .pSetLayouts = (VkDescriptorSetLayout*)layouts.ptr,
    };

    vk_check(vk::allocateDescriptorSets(dev.log_dev, &alloc_info, sets.ptr));
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
    vk_check(vk::createDescriptorSetLayout(ctx.dev.log_dev, &layout_ci, ctx.vk_alloc, &layout.handle));
}

<*
	@require descriptor_types.len == out_bindings.len
*>
fn void create_descriptor_bindings(VkShaderStageFlags stage_flags, VkDescriptorType[] descriptor_types, VkDescriptorSetLayoutBinding[] out_bindings)
{
    foreach (uint i, &binding : out_bindings) {
        binding.binding = i;
        binding.descriptorType = descriptor_types[i];
        binding.descriptorCount = 1u;
        binding.stageFlags = stage_flags;
        binding.pImmutableSamplers = null;
    }
}

// destructors

fn void VulkanShader.destroy(&shader, VulkanContext* ctx)
{
	foreach (&layout : shader.descriptor_layouts) {
	    layout.destroy(ctx);
	}
	foreach (&pipe : shader.pipelines) {
		pipe.destroy(ctx);
	}
	foreach (&pool : shader.descriptor_pools) {
	    pool.destroy(ctx);
	}
	shader.mod.destroy(ctx);
}

fn void VulkanPipeline.destroy(&pipe, VulkanContext* ctx)
{
	if (pipe.handle) {
	    vk::destroyPipeline(ctx.dev.log_dev, pipe.handle, ctx.vk_alloc);
		pipe.handle = null;
	}
}

fn void VulkanShaderModule.destroy(&mod, VulkanContext* ctx)
{
	if (mod.handle) {
	    vk::destroyShaderModule(ctx.dev.log_dev, mod.handle, ctx.vk_alloc);
		mod.handle = null;
	}
}

fn void VulkanDescriptorSetLayout.destroy(&layout, VulkanContext* ctx)
{
    if (layout.handle) {
        vk::destroyDescriptorSetLayout(ctx.dev.log_dev, layout.handle, ctx.vk_alloc);
        layout.handle = null;
    }
}

fn void VulkanDescriptorPool.destroy(&pool, VulkanContext* ctx)
{
    if (pool.handle) {
        vk::destroyDescriptorPool(ctx.dev.log_dev, pool.handle, ctx.vk_alloc);
        pool.handle = null;
    }
}
