// The virtual microphone: an audio server plug-in with two devices that
// share one clock and one ring of sound.
//
// "CamTwisted Virtual Microphone output" is what other apps pick. It has an input and
// nothing else. "CamTwisted Microphone Feed" is hidden from every list: the
// app plays its mix to it, and whatever is played there is what the
// microphone hears. The audio server loads this code into a process of its
// own, so the two halves meet here rather than over a connection.

#include <CoreAudio/AudioServerPlugIn.h>
#include <mach/mach_time.h>
#include <pthread.h>
#include <stdatomic.h>
#include <string.h>

void *CamTwistAudioDriver_Create(CFAllocatorRef allocator, CFUUIDRef requestedTypeUUID);

// MARK: What the driver is

// These names are part of the contract with the app, which finds the
// devices by them. MicrophoneContract in CamTwistCore holds the same
// values, and a test keeps the two in step.
#define kManufacturer CFSTR("CamTwisted")
#define kMicrophoneName CFSTR("CamTwisted Virtual Microphone output")
#define kMicrophoneUID CFSTR("CamTwistedMicrophone")
#define kFeedName CFSTR("CamTwisted Microphone Feed")
#define kFeedUID CFSTR("CamTwistedMicrophoneFeed")
#define kModelUID CFSTR("CamTwistedMicrophoneModel")

enum {
    kObjectPlugIn = kAudioObjectPlugInObject,
    kObjectMicrophone = 2,
    kObjectMicrophoneStream = 3,
    kObjectFeed = 4,
    kObjectFeedStream = 5,
};

// One fixed format: there is nothing to gain from offering more, since
// the system converts for any app that wants another.
static const Float64 kSampleRate = 48000.0;
enum {
    kChannels = 2,
    kBitsPerChannel = 32,
    kBytesPerFrame = kChannels * (kBitsPerChannel / 8),
    // How many frames pass between the moments the clock is read off.
    kZeroTimeStampPeriod = 16384,
    // How much sound is kept for the microphone to read: a third of a second.
    kRingFrames = 16384,
    kFirstChannel = 1,
    kSecondChannel = 2,
    kClockSeed = 1,
};
static const Float64 kNanosecondsPerSecond = 1000000000.0;

// MARK: State

static pthread_mutex_t gMutex = PTHREAD_MUTEX_INITIALIZER;
static UInt32 gRefCount = 0;
static AudioServerPlugInHostRef gHost = NULL;
// How many clients are running each device.
static UInt32 gMicrophoneRunning = 0;
static UInt32 gFeedRunning = 0;
// The clock both devices keep: where it started and how many periods on.
static UInt64 gAnchorHostTime = 0;
static UInt64 gPeriodCount = 0;
static Float64 gHostTicksPerFrame = 0;
// The sound, and the frame just past the last one written.
static Float32 gRing[kRingFrames * kChannels];
static _Atomic SInt64 gWrittenUpTo = 0;

// MARK: The interface

