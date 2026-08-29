# PlumeFileToC.cmake
# Builds the file_to_c tool for embedding binary files as C arrays

# Build the file_to_c tool. On a native build it is a regular executable target
# in this build. When cross compiling it cannot run on the host, so it is built
# in a nested CMake project with the host toolchain and its path is cached.
function(plume_build_file_to_c)
    if(TARGET plume_file_to_c)
        return()
    endif()

    # Find the source file relative to this module
    set(FILE_TO_C_SOURCE "${CMAKE_CURRENT_FUNCTION_LIST_DIR}/../tools/file_to_c.cpp")

    if(NOT EXISTS "${FILE_TO_C_SOURCE}")
        message(FATAL_ERROR "plume file_to_c.cpp not found at ${FILE_TO_C_SOURCE}")
    endif()

    if(CMAKE_CROSSCOMPILING)
        set(HOST_PROJ_DIR "${CMAKE_BINARY_DIR}/plume_host_file_to_c")
        string(REPLACE "\\" "/" FILE_TO_C_SRC_UNIX "${FILE_TO_C_SOURCE}")
        file(MAKE_DIRECTORY "${HOST_PROJ_DIR}")
        file(WRITE "${HOST_PROJ_DIR}/CMakeLists.txt" "\
cmake_minimum_required(VERSION 3.16)\n\
project(plume_file_to_c_host CXX)\n\
add_executable(plume_file_to_c \"${FILE_TO_C_SRC_UNIX}\")\n\
set_target_properties(plume_file_to_c PROPERTIES\n\
  CXX_STANDARD 17\n\
  CXX_STANDARD_REQUIRED ON\n\
  RUNTIME_OUTPUT_DIRECTORY \"${HOST_PROJ_DIR}\")\n\
file(GENERATE OUTPUT \"${HOST_PROJ_DIR}/tool_path.txt\" CONTENT \"$<TARGET_FILE:plume_file_to_c>\")\n")
        execute_process(
            COMMAND "${CMAKE_COMMAND}" -S "${HOST_PROJ_DIR}" -B "${HOST_PROJ_DIR}/build"
            -G "${CMAKE_GENERATOR}"
            RESULT_VARIABLE _cfg_ok
            ERROR_VARIABLE _cfg_err
            OUTPUT_QUIET)
        if(NOT _cfg_ok EQUAL 0)
            message(FATAL_ERROR "Could not configure host plume_file_to_c build:\n${_cfg_err}")
        endif()
        execute_process(
            COMMAND "${CMAKE_COMMAND}" --build "${HOST_PROJ_DIR}/build"
            RESULT_VARIABLE _build_ok
            ERROR_VARIABLE _build_err
            OUTPUT_QUIET)
        if(NOT _build_ok EQUAL 0)
            message(FATAL_ERROR "Could not build host plume_file_to_c:\n${_build_err}")
        endif()
        file(STRINGS "${HOST_PROJ_DIR}/tool_path.txt" _tool_path LIMIT_COUNT 1)
        if(NOT EXISTS "${_tool_path}")
            message(FATAL_ERROR "Host plume_file_to_c was not produced: ${_tool_path}")
        endif()
        set(PLUME_FILE_TO_C_HOST_EXECUTABLE "${_tool_path}" CACHE INTERNAL
            "Path to the host-built plume file_to_c tool")
        add_custom_target(plume_file_to_c
            COMMENT "plume_file_to_c is built for the host during cross-compiles")
        return()
    endif()

    add_executable(plume_file_to_c ${FILE_TO_C_SOURCE})
    set_target_properties(plume_file_to_c PROPERTIES
        RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/plume_tools"
        CXX_STANDARD 17
        CXX_STANDARD_REQUIRED ON
    )

    if(APPLE)
        set_target_properties(plume_file_to_c PROPERTIES
            XCODE_ATTRIBUTE_CODE_SIGN_IDENTITY "-"
        )
    endif()
endfunction()

# Returns the command to invoke the file_to_c tool. On a native build this is
# the built executable target; when cross compiling it is the host-built binary.
function(plume_get_file_to_c_command OUT_VAR)
    if(CMAKE_CROSSCOMPILING)
        if(NOT PLUME_FILE_TO_C_HOST_EXECUTABLE)
            message(FATAL_ERROR "plume_file_to_c host executable was not built")
        endif()
        set(${OUT_VAR} "${PLUME_FILE_TO_C_HOST_EXECUTABLE}" PARENT_SCOPE)
    else()
        set(${OUT_VAR} "$<TARGET_FILE:plume_file_to_c>" PARENT_SCOPE)
    endif()
endfunction()

# Convert a binary file to a C header
# Usage: plume_file_to_c_header(INPUT_FILE OUTPUT_C OUTPUT_H VARIABLE_NAME)
function(plume_file_to_c_header INPUT_FILE VARIABLE_NAME OUTPUT_C OUTPUT_H)
    plume_build_file_to_c()
    plume_get_file_to_c_command(FILE_TO_C_CMD)

    get_filename_component(OUTPUT_DIR "${OUTPUT_C}" DIRECTORY)
    file(MAKE_DIRECTORY "${OUTPUT_DIR}")

    add_custom_command(
        OUTPUT "${OUTPUT_C}" "${OUTPUT_H}"
        COMMAND ${FILE_TO_C_CMD} "${INPUT_FILE}" "${VARIABLE_NAME}" "${OUTPUT_C}" "${OUTPUT_H}"
        DEPENDS "${INPUT_FILE}" plume_file_to_c
        COMMENT "Generating C header for ${VARIABLE_NAME}"
        VERBATIM
    )
endfunction()