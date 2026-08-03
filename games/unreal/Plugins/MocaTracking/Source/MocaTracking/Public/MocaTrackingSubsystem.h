#pragma once
#include "CoreMinimal.h"
#include "Subsystems/GameInstanceSubsystem.h"
#include "MocaPlayerSnapshot.h"
#include "MocaTrackingSubsystem.generated.h"

UCLASS()
class MOCATRACKING_API UMocaTrackingSubsystem : public UGameInstanceSubsystem {
  GENERATED_BODY()
 public:
  UFUNCTION(BlueprintCallable, Category="Moca|Tracking") void Connect(const FString& Url);
  UFUNCTION(BlueprintCallable, Category="Moca|Tracking") void Disconnect();
  UFUNCTION(BlueprintPure, Category="Moca|Tracking") TArray<FMocaPlayerSnapshot> GetPlayers() const;
 private:
  mutable FCriticalSection SnapshotMutex;
  TArray<FMocaPlayerSnapshot> LatestPlayers;
};