static HRESULT QueryInterface(void *driver, REFIID uuid, LPVOID *outInterface);
static ULONG AddRef(void *driver);
static ULONG Release(void *driver);
static OSStatus Initialize(AudioServerPlugInDriverRef driver, AudioServerPlugInHostRef host);
static OSStatus CreateDevice(AudioServerPlugInDriverRef driver, CFDictionaryRef description, const AudioServerPlugInClientInfo *client, AudioObjectID *outDevice);
static OSStatus DestroyDevice(AudioServerPlugInDriverRef driver, AudioObjectID device);
static OSStatus AddDeviceClient(AudioServerPlugInDriverRef driver, AudioObjectID device, const AudioServerPlugInClientInfo *client);
static OSStatus RemoveDeviceClient(AudioServerPlugInDriverRef driver, AudioObjectID device, const AudioServerPlugInClientInfo *client);
static OSStatus PerformDeviceConfigurationChange(AudioServerPlugInDriverRef driver, AudioObjectID device, UInt64 action, void *info);
static OSStatus AbortDeviceConfigurationChange(AudioServerPlugInDriverRef driver, AudioObjectID device, UInt64 action, void *info);
static Boolean HasProperty(AudioServerPlugInDriverRef driver, AudioObjectID object, pid_t client, const AudioObjectPropertyAddress *address);
static OSStatus IsPropertySettable(AudioServerPlugInDriverRef driver, AudioObjectID object, pid_t client, const AudioObjectPropertyAddress *address, Boolean *outIsSettable);
static OSStatus GetPropertyDataSize(AudioServerPlugInDriverRef driver, AudioObjectID object, pid_t client, const AudioObjectPropertyAddress *address, UInt32 qualifierSize, const void *qualifier, UInt32 *outSize);
static OSStatus GetPropertyData(AudioServerPlugInDriverRef driver, AudioObjectID object, pid_t client, const AudioObjectPropertyAddress *address, UInt32 qualifierSize, const void *qualifier, UInt32 dataSize, UInt32 *outSize, void *outData);
static OSStatus SetPropertyData(AudioServerPlugInDriverRef driver, AudioObjectID object, pid_t client, const AudioObjectPropertyAddress *address, UInt32 qualifierSize, const void *qualifier, UInt32 dataSize, const void *data);
static OSStatus StartIO(AudioServerPlugInDriverRef driver, AudioObjectID device, UInt32 client);
static OSStatus StopIO(AudioServerPlugInDriverRef driver, AudioObjectID device, UInt32 client);
static OSStatus GetZeroTimeStamp(AudioServerPlugInDriverRef driver, AudioObjectID device, UInt32 client, Float64 *outSampleTime, UInt64 *outHostTime, UInt64 *outSeed);
static OSStatus WillDoIOOperation(AudioServerPlugInDriverRef driver, AudioObjectID device, UInt32 client, UInt32 operation, Boolean *outWillDo, Boolean *outWillDoInPlace);
static OSStatus BeginIOOperation(AudioServerPlugInDriverRef driver, AudioObjectID device, UInt32 client, UInt32 operation, UInt32 frames, const AudioServerPlugInIOCycleInfo *cycle);
static OSStatus DoIOOperation(AudioServerPlugInDriverRef driver, AudioObjectID device, AudioObjectID stream, UInt32 client, UInt32 operation, UInt32 frames, const AudioServerPlugInIOCycleInfo *cycle, void *mainBuffer, void *secondaryBuffer);
static OSStatus EndIOOperation(AudioServerPlugInDriverRef driver, AudioObjectID device, UInt32 client, UInt32 operation, UInt32 frames, const AudioServerPlugInIOCycleInfo *cycle);

static AudioServerPlugInDriverInterface gInterface = {
    NULL,
    QueryInterface, AddRef, Release,
    Initialize, CreateDevice, DestroyDevice, AddDeviceClient, RemoveDeviceClient,
    PerformDeviceConfigurationChange, AbortDeviceConfigurationChange,
    HasProperty, IsPropertySettable, GetPropertyDataSize, GetPropertyData, SetPropertyData,
    StartIO, StopIO, GetZeroTimeStamp,
    WillDoIOOperation, BeginIOOperation, DoIOOperation, EndIOOperation,
};
static AudioServerPlugInDriverInterface *gInterfacePointer = &gInterface;
static AudioServerPlugInDriverRef gDriver = &gInterfacePointer;

void *CamTwistAudioDriver_Create(CFAllocatorRef allocator, CFUUIDRef requestedTypeUUID) {
    (void)allocator;
    if (!CFEqual(requestedTypeUUID, kAudioServerPlugInTypeUUID)) {
        return NULL;
    }
    return gDriver;
}

// MARK: Lifetime

static HRESULT QueryInterface(void *driver, REFIID uuid, LPVOID *outInterface) {
    if (driver != gDriver || outInterface == NULL) {
        return kAudioHardwareBadObjectError;
    }
    CFUUIDRef requested = CFUUIDCreateFromUUIDBytes(NULL, uuid);
    Boolean known = CFEqual(requested, IUnknownUUID) || CFEqual(requested, kAudioServerPlugInDriverInterfaceUUID);
    CFRelease(requested);
    if (!known) {
        return E_NOINTERFACE;
    }
    AddRef(driver);
    *outInterface = gDriver;
    return 0;
}

static ULONG AddRef(void *driver) {
    (void)driver;
    pthread_mutex_lock(&gMutex);
    ULONG count = ++gRefCount;
    pthread_mutex_unlock(&gMutex);
    return count;
}

