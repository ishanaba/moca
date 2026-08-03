using UnrealBuildTool;
public class MocaTracking : ModuleRules {
  public MocaTracking(ReadOnlyTargetRules Target) : base(Target) {
    PCHUsage = PCHUsageMode.UseExplicitOrSharedPCHs;
    PublicDependencyModuleNames.AddRange(new[]{"Core","CoreUObject","Engine"});
    PrivateDependencyModuleNames.AddRange(new[]{"WebSockets"});
    // Generated Protobuf C++ and its runtime will be wired here after the Unreal toolchain version is fixed.
  }
}
