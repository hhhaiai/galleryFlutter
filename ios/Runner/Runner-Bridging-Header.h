#import "GeneratedPluginRegistrant.h"
#import "SafePluginRegistrant.h"

#include <stddef.h>
#include <stdint.h>

typedef struct {
  uint32_t type;
  int32_t top_k;
  float top_p;
  float temperature;
  int32_t seed;
} LiteRtLmSamplerParamsC;

typedef struct {
  uint32_t type;
  const void *data;
  size_t size;
} LiteRtLmInputDataC;
