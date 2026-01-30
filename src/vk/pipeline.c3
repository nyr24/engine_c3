module vk;

import std::collections::elastic_array;
import std::io;
import constants;
import logger;
import mesh;

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
	ElasticArray{VulkanShaderStage, (uint)VulkanShaderStageKind._COUNT} stages;
}

struct VulkanShaderStage
{
	CChar*				  entry_name;
	VulkanShaderStageKind kind;
}

enum VulkanShaderStageKind : const inline char
{
	VERTEX              = 1 << 0,
	FRAGMENT            = 1 << 1,
	COMPUTE             = 1 << 2,
	GEOMETRY            = 1 << 3,
	TESSELATION_CONTROL = 1 << 4,
	TESSELATION_EVAL    = 1 << 5,
	_COUNT
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
        .s_type = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
        .set_layout_count = (uint)shader.descriptor_layouts.size,
        .p_set_layouts = (VkDescriptorSetLayout*)shader.descriptor_layouts.data(),
        .push_constant_range_count = (uint)config.push_constant_ranges.len,
        .p_push_constant_ranges = config.push_constant_ranges.ptr,
    };

	// will be shared across all pipelines for this shader 
	VkPipelineLayout pipeline_layout;
    vk_check(vkCreatePipelineLayout(ctx.dev.log_dev, &pipeline_layouts_ci, ctx.vk_alloc, &pipeline_layout));

	shader.pipelines.resize(config.pipeline_configs.len);

	foreach (&pipe : shader.pipelines) {
		pipe.layout = pipeline_layout;
	}

	foreach (uint ii, &pipe_conf : config.pipeline_configs) {
		shader.create_pipeline(
			ctx,
			pipe_conf,
			config.attrib_descriptions,
			config.vertex_binding_index,
			&shader.pipelines[ii]
		);
	}
	
	return shader;
}

fn VulkanShaderModule? create_shader_module(VulkanContext* ctx, String file_name, VulkanShaderStageKindBits stage_bits) @private
{
	DString full_path;
	full_path.init(ctx.app_ctx.temp_alloc, constants::SHADER_PATH.len + file_name.len);
	defer full_path.free();
	full_path.append_bytes(constants::SHADER_PATH);
	full_path.append_bytes(file_name);

	char[]? file_contents = file::load(ctx.app_ctx.temp_alloc, full_path.str_view());
	if (catch excuse = file_contents) {
		logger::@logn(LogLevel.ERROR, "Shader file read failed, path: %s", full_path.str_view());
		return excuse~;
	}
	defer ctx.app_ctx.temp_alloc.release(file_contents.ptr, false);
	
    VkShaderModuleCreateInfo create_info = {
        .s_type = VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
        .code_size = file_contents.len,
        .p_code = (uint*)file_contents.ptr,
    };

    VulkanShaderModule shader_module;
	shader_module.init_shader_stages(stage_bits);

    vk_check(vkCreateShaderModule(ctx.dev.log_dev, &create_info, ctx.vk_alloc, &shader_module.handle));
    return shader_module;
}

fn void VulkanShaderModule.init_shader_stages(&mod, VulkanShaderStageKindBits stage_bits) @private
{
	if (stage_bits & VulkanShaderStageKind.VERTEX) {
		mod.stages.push({ (CChar*)constants::VERTEX_SHADER_ENTRY_NAME.ptr, VulkanShaderStageKind.VERTEX });
	}
	if (stage_bits & VulkanShaderStageKind.FRAGMENT) {
		mod.stages.push({ (CChar*)constants::FRAGMENT_SHADER_ENTRY_NAME.ptr, VulkanShaderStageKind.FRAGMENT });
	}
	if (stage_bits & VulkanShaderStageKind.COMPUTE) {
		mod.stages.push({ (CChar*)constants::COMPUTE_SHADER_ENTRY_NAME.ptr, VulkanShaderStageKind.COMPUTE });
	}
	if (stage_bits & VulkanShaderStageKind.GEOMETRY) {
		mod.stages.push({ (CChar*)constants::GEOMETRY_SHADER_ENTRY_NAME.ptr, VulkanShaderStageKind.GEOMETRY });
	}
	if (stage_bits & VulkanShaderStageKind.TESSELATION_CONTROL) {
		mod.stages.push({ (CChar*)constants::TESSELATION_CONTROL_SHADER_ENTRY_NAME.ptr, VulkanShaderStageKind.TESSELATION_CONTROL });
	}
	if (stage_bits & VulkanShaderStageKind.TESSELATION_EVAL) {
		mod.stages.push({ (CChar*)constants::TESSELATION_EVAL_SHADER_ENTRY_NAME.ptr, VulkanShaderStageKind.TESSELATION_EVAL });
	}
}

<*
	@require mod.stages.size == out_stages.len : "Lengths should be equal"
*>
fn void VulkanShaderModule.get_shader_stage_infos(&mod, VkPipelineShaderStageCreateInfo[] out_stages) @private
{
	foreach (uint i, stage : mod.stages) {
		VkPipelineShaderStageCreateInfo stage_ci;
		stage_ci.s_type = VK_STRUCTURE_TYPE_SHADER_CREATE_INFO_EXT;
		stage_ci.stage = map_shader_stage_to_vk_stage(stage.kind);
		stage_ci.p_name = stage.entry_name;
		stage_ci.mod = mod.handle;
		out_stages[i] = stage_ci;
	}
}

fn VkShaderStageFlagBits map_shader_stage_to_vk_stage(VulkanShaderStageKind stage) @private
{
	switch (stage) {
		case VulkanShaderStageKind.VERTEX: return VK_SHADER_STAGE_VERTEX_BIT;
		case VulkanShaderStageKind.FRAGMENT: return  VK_SHADER_STAGE_FRAGMENT_BIT;
		case VulkanShaderStageKind.COMPUTE: return  VK_SHADER_STAGE_COMPUTE_BIT;
		case VulkanShaderStageKind.GEOMETRY: return  VK_SHADER_STAGE_GEOMETRY_BIT;
		case VulkanShaderStageKind.TESSELATION_CONTROL: return  VK_SHADER_STAGE_TESSELLATION_CONTROL_BIT;
		case VulkanShaderStageKind.TESSELATION_EVAL: return  VK_SHADER_STAGE_TESSELLATION_EVALUATION_BIT;
		default: unreachable();
	}
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
    VkDynamicState[2] dynamic_states = { VK_DYNAMIC_STATE_VIEWPORT, VK_DYNAMIC_STATE_SCISSOR };

    VkPipelineDynamicStateCreateInfo dynamic_state = {
        .s_type = VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO,
        .dynamic_state_count = (uint)dynamic_states.len,
        .p_dynamic_states = &dynamic_states,
    };

    VkVertexInputBindingDescription binding_descr = get_binding_descr(vertex_bind_ind);

    VkPipelineVertexInputStateCreateInfo vertex_ci = {
        .s_type = VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
        .vertex_binding_description_count = 1,
        .p_vertex_binding_descriptions = &binding_descr,
        .vertex_attribute_description_count = (uint)attrib_descriptions.len,
        .p_vertex_attribute_descriptions = attrib_descriptions.ptr,
    };

    VkPipelineInputAssemblyStateCreateInfo input_assembly_ci = {
        .s_type = VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
        .topology = config.primitive_topology,
    };

	
    VkPipelineViewportStateCreateInfo viewport_ci = {
        .s_type = VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,
        .viewport_count = 1,
        .p_viewports = &ctx.renderer.viewport,
        .scissor_count = 1,
        .p_scissors = &ctx.renderer.scissors
    };

    VkPipelineRasterizationStateCreateInfo rasterization_ci = {
        .s_type = VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
        .depth_clamp_enable = VK_FALSE,
        .rasterizer_discard_enable = VK_FALSE,
        .polygon_mode = config.polygon_mode,
        .cull_mode = VK_CULL_MODE_BACK_BIT,
        .front_face = VK_FRONT_FACE_COUNTER_CLOCKWISE,
        .depth_bias_enable = VK_FALSE,
        .depth_bias_slope_factor = 1.0f,
        .line_width = config.line_width,
    };

    VkPipelineMultisampleStateCreateInfo multisample_ci = {
        .s_type = VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
        .rasterization_samples = config.sample_count,
        .sample_shading_enable = VK_FALSE,
    };

    VkPipelineColorBlendAttachmentState color_blending_attachment = {
        .blend_enable = (VkBool32)config.enable_color_blend,
        .src_color_blend_factor = VK_BLEND_FACTOR_SRC_ALPHA,
        .dst_color_blend_factor = VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA,
        .color_blend_op = VK_BLEND_OP_ADD,
        .src_alpha_blend_factor = VK_BLEND_FACTOR_ONE,
        .dst_alpha_blend_factor = VK_BLEND_FACTOR_ZERO,
        .alpha_blend_op = VK_BLEND_OP_ADD,
        .color_write_mask = VK_COLOR_COMPONENT_R_BIT | VK_COLOR_COMPONENT_G_BIT | VK_COLOR_COMPONENT_B_BIT | VK_COLOR_COMPONENT_A_BIT,
    };

    VkPipelineColorBlendStateCreateInfo color_blending_state = {
        .logic_op_enable = VK_FALSE,
        .logic_op = VK_LOGIC_OP_COPY,
        .attachment_count = 1,
        .p_attachments = &color_blending_attachment,
    };

    VkPipelineRenderingCreateInfo rendering_ci = {
        .s_type = VK_STRUCTURE_TYPE_PIPELINE_RENDERING_CREATE_INFO,
        .color_attachment_count = 1,
        .p_color_attachment_formats = &ctx.swapchain.surface_fmt.format,
        .depth_attachment_format = ctx.dev.depth_fmt,
    };

    VkPipelineDepthStencilStateCreateInfo depth_stencil_state = {
        .s_type = VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
        .p_next = null,
        .depth_test_enable = VK_TRUE,
        .depth_write_enable = VK_TRUE,
        // lower depth => write pixel
        .depth_compare_op = VK_COMPARE_OP_LESS,
        .depth_bounds_test_enable = VK_FALSE,
        .stencil_test_enable = VK_FALSE,
    };

	ElasticArray{VkPipelineShaderStageCreateInfo, (uint)VulkanShaderStageKind._COUNT} shader_stages;
	shader_stages.resize(shader.mod.stages.size);
	shader.mod.get_shader_stage_infos(shader_stages.array_view());

    VkGraphicsPipelineCreateInfo pipeline_ci = {
        .s_type = VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,
        .p_next = &rendering_ci,
        .stage_count = (uint)shader_stages.size,
        .p_stages = shader_stages.data(),
        .p_vertex_input_state = &vertex_ci,
        .p_input_assembly_state = &input_assembly_ci,
        .p_viewport_state = &viewport_ci,
        .p_rasterization_state = &rasterization_ci,
        .p_multisample_state = &multisample_ci,
        .p_depth_stencil_state = &depth_stencil_state,
        .p_color_blend_state = &color_blending_state,
        .p_dynamic_state = &dynamic_state,
        .layout = out_pipeline.layout,
        .render_pass = null,
        .base_pipeline_handle = VK_NULL_HANDLE,
        .base_pipeline_index = -1,
    };

    vk_check(vkCreateGraphicsPipelines(ctx.dev.log_dev, null, 1, &pipeline_ci, ctx.vk_alloc, &out_pipeline.handle));
    logger::@logn(INFO, "Graphics pipeline was successfully created!");
}