static ULONG Release(void *driver) {
    (void)driver;
    pthread_mutex_lock(&gMutex);
    if (gRefCount > 0) {
        --gRefCount;
    }
    ULONG count = gRefCount;
    pthread_mutex_unlock(&gMutex);
    return count;
}

static OSStatus Initialize(AudioServerPlugInDriverRef driver, AudioServerPlugInHostRef host) {
    if (driver != gDriver) {
        return kAudioHardwareBadObjectError;
    }
    gHost = host;
    struct mach_timebase_info timebase;
    mach_timebase_info(&timebase);
    Float64 ticksPerNanosecond = (Float64)timebase.denom / (Float64)timebase.numer;
    gHostTicksPerFrame = (kNanosecondsPerSecond / kSampleRate) * ticksPerNanosecond;
    return 0;
}

// The devices are fixed: none is made or taken away, and none has a
// configuration that can change.
static OSStatus CreateDevice(AudioServerPlugInDriverRef driver, CFDictionaryRef description, const AudioServerPlugInClientInfo *client, AudioObjectID *outDevice) {
    (void)driver; (void)description; (void)client; (void)outDevice;
    return kAudioHardwareUnsupportedOperationError;
}

static OSStatus DestroyDevice(AudioServerPlugInDriverRef driver, AudioObjectID device) {
    (void)driver; (void)device;
    return kAudioHardwareUnsupportedOperationError;
}

static Boolean IsDevice(AudioObjectID object) {
    return object == kObjectMicrophone || object == kObjectFeed;
}

static OSStatus AddDeviceClient(AudioServerPlugInDriverRef driver, AudioObjectID device, const AudioServerPlugInClientInfo *client) {
    (void)driver; (void)client;
    return IsDevice(device) ? 0 : kAudioHardwareBadObjectError;
}

static OSStatus RemoveDeviceClient(AudioServerPlugInDriverRef driver, AudioObjectID device, const AudioServerPlugInClientInfo *client) {
    (void)driver; (void)client;
    return IsDevice(device) ? 0 : kAudioHardwareBadObjectError;
}

static OSStatus PerformDeviceConfigurationChange(AudioServerPlugInDriverRef driver, AudioObjectID device, UInt64 action, void *info) {
    (void)driver; (void)action; (void)info;
    return IsDevice(device) ? 0 : kAudioHardwareBadObjectError;
}

static OSStatus AbortDeviceConfigurationChange(AudioServerPlugInDriverRef driver, AudioObjectID device, UInt64 action, void *info) {
    (void)driver; (void)action; (void)info;
    return IsDevice(device) ? 0 : kAudioHardwareBadObjectError;
}

// MARK: Properties

// Where a property's value goes: how much room there is, how much was
// used, and the room itself, which is NULL when only the size is asked for.
typedef struct {
    UInt32 room;
    UInt32 *outSize;
    void *outData;
} Answer;

// Hands back one value, or only its size when no room was offered.
static OSStatus Give(Answer answer, const void *value, UInt32 size) {
    *answer.outSize = size;
    if (answer.outData != NULL) {
        if (answer.room < size) { return kAudioHardwareBadPropertySizeError; }
        memcpy(answer.outData, value, size);
    }
    return 0;
}

// Answers a property with one value of a type. It is a return statement,
// so nothing written after it in the same case would run.
#define ANSWER(type, value) return Give(answer, (type[]){ (value) }, sizeof(type))

// A list is given as far as it fits, which is how the audio server asks
// for the first few of something.
static OSStatus AnswerList(Answer answer, const void *items, UInt32 count, UInt32 itemSize) {
    if (answer.outData == NULL) {
        *answer.outSize = count * itemSize;
        return 0;
    }
    UInt32 fitting = answer.room / itemSize;
    if (fitting > count) {
        fitting = count;
    }
    if (fitting > 0) {
        memcpy(answer.outData, items, fitting * itemSize);
    }
    *answer.outSize = fitting * itemSize;
    return 0;
}

static AudioStreamBasicDescription Format(void) {
    AudioStreamBasicDescription format = {
        .mSampleRate = kSampleRate,
        .mFormatID = kAudioFormatLinearPCM,
        .mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagsNativeEndian | kAudioFormatFlagIsPacked,
        .mBytesPerPacket = kBytesPerFrame,
        .mFramesPerPacket = 1,
        .mBytesPerFrame = kBytesPerFrame,
        .mChannelsPerFrame = kChannels,
        .mBitsPerChannel = kBitsPerChannel,
    };
    return format;
}

static OSStatus PlugInProperty(const AudioObjectPropertyAddress *address, UInt32 qualifierSize, const void *qualifier, Answer answer) {
    static const AudioObjectID devices[] = { kObjectMicrophone, kObjectFeed };
    switch (address->mSelector) {
    case kAudioObjectPropertyBaseClass:
        ANSWER(AudioClassID, kAudioObjectClassID);
    case kAudioObjectPropertyClass:
        ANSWER(AudioClassID, kAudioPlugInClassID);
    case kAudioObjectPropertyOwner:
        ANSWER(AudioObjectID, kAudioObjectUnknown);
    case kAudioObjectPropertyManufacturer:
        ANSWER(CFStringRef, kManufacturer);
    case kAudioObjectPropertyOwnedObjects:
    case kAudioPlugInPropertyDeviceList:
        return AnswerList(answer, devices, sizeof(devices) / sizeof(devices[0]), sizeof(AudioObjectID));
    case kAudioPlugInPropertyBoxList:
        return AnswerList(answer, devices, 0, sizeof(AudioObjectID));
    case kAudioPlugInPropertyTranslateUIDToBox:
        ANSWER(AudioObjectID, kAudioObjectUnknown);
    case kAudioPlugInPropertyTranslateUIDToDevice: {
        AudioObjectID found = kAudioObjectUnknown;
        if (qualifierSize == sizeof(CFStringRef) && qualifier != NULL) {
            CFStringRef uid = *(const CFStringRef *)qualifier;
            if (CFEqual(uid, kMicrophoneUID)) {
                found = kObjectMicrophone;
            } else if (CFEqual(uid, kFeedUID)) {
                found = kObjectFeed;
            }
        }
        ANSWER(AudioObjectID, found);
    }
    case kAudioPlugInPropertyResourceBundle:
        ANSWER(CFStringRef, CFSTR(""));
    default:
        return kAudioHardwareUnknownPropertyError;
    }
}

// Whether anything has one of the two devices running: 1 or 0, as the audio server asks for it.
static UInt32 IsRunning(bool isMicrophone) {
    pthread_mutex_lock(&gMutex);
    UInt32 running = (isMicrophone ? gMicrophoneRunning : gFeedRunning) > 0 ? 1 : 0;
    pthread_mutex_unlock(&gMutex);
    return running;
}

static OSStatus DeviceProperty(AudioObjectID device, const AudioObjectPropertyAddress *address, Answer answer) {
    Boolean isMicrophone = device == kObjectMicrophone;
    AudioObjectID stream = isMicrophone ? kObjectMicrophoneStream : kObjectFeedStream;
    // The microphone's one stream is an input and the feed's an output.
    AudioObjectPropertyScope streamScope = isMicrophone ? kAudioObjectPropertyScopeInput : kAudioObjectPropertyScopeOutput;
    Boolean scopeHasStream = address->mScope == kAudioObjectPropertyScopeGlobal || address->mScope == streamScope;
    switch (address->mSelector) {
    case kAudioObjectPropertyBaseClass:
        ANSWER(AudioClassID, kAudioObjectClassID);
    case kAudioObjectPropertyClass:
        ANSWER(AudioClassID, kAudioDeviceClassID);
    case kAudioObjectPropertyOwner:
        ANSWER(AudioObjectID, kObjectPlugIn);
    case kAudioObjectPropertyName:
        ANSWER(CFStringRef, isMicrophone ? kMicrophoneName : kFeedName);
    case kAudioObjectPropertyManufacturer:
        ANSWER(CFStringRef, kManufacturer);
    case kAudioDevicePropertyDeviceUID:
        ANSWER(CFStringRef, isMicrophone ? kMicrophoneUID : kFeedUID);
    case kAudioDevicePropertyModelUID:
        ANSWER(CFStringRef, kModelUID);
    case kAudioDevicePropertyTransportType:
        ANSWER(UInt32, kAudioDeviceTransportTypeVirtual);
    case kAudioDevicePropertyRelatedDevices:
        return AnswerList(answer, &device, 1, sizeof(AudioObjectID));
    case kAudioDevicePropertyClockDomain:
        ANSWER(UInt32, 0);
    case kAudioDevicePropertyDeviceIsAlive:
        ANSWER(UInt32, 1);
    case kAudioDevicePropertyDeviceIsRunning:
        ANSWER(UInt32, IsRunning(isMicrophone));
    case kAudioDevicePropertyDeviceCanBeDefaultDevice:
        // Only the microphone may be chosen, and only to listen to.
        ANSWER(UInt32, isMicrophone && address->mScope != kAudioObjectPropertyScopeOutput ? 1 : 0);
    case kAudioDevicePropertyDeviceCanBeDefaultSystemDevice:
        ANSWER(UInt32, 0);
    case kAudioDevicePropertyLatency:
    case kAudioDevicePropertySafetyOffset:
        ANSWER(UInt32, 0);
    case kAudioObjectPropertyOwnedObjects:
    case kAudioDevicePropertyStreams:
        return AnswerList(answer, &stream, scopeHasStream ? 1 : 0, sizeof(AudioObjectID));
    case kAudioObjectPropertyControlList:
        return AnswerList(answer, &stream, 0, sizeof(AudioObjectID));
    case kAudioDevicePropertyNominalSampleRate:
        ANSWER(Float64, kSampleRate);
    case kAudioDevicePropertyAvailableNominalSampleRates: {
        AudioValueRange range = { kSampleRate, kSampleRate };
        return AnswerList(answer, &range, 1, sizeof(AudioValueRange));
    }
    case kAudioDevicePropertyIsHidden:
        ANSWER(UInt32, isMicrophone ? 0 : 1);
    case kAudioDevicePropertyPreferredChannelsForStereo: {
        UInt32 pair[] = { kFirstChannel, kSecondChannel };
        *answer.outSize = sizeof(pair);
        if (answer.outData != NULL) {
            if (answer.room < sizeof(pair)) { return kAudioHardwareBadPropertySizeError; }
            memcpy(answer.outData, pair, sizeof(pair));
        }
        return 0;
    }
    case kAudioDevicePropertyZeroTimeStampPeriod:
        ANSWER(UInt32, kZeroTimeStampPeriod);
    case kAudioDevicePropertyClockIsStable:
        ANSWER(UInt32, 1);
    default:
        return kAudioHardwareUnknownPropertyError;
    }
}

static OSStatus StreamProperty(AudioObjectID stream, const AudioObjectPropertyAddress *address, Answer answer) {
    Boolean isInput = stream == kObjectMicrophoneStream;
    switch (address->mSelector) {
    case kAudioObjectPropertyBaseClass:
        ANSWER(AudioClassID, kAudioObjectClassID);
    case kAudioObjectPropertyClass:
        ANSWER(AudioClassID, kAudioStreamClassID);
    case kAudioObjectPropertyOwner:
        ANSWER(AudioObjectID, isInput ? kObjectMicrophone : kObjectFeed);
    case kAudioObjectPropertyOwnedObjects:
        return AnswerList(answer, &stream, 0, sizeof(AudioObjectID));
    case kAudioStreamPropertyIsActive:
        ANSWER(UInt32, 1);
    case kAudioStreamPropertyDirection:
        ANSWER(UInt32, isInput ? 1 : 0);
    case kAudioStreamPropertyTerminalType:
        ANSWER(UInt32, isInput ? kAudioStreamTerminalTypeMicrophone : kAudioStreamTerminalTypeSpeaker);
    case kAudioStreamPropertyStartingChannel:
        ANSWER(UInt32, kFirstChannel);
    case kAudioStreamPropertyLatency:
        ANSWER(UInt32, 0);
    case kAudioStreamPropertyVirtualFormat:
    case kAudioStreamPropertyPhysicalFormat:
        ANSWER(AudioStreamBasicDescription, Format());
    case kAudioStreamPropertyAvailableVirtualFormats:
    case kAudioStreamPropertyAvailablePhysicalFormats: {
        AudioStreamRangedDescription only = { Format(), { kSampleRate, kSampleRate } };
        return AnswerList(answer, &only, 1, sizeof(AudioStreamRangedDescription));
    }
    default:
        return kAudioHardwareUnknownPropertyError;
    }
}

static OSStatus Property(AudioObjectID object, const AudioObjectPropertyAddress *address, UInt32 qualifierSize, const void *qualifier, Answer answer) {
    if (address == NULL || answer.outSize == NULL) {
        return kAudioHardwareIllegalOperationError;
    }
    switch (object) {
    case kObjectPlugIn:
        return PlugInProperty(address, qualifierSize, qualifier, answer);
    case kObjectMicrophone:
    case kObjectFeed:
        return DeviceProperty(object, address, answer);
    case kObjectMicrophoneStream:
    case kObjectFeedStream:
        return StreamProperty(object, address, answer);
    default:
        return kAudioHardwareBadObjectError;
    }
}

static Boolean HasProperty(AudioServerPlugInDriverRef driver, AudioObjectID object, pid_t client, const AudioObjectPropertyAddress *address) {
    (void)driver; (void)client;
    UInt32 size = 0;
    Answer answer = { 0, &size, NULL };
    return Property(object, address, 0, NULL, answer) == 0;
}

// Nothing can be changed: one format, one rate, no controls.
static OSStatus IsPropertySettable(AudioServerPlugInDriverRef driver, AudioObjectID object, pid_t client, const AudioObjectPropertyAddress *address, Boolean *outIsSettable) {
    if (outIsSettable == NULL) {
        return kAudioHardwareIllegalOperationError;
    }
    *outIsSettable = false;
    return HasProperty(driver, object, client, address) ? 0 : kAudioHardwareUnknownPropertyError;
}

static OSStatus GetPropertyDataSize(AudioServerPlugInDriverRef driver, AudioObjectID object, pid_t client, const AudioObjectPropertyAddress *address, UInt32 qualifierSize, const void *qualifier, UInt32 *outSize) {
    (void)driver; (void)client;
    Answer answer = { 0, outSize, NULL };
    return Property(object, address, qualifierSize, qualifier, answer);
}

static OSStatus GetPropertyData(AudioServerPlugInDriverRef driver, AudioObjectID object, pid_t client, const AudioObjectPropertyAddress *address, UInt32 qualifierSize, const void *qualifier, UInt32 dataSize, UInt32 *outSize, void *outData) {
    (void)driver; (void)client;
    if (outData == NULL) {
        return kAudioHardwareIllegalOperationError;
    }
    Answer answer = { dataSize, outSize, outData };
    return Property(object, address, qualifierSize, qualifier, answer);
}

static OSStatus SetPropertyData(AudioServerPlugInDriverRef driver, AudioObjectID object, pid_t client, const AudioObjectPropertyAddress *address, UInt32 qualifierSize, const void *qualifier, UInt32 dataSize, const void *data) {
    (void)qualifierSize; (void)qualifier; (void)dataSize; (void)data;
    return HasProperty(driver, object, client, address) ? kAudioHardwareUnsupportedOperationError : kAudioHardwareUnknownPropertyError;
}

// MARK: Running

static OSStatus StartIO(AudioServerPlugInDriverRef driver, AudioObjectID device, UInt32 client) {
    (void)driver; (void)client;
    if (!IsDevice(device)) {
        return kAudioHardwareBadObjectError;
    }
    pthread_mutex_lock(&gMutex);
    if (gMicrophoneRunning + gFeedRunning == 0) {
        // The first to start sets the clock both devices keep, and
        // nothing from an earlier run is left to be heard.
        gAnchorHostTime = mach_absolute_time();
        gPeriodCount = 0;
        atomic_store(&gWrittenUpTo, 0);
        memset(gRing, 0, sizeof(gRing));
    }
    if (device == kObjectMicrophone) {
        ++gMicrophoneRunning;
    } else {
        ++gFeedRunning;
    }
    pthread_mutex_unlock(&gMutex);
    return 0;
}

static OSStatus StopIO(AudioServerPlugInDriverRef driver, AudioObjectID device, UInt32 client) {
    (void)driver; (void)client;
    if (!IsDevice(device)) {
        return kAudioHardwareBadObjectError;
    }
    pthread_mutex_lock(&gMutex);
    UInt32 *running = device == kObjectMicrophone ? &gMicrophoneRunning : &gFeedRunning;
    if (*running > 0) {
        --*running;
    }
    pthread_mutex_unlock(&gMutex);
    return 0;
}

