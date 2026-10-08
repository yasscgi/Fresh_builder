cmake_minimum_required(VERSION 3.18)
project(fresh_builder_viewport_texture LANGUAGES CXX)

add_library(
  fresh_builder_viewport_texture
  SHARED
  fresh_builder_viewport_texture_jni.cpp
)

find_library(log-lib log)
find_library(android-lib android)
find_library(dl-lib dl)

target_link_libraries(
  fresh_builder_viewport_texture
  ${log-lib}
  ${android-lib}
  ${dl-lib}
)