fn void VulkanShader.create_descriptor_state(&shader, VulkanContext* ctx, VulkanShaderConfig* conf)
{
	uint entity_count = conf.max_entities_per_frame * constants::FRAMES_IN_FLIGHT;

	foreach (uint i, bindings : conf.descriptor_bindings) {
	    ElasticArray{VkDescriptorType, MAX_DESCRIPTOR_BINDING_CNT} descriptor_types;
	    ElasticArray{VkDescriptorPoolSize, MAX_DESCRIPTOR_POOL_CNT} pool_sizes;

		foreach (&binding : bindings) {
			descriptor_types.push(binding.descriptor_type);
	        pool_sizes.push({ .type = binding.descriptor_type, .descriptor_count = entity_count });
		}

	    shader.descriptor_pools.push(create_descriptor_pool(ctx, pool_sizes.array_view(), entity_count));
		shader.descriptor_layouts.push(create_descriptor_set_layout(ctx, bindings));
	}
}

fn VkVertexInputBindingDescription get_binding_descr(char binding_index)
{
    return {
        .binding = (uint)binding_index,
        .stride = mesh::Vertex.sizeof,
        .input_rate = VK_VERTEX_INPUT_RATE_VERTEX,
    };
}

// VulkanDescriptorPool

struct VulkanDescriptorPool
{
	VkDescriptorPool handle;
}