static OSStatus GetZeroTimeStamp(AudioServerPlugInDriverRef driver, AudioObjectID device, UInt32 client, Float64 *outSampleTime, UInt64 *outHostTime, UInt64 *outSeed) {
    (void)driver; (void)client;
    if (!IsDevice(device)) {
        return kAudioHardwareBadObjectError;
    }
    pthread_mutex_lock(&gMutex);
    Float64 ticksPerPeriod = gHostTicksPerFrame * (Float64)kZeroTimeStampPeriod;
    UInt64 nextPeriodAt = gAnchorHostTime + (UInt64)((Float64)(gPeriodCount + 1) * ticksPerPeriod);
    // Once the next period has begun, the clock moves on to it.
    if (nextPeriodAt <= mach_absolute_time()) {
        ++gPeriodCount;
    }
    *outSampleTime = (Float64)(gPeriodCount * kZeroTimeStampPeriod);
    *outHostTime = gAnchorHostTime + (UInt64)((Float64)gPeriodCount * ticksPerPeriod);
    *outSeed = kClockSeed;
    pthread_mutex_unlock(&gMutex);
    return 0;
}

// The feed takes what is played to it; the microphone gives it back.
static Boolean Handles(AudioObjectID device, UInt32 operation) {
    return (device == kObjectFeed && operation == kAudioServerPlugInIOOperationWriteMix)
        || (device == kObjectMicrophone && operation == kAudioServerPlugInIOOperationReadInput);
}

static OSStatus WillDoIOOperation(AudioServerPlugInDriverRef driver, AudioObjectID device, UInt32 client, UInt32 operation, Boolean *outWillDo, Boolean *outWillDoInPlace) {
    (void)driver; (void)client;
    if (!IsDevice(device)) {
        return kAudioHardwareBadObjectError;
    }
    *outWillDo = Handles(device, operation);
    *outWillDoInPlace = true;
    return 0;
}

static OSStatus BeginIOOperation(AudioServerPlugInDriverRef driver, AudioObjectID device, UInt32 client, UInt32 operation, UInt32 frames, const AudioServerPlugInIOCycleInfo *cycle) {
    (void)driver; (void)client; (void)operation; (void)frames; (void)cycle;
    return IsDevice(device) ? 0 : kAudioHardwareBadObjectError;
}

static OSStatus EndIOOperation(AudioServerPlugInDriverRef driver, AudioObjectID device, UInt32 client, UInt32 operation, UInt32 frames, const AudioServerPlugInIOCycleInfo *cycle) {
    (void)driver; (void)client; (void)operation; (void)frames; (void)cycle;
    return IsDevice(device) ? 0 : kAudioHardwareBadObjectError;
}

// Runs on the audio server's real-time thread: no locks, no memory.
static OSStatus DoIOOperation(AudioServerPlugInDriverRef driver, AudioObjectID device, AudioObjectID stream, UInt32 client, UInt32 operation, UInt32 frames, const AudioServerPlugInIOCycleInfo *cycle, void *mainBuffer, void *secondaryBuffer) {
    (void)driver; (void)stream; (void)client; (void)secondaryBuffer;
    if (!IsDevice(device)) {
        return kAudioHardwareBadObjectError;
    }
    if (!Handles(device, operation) || cycle == NULL || mainBuffer == NULL) {
        return 0;
    }
    Float32 *samples = (Float32 *)mainBuffer;
    if (operation == kAudioServerPlugInIOOperationWriteMix) {
        SInt64 start = (SInt64)cycle->mOutputTime.mSampleTime;
        for (UInt32 frame = 0; frame < frames; ++frame) {
            SInt64 slot = (start + frame) % kRingFrames;
            memcpy(&gRing[slot * kChannels], &samples[frame * kChannels], kBytesPerFrame);
        }
        atomic_store(&gWrittenUpTo, start + frames);
        return 0;
    }
    SInt64 start = (SInt64)cycle->mInputTime.mSampleTime;
    SInt64 writtenUpTo = atomic_load(&gWrittenUpTo);
    for (UInt32 frame = 0; frame < frames; ++frame) {
        SInt64 time = start + frame;
        // Only what was written, and has not since been written over, is
        // sound. Anything else is silence.
        if (time >= 0 && time < writtenUpTo && time >= writtenUpTo - kRingFrames) {
            memcpy(&samples[frame * kChannels], &gRing[(time % kRingFrames) * kChannels], kBytesPerFrame);
        } else {
            memset(&samples[frame * kChannels], 0, kBytesPerFrame);
        }
    }
    return 0;
}
