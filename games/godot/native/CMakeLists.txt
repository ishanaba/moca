if(NOT TARGET moca_protocol)
  message(STATUS "Protobuf not found: Godot native tracking bridge disabled")
  return()
endif()

add_library(moca_godot_tracking STATIC
  src/tracking_bridge.cpp
)
set_target_properties(moca_godot_tracking PROPERTIES POSITION_INDEPENDENT_CODE ON)
target_include_directories(moca_godot_tracking PUBLIC
  include
  ${CMAKE_SOURCE_DIR}/services/tracker/include
)
target_compile_features(moca_godot_tracking PUBLIC cxx_std_20)
target_compile_options(moca_godot_tracking PRIVATE -Wall -Wextra -Wpedantic)
target_link_libraries(moca_godot_tracking PUBLIC moca_protocol)

add_executable(moca-godot-tracking-tests tests/tracking_bridge_tests.cpp)
target_link_libraries(moca-godot-tracking-tests PRIVATE moca_godot_tracking)
add_test(NAME moca-godot-tracking-tests COMMAND moca-godot-tracking-tests)

if(TARGET godot::cpp)
  find_file(MOCA_PROTOBUF_SHARED_LIBRARY libprotobuf.so.32
    PATHS /usr/lib/${CMAKE_LIBRARY_ARCHITECTURE} /lib/${CMAKE_LIBRARY_ARCHITECTURE}
    REQUIRED NO_DEFAULT_PATH)
  add_library(moca_godot_extension SHARED
    src/godot_tracking_decoder.cpp
    src/register_types.cpp
  )
  target_compile_features(moca_godot_extension PRIVATE cxx_std_20)
  target_compile_options(moca_godot_extension PRIVATE -Wall -Wextra -Wpedantic)
  target_link_libraries(moca_godot_extension PRIVATE moca_godot_tracking godot::cpp)
  set_target_properties(moca_godot_extension PROPERTIES
    PREFIX "lib"
    OUTPUT_NAME "moca_tracking"
    LIBRARY_OUTPUT_DIRECTORY ${CMAKE_SOURCE_DIR}/games/godot/bin
    BUILD_RPATH "$ORIGIN"
  )
  add_custom_command(TARGET moca_godot_extension POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
      ${MOCA_PROTOBUF_SHARED_LIBRARY}
      ${CMAKE_SOURCE_DIR}/games/godot/bin/libprotobuf.so.32
  )
endif()