fn VulkanDescriptorPool create_descriptor_pool(VulkanContext* ctx, VkDescriptorPoolSize[] pool_sizes, uint max_sets)
{
	VulkanDescriptorPool pool @noinit;
    VkDescriptorPoolCreateInfo descriptor_pool_ci = {
        .s_type = VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
        .max_sets = max_sets,
        .pool_size_count = (uint)pool_sizes.len,
        .p_pool_sizes = pool_sizes.ptr,
    };
    vk_check(vkCreateDescriptorPool(ctx.dev.log_dev, &descriptor_pool_ci, ctx.vk_alloc, &pool.handle)); 
	return pool;
}

<*
	@require layouts.len == sets.len
*>
fn void VulkanDescriptorPool.allocate_sets(&pool, VulkanDevice* dev, VulkanDescriptorSetLayout[] layouts, VkDescriptorSet[] sets)
{
    VkDescriptorSetAllocateInfo alloc_info = {
        .s_type = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
        .descriptor_pool = pool.handle,
        .descriptor_set_count = layouts.len,
        .p_set_layouts = (VkDescriptorSetLayout*)layouts.ptr,
    };

    vk_check(vkAllocateDescriptorSets(dev.log_dev, &alloc_info, sets.ptr));
}

fn void VulkanDescriptorPool.destroy(&pool, VulkanContext* ctx)
{
    if (pool.handle) {
        vkDestroyDescriptorPool(ctx.dev.log_dev, pool.handle, ctx.vk_alloc);
        pool.handle = null;
    }
}

// VulkanDescriptorSetLayout

struct VulkanDescriptorSetLayout
{
    VkDescriptorSetLayout handle;
}

fn VulkanDescriptorSetLayout create_descriptor_set_layout(VulkanContext* ctx, VkDescriptorSetLayoutBinding[] bindings)
{
	VulkanDescriptorSetLayout layout @noinit;
    VkDescriptorSetLayoutCreateInfo layout_ci = {
        .s_type = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
        .binding_count = bindings.len,
        .p_bindings = bindings.ptr,
    };
    vk_check(vkCreateDescriptorSetLayout(ctx.dev.log_dev, &layout_ci, ctx.vk_alloc, &layout.handle));
	return layout;
}

<*
	@require descriptor_types.len == out_bindings.len
*>
fn void create_descriptor_bindings(VkShaderStageFlags stage_flags, VkDescriptorType[] descriptor_types, VkDescriptorSetLayoutBinding[] out_bindings)
{
    foreach (uint i, &binding : out_bindings) {
        binding.binding = i;
        binding.descriptor_type = descriptor_types[i];
        binding.descriptor_count = 1u;
        binding.stage_flags = stage_flags;
        binding.p_immutable_samplers = null;
    }
}

fn void VulkanDescriptorSetLayout.destroy(&layout, VulkanContext* ctx)
{
    if (layout.handle) {
        vkDestroyDescriptorSetLayout(ctx.dev.log_dev, layout.handle, ctx.vk_alloc);
        layout.handle = null;
    }
}
