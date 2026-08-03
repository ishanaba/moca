#include "moca/godot/godot_tracking_decoder.hpp"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/godot.hpp>

namespace {
void initialize_moca_module(godot::ModuleInitializationLevel level) {
  if (level != godot::MODULE_INITIALIZATION_LEVEL_SCENE) return;
  godot::ClassDB::register_class<moca::godot::TrackingDecoder>();
}

void uninitialize_moca_module(godot::ModuleInitializationLevel level) {
  if (level != godot::MODULE_INITIALIZATION_LEVEL_SCENE) return;
}
}  // namespace

extern "C" GDExtensionBool GDE_EXPORT
moca_tracking_library_init(GDExtensionInterfaceGetProcAddress get_proc_address,
                           GDExtensionClassLibraryPtr library,
                           GDExtensionInitialization* initialization) {
  godot::GDExtensionBinding::InitObject init(get_proc_address, library, initialization);
  init.register_initializer(initialize_moca_module);
  init.register_terminator(uninitialize_moca_module);
  init.set_minimum_library_initialization_level(godot::MODULE_INITIALIZATION_LEVEL_SCENE);
  return init.init();
}
