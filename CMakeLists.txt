cmake_minimum_required(VERSION 3.25)
project(game_engine VERSION 0.1.0 LANGUAGES CXX)

set(ROOT_DIR ${CMAKE_CURRENT_SOURCE_DIR})

if (CMAKE_BUILD_TYPE STREQUAL "Debug")
  set(BUILD_DIR ${ROOT_DIR}/build/debug)
elseif (CMAKE_BUILD_TYPE STREQUAL "Release")
  set(BUILD_DIR ${ROOT_DIR}/build/release)
endif()

# glfw
set(GLFW_SRC_DIR ${ROOT_DIR}/lib/glfw)
set(GLFW_BUILD_DIR ${BUILD_DIR}/glfw)
add_subdirectory(${GLFW_SRC_DIR} ${GLFW_BUILD_DIR})

# volk
set(VOLK_SRC_DIR ${ROOT_DIR}/lib/volk)
set(VOLK_BUILD_DIR ${BUILD_DIR}/volk)
add_subdirectory(${VOLK_SRC_DIR} ${VOLK_BUILD_DIR})

# shaders
set(SHADER_SRC_DIR ${ROOT_DIR}/resources/shaders)
set(SHADER_BIN_DIR ${BUILD_DIR}/shaders)
set(SHADER_COMPILER $ENV{VULKAN_SDK}/bin/slangc)
set(SHADER_TARGET ${PROJECT_NAME}_shaders)
file(GLOB_RECURSE VK_SHADER_SRCS CONFIGURE_DEPENDS ${SHADER_SRC_DIR}/*.slang)

# compile shaders
function (compile_shaders)
  set(SHADER_DIR_TARGET ${SHADER_TARGET}_dir)
  add_custom_target(${SHADER_DIR_TARGET} DEPENDS ${SHADER_BIN_DIR})

  # Create shader binary directory
  add_custom_command(
    COMMAND ${CMAKE_COMMAND} -E make_directory ${SHADER_BIN_DIR}
    OUTPUT ${SHADER_BIN_DIR}
    COMMENT "Creating shader binary directory"
  )

  # Process each shader file
  foreach(SHADER_PATH ${VK_SHADER_SRCS})
    get_filename_component(SHADER_FILE_NAME ${SHADER_PATH} NAME_WE)
    get_filename_component(SHADER_EXT ${SHADER_PATH} EXT)

    if(${EXT} MATCHES "slang")
      set(ENTRY "-entry vertMain -entry fragMain")
    elseif(${EXT} MATCHES "(comp|compute)")
      set(ENTRY "-entry main")
    elseif(${EXT} MATCHES "(geom|geometry)")
      set(ENTRY "-entry geomMain")
    elseif(${EXT} MATCHES "(tesc|tessellation_control)")
      set(ENTRY "-entry tescMain")
    elseif(${EXT} MATCHES "(tese|tessellation_evaluation)")
      set(ENTRY "-entry teseMain")
    endif()

    # Create SPIR-V output path
    set(SPIRV_OUTPUT ${SHADER_BIN_DIR}/${SHADER_FILE_NAME}.spv)

    # Add compilation command
    add_custom_command(
      OUTPUT ${SPIRV_OUTPUT}
      COMMAND ${SHADER_COMPILER}
        ${SHADER_PATH}
        -target spirv
        -profile spirv_1_4
        -emit-spirv-directly
        -fvk-use-entrypoint-name
        ${ENTRY}
        -o ${SPIRV_OUTPUT}
      DEPENDS ${SHADER_PATH} ${SHADER_BINARY_DIR}
      COMMENT "Compiling ${SHADER_FILE_NAME}"
    )

    # Collect all SPIR-V outputs
    list(APPEND SPIRV_FILES ${SPIRV_OUTPUT})
  endforeach()

  add_custom_target(${SHADER_TARGET} ALL DEPENDS ${SHADER_DIR_TARGET} ${SPIRV_FILES})
endfunction()

option(BUILD_SHADERS "Enable shader compilation" ON)

if(BUILD_SHADERS)
    compile_shaders()
endif()
