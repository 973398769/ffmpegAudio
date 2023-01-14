//
//  PCMPlayer.m
//  ffmpegAudio2
//
//  Created by EBM on 2023/1/13.
//

#import "PCMPlayer.h"

#ifdef __cplusplus
extern "C" {
#endif

#include "libavformat/avformat.h"
#include "libavcodec/avcodec.h"
#include "libavutil/avutil.h"
#include "libswscale/swscale.h"
#include "libswresample/swresample.h"
#include "libavutil/opt.h"
#include "SDL2/SDL.h"

#ifdef __cplusplus
};
#endif

static const NSString *errorDomain = @"audioPlayerError";

struct AudioBuffer {
public:
    int len = 0;
    // 每次往音频缓冲区的大小
    int pullLen = 0;
    Uint8 *data = nullptr;
    
    AudioBuffer() {}
};

@implementation PCMPlayer

- (void)playPCM:(NSString*)filePath error:(NSError **)error {
    NSString *errorStr = @"";
    NSFileManager *fm = [NSFileManager defaultManager];
    
    if (!filePath) {
        *error = [NSError errorWithDomain:(NSString *)errorDomain code:0 userInfo:[NSDictionary dictionaryWithObject:@"Empty path or not exist" forKey:NSLocalizedDescriptionKey]];
        return;
    }
    
    if (SDL_Init(SDL_INIT_AUDIO)) {
        errorStr = [NSString stringWithFormat:@"SDL_INIT Error: %s", SDL_GetError()];
        *error = [NSError errorWithDomain:(NSString *)errorDomain code:0 userInfo:[NSDictionary dictionaryWithObject:errorStr forKey:NSLocalizedDescriptionKey]];
    }
    
    SDL_AudioSpec spec;
    spec.freq = 44100;
    spec.format = AV_SAMPLE_FMT_FLTP;
    spec.channels = AV_CH_LAYOUT_STEREO;
    spec.samples = 1024;
    spec.callback = pulAudioData;
    AudioBuffer *buffer = new AudioBuffer();
    spec.userdata = buffer;
    if (SDL_OpenAudio(&spec, nullptr)) {
        SDL_Quit();
        NSLog(@"SDL_OpenAudio Error: %s", SDL_GetError());
        return;
    }
    SDL_PauseAudio(0);
    NSFileHandle *filehandle = [NSFileHandle fileHandleForReadingAtPath:filePath];
    NSUInteger perSample = (SDL_AUDIO_BITSIZE(AUDIO_S16LSB) * AV_CH_LAYOUT_STEREO) >> 3;
    NSUInteger length = perSample *1024;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        while (1) {
            if (buffer->len > 0) continue;
            NSData *data = [filehandle readDataOfLength:length];
            buffer->len = (int)data.length;
            if (buffer->len <= 0) {
                // 剩余样本数量
                // BYTES_PER_SAMPLE 每个样本的大小 = 采样率 * 通道数 >> 3
                // 这样做的目的是推迟线程结束的时间，让剩余的音频播放完毕
                int samples = buffer->pullLen / perSample;
                int ms = samples * 1000 / 44100;
                SDL_Delay(ms);
                break;
            }
            buffer->data =  (Uint8 *)[data bytes];
        }
        [filehandle closeFile];
        SDL_CloseAudio();
        SDL_Quit();
        dispatch_async(dispatch_get_main_queue(), ^{
//            [self playEnd];
        });
    });
}

void pulAudioData(void *userData, Uint8 *stream, int len) {
    AudioBuffer *buffer = (AudioBuffer*)userData;
    SDL_memset(stream, 0, len);
    if (buffer->len <= 0) {
        return;
    }
    buffer->pullLen = len > buffer->len ? buffer->len : len;
    NSLog(@"before-buffer->len: %d, buffer->pullLen %d, len: %d", buffer->len, buffer->pullLen, len);
    SDL_MixAudio(stream, (UInt8 *)buffer->data, buffer->pullLen, SDL_MIX_MAXVOLUME);
    buffer->data += buffer->pullLen;
    buffer->len -= buffer->pullLen;
    NSLog(@"buffer->len: %d, buffer->pullLen %d", buffer->len, buffer->pullLen);
}

@end
