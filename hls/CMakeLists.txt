cmake_minimum_required(VERSION 3.11)
project(unet)

set(CMAKE_CXX_STANDARD 14)
include_directories(
    /tools/Xilinx/2025.1/Vitis/include
    ${PROJECT_SOURCE_DIR}/include
)
include_directories(include)

# 自动查找 src 和 tb 目录下的所有 cpp 文件
file(GLOB SRC_FILES "src/*.cpp")
file(GLOB TEST_FILES "test/*.cpp")

# 为 tb 目录下的每个 cpp 文件创建一个可执行目标
foreach(TEST_FILE ${TEST_FILES})
    get_filename_component(TEST_NAME ${TEST_FILE} NAME_WE)
    add_executable(${TEST_NAME} ${TEST_FILE} ${SRC_FILES})
endforeach()

# 如果没有指定 build type，默认设为 Release（避免无意使用 Debug）
if(NOT CMAKE_BUILD_TYPE)
	set(CMAKE_BUILD_TYPE "Release" CACHE STRING "Build type" FORCE)
endif()