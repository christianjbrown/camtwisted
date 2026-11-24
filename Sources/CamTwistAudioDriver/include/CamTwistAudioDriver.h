#ifndef CAMTWIST_AUDIO_DRIVER_H
#define CAMTWIST_AUDIO_DRIVER_H

#include <CoreFoundation/CoreFoundation.h>

/// The factory the system's audio server calls to load the driver. It is
/// named in the bundle's Info.plist, and hands back the driver when asked
/// for an audio server plug-in.
void *CamTwistAudioDriver_Create(CFAllocatorRef allocator, CFUUIDRef requestedTypeUUID);

#endif
