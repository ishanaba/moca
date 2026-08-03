#include "MocaTrackingSubsystem.h"
void UMocaTrackingSubsystem::Connect(const FString& Url) { UE_LOG(LogTemp, Log, TEXT("Moca tracker endpoint: %s"), *Url); }
void UMocaTrackingSubsystem::Disconnect() { FScopeLock Lock(&SnapshotMutex); LatestPlayers.Reset(); }
TArray<FMocaPlayerSnapshot> UMocaTrackingSubsystem::GetPlayers() const { FScopeLock Lock(&SnapshotMutex); return LatestPlayers; }
