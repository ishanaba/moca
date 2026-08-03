#pragma once
#include "CoreMinimal.h"
#include "MocaPlayerSnapshot.generated.h"

USTRUCT(BlueprintType)
struct MOCATRACKING_API FMocaPlayerSnapshot {
  GENERATED_BODY()
  UPROPERTY(BlueprintReadOnly) int32 PlayerId = INDEX_NONE;
  UPROPERTY(BlueprintReadOnly) FVector2D LeftWrist = FVector2D::ZeroVector;
  UPROPERTY(BlueprintReadOnly) FVector2D RightWrist = FVector2D::ZeroVector;
  UPROPERTY(BlueprintReadOnly) FVector2D BladePosition = FVector2D::ZeroVector;
  UPROPERTY(BlueprintReadOnly) FVector2D BladeVelocity = FVector2D::ZeroVector;
  UPROPERTY(BlueprintReadOnly) float Confidence = 0.0f;
  UPROPERTY(BlueprintReadOnly) bool IsVisible = false;
  UPROPERTY(BlueprintReadOnly) double CaptureTimeSeconds = 0.0;
};
