module engine;

import logger;
import vk;
import std::math;
import std::collections::elastic_array;

const MAX_TEXTURE_INDICES = 4;

struct Entity
{
	Vec3 scale;
	Quat rotation;
	Vec3 translation;
	GeometryView geometry;
	EntityShaderState shader_state;
	ElasticArray{uint, MAX_TEXTURE_INDICES} texture_indices;
}

fn Entity create_entity(
	App* app_ctx,
	VulkanShader* shader,
	GeometryView geometry,
	String[] texture_names,
	Vec3 scale,
	Quat rotation,
	Vec3 translation
)
{
	Entity en;
	en.init(app_ctx, shader, geometry, texture_names, scale, rotation, translation);
	return en;
}

<*
 @require texture_names.len <= MAX_TEXTURE_INDICES : "Shouldn't exceed upper bound"
*>
fn void Entity.init(
	&en,
	App* app_ctx,
	VulkanShader* shader,
	GeometryView geometry,
	String[] texture_names,
	Vec3 scale,
	Quat rotation,
	Vec3 translation
)
{
	en.geometry = geometry;
	en.scale = scale;
	en.rotation = rotation;
	en.translation = translation;
	en.shader_state = shader.acquire_entity_resources(&app_ctx.vk_ctx);
	foreach (tex_name : texture_names)
	{
		uint? tex_index = app_ctx.tex_sys.load_texture(app_ctx, tex_name);
		if (catch err = tex_index)
		{
			logger::logn(ERROR, "Failed to load texture for entity, reason: %s", err);
		}
		else
		{
			en.texture_indices.push(tex_index);
		}
	}
}

fn Mat4 Entity.get_model(&en, TransformType[] transform_order)
{
	Mat4 model = matrix::IDENTITY4;
	foreach (order : transform_order)
	{
		switch (order)
		{
			case SCALE: model = model.scale(en.scale);
			case TRANSLATION: model = model.translate(en.translation);
			case ROTATION: model *= en.rotation.to_matrix();
		}
	}
	return model;
}

fn void Entity.write_updates_for_shader(
	&en,
	TextureSystem* tex_sys,
	ElasticArray{DescriptorUpdateInfo, vk::MAX_DESCRIPTOR_BINDING_COUNT}* out_update_infos
)
{
	foreach (uint i, tex_ind : en.texture_indices)
	{
		Texture* tex = tex_sys.get_texture_by_index(tex_ind);
		assert (tex.load_state == UPLOADED_TO_GPU , "Texture should be uploaded to gpu");
		out_update_infos.push(
			{
				.set_index = 0,
				.type = vk::DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
				.image_info = tex.to_vk_descriptor_info(),
			}
		);
	}
}

fn void Entity.destroy(&en, App* app_ctx, VulkanShader* shader)
{
	shader.free_entity_resources(&app_ctx.vk_ctx, en.shader_state);
	foreach (tex_ind : en.texture_indices)
	{
		app_ctx.tex_sys.remove_texture(tex_ind);
	}
}
