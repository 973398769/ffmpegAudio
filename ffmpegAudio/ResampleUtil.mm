//
//  ResampleUtil.m
//  ffmpegAudio2
//
//  Created by EBM on 2023/1/9.
//

#import "ResampleUtil.h"

#ifdef __cplusplus
extern "C" {
#endif
    
#include "libswresample/swresample.h"
    
#ifdef __cplusplus
};
#endif

// 重采样上下文
static struct SwrContext *swrCtx = NULL;
// 输入缓冲区能存放的样本数量
static int srcNbSamples = 1024;
static int32_t srcRate = 0;
static AVFrame *inputFrame = NULL;
static int32_t srcNbChannels = 0;
enum AVSampleFormat srcSampleFmt = AV_SAMPLE_FMT_NONE;
static int64_t srcChLayout = 0;
// 输入文件
static FILE *srcFile = NULL;


static int32_t dstNbSamples = 0;
static int32_t maxDstNbSamples = 0;
static int32_t dstNbChannels = 0;
static int32_t dstRate = 0;
enum AVSampleFormat dstSampleFmt = AV_SAMPLE_FMT_NONE;
static int64_t dstChLayout = 0;
// 输出缓冲区的指针
static uint8_t **dstData = NULL;
// 输入缓冲区的大小
static int dstLinesize = 0;
// 输出文件
static FILE *destFile = NULL;

@implementation ResampleUtil

- (void)swrContext:(NSString *)srcFName destFile:(NSString *)destFName {
    if (!srcFName || !destFName) {
        return;
    }
    // 原 PCM 参数
    const char *srcFileName = [srcFName UTF8String];
    srcRate = 44100;
    srcSampleFmt = AV_SAMPLE_FMT_FLTP;
    srcChLayout = AV_CH_LAYOUT_STEREO;
    
    // 重采样后 PCM 参数
    const char *destFileName = [destFName UTF8String];
    dstRate = 44100;
    dstSampleFmt = AV_SAMPLE_FMT_S16;
    dstChLayout = AV_CH_LAYOUT_STEREO;
    
    if (![self openFile:srcFileName dstFilePath:destFileName]) {
        goto end;
    }
    
    if ([self initAudioResampler] < 0) {
        fprintf(stderr, "Error: init audio resampler failed");
        goto end;
    }
    
    // 进行重采样
    if ([self audioResampling] < 0) {
        fprintf(stderr, "Error: audio resampleing failed");
        goto end;
    }

end:
    [self closeFile:srcFile];
    [self closeFile:destFile];
    [self destroyAudioResampler];
}

#pragma mark - Private
- (int32_t)initAudioResampler {
    int32_t result = 0;
    swrCtx = swr_alloc_set_opts(NULL,
                                // 输出参数
                                dstChLayout,
                                dstSampleFmt,
                                dstRate,
                                // 输入参数
                                srcChLayout,
                                srcSampleFmt,
                                srcRate,
                                0,
                                NULL);
    
    if (!swrCtx) {
        fprintf(stderr, "Error: failed to allocate SwrContext.\n");
        return -1;
    }
    
    result = swr_init(swrCtx);
    if (result < 0) {
        fprintf(stderr, "Error: failed to initialize SwrContext.\n");
        return -1;
    }
    
    inputFrame = av_frame_alloc();
    if (!inputFrame) {
        fprintf(stderr, "Error: could not alloc input frame.\n");
        return -1;
    }
    
    result = [self initFrame:srcRate sampleFmt:srcSampleFmt channelLayout:srcChLayout];
    if (result < 0) {
        fprintf(stderr, "Error: failed to initialize input frame.\n");
        return -1;
    }
    
    maxDstNbSamples = dstNbSamples = (int)av_rescale_rnd(srcNbSamples, dstRate, srcRate, AV_ROUND_UP);
    dstNbChannels = av_get_channel_layout_nb_channels(dstChLayout);
    fprintf(stderr, "maxDstNbSamples: %d.\n", maxDstNbSamples);
    fprintf(stderr, "dstNbChannels: %d.\n", dstNbChannels);
    
    return result;


}

// 初始化inputFrame
- (int32_t)initFrame:(int)sampleRate sampleFmt:(int)sampleFmt channelLayout:(uint64_t)channelLayout {
    int32_t result = 0;
    
    inputFrame->sample_rate = sampleRate;
    inputFrame->nb_samples = srcNbSamples;
    inputFrame->format = sampleFmt;
    inputFrame->channel_layout = channelLayout;
    inputFrame->channels = av_get_channel_layout_nb_channels(channelLayout);
    
    // 设置好 inputFrame 参数后，可以创建重采样前的缓冲区
    result = av_frame_get_buffer(inputFrame, 0);
    if (result < 0) {
        fprintf(stderr, "Error: AVFrame could not get buffer.\n");
        return -1;
    }
    return result;
}

- (int32_t)audioResampling {
    // 创建输出缓冲区
    int32_t result = av_samples_alloc_array_and_samples(&dstData,
                                                        &dstLinesize,
                                                        dstNbChannels,
                                                        dstNbSamples,
                                                        dstSampleFmt,
                                                        1);
    if (result < 0) {
        fprintf(stderr, "Error: av_samples_alloc_array_and_samples failed.\n");
        return -1;
    }
    fprintf(stderr, "dstLinesize: %d.\n", dstLinesize);
    srcNbChannels = av_get_channel_layout_nb_channels(srcChLayout);
    
    while (![self endOfFile:srcFile]) {
        result = [self readPCMToFrame];
        if (result < 0) {
            fprintf(stderr, "Error: read_pcm_to_frame failed.\n");
            return -1;
        }
        
        result = [self resamplingFrame];
        if (result < 0) {
            fprintf(stderr, "Error: resampling_frame failed.\n");
            return -1;
        }
    }
    
    // 冲刷重采样缓冲区
    while ((result = swr_convert(swrCtx, dstData, dstNbSamples, NULL, 0)) > 0) {
        int32_t dstBufsize = 0;
        dstBufsize = av_samples_get_buffer_size(&dstLinesize,
                                                 dstNbChannels,
                                                 result,
                                                 dstSampleFmt,
                                                 1);
        [self writePacketToFile:dstData[0] size:dstBufsize];
    }
    
    return result;
}

- (int32_t)resamplingFrame {
    int32_t result = 0;
    int32_t dstBufsize = 0;
    // 计算积压的延迟数据
    int64_t delay = swr_get_delay(swrCtx, srcRate);
    /*
     计算实际读取样本的数量
     size：每次从文件读取的大小
     除以每个样本的大小，就得到实际读取样本数量
     */
    dstNbSamples = (int32_t)av_rescale_rnd(delay + srcNbSamples, dstRate, srcRate, AV_ROUND_UP);
    if (dstNbSamples > maxDstNbSamples) {
        av_freep(&dstData[0]);
        result = av_samples_alloc(dstData,
                                  &dstLinesize,
                                  dstNbChannels,
                                  dstNbSamples,
                                  dstSampleFmt,
                                  1);
        if (result < 0) {
            fprintf(stderr, "Error:failed to reallocat dstData.\n");
            return -1;
        }
        fprintf(stderr, "nbSamples exceeds maxDstNbSamples, buffer reallocated\n");
        maxDstNbSamples = dstNbSamples;
    }
    
    /*
     重采样
     result: 转换后的样本数量
     */
    result = swr_convert(swrCtx,
                         dstData,
                         dstNbSamples,
                         (const uint8_t **)inputFrame->data,
                         srcNbSamples);
    if (result < 0) {
        fprintf(stderr, "Error:swr_convert failed.\n");
        return -1;
    }
    // 返回指定格式音频的缓存大小
    dstBufsize = av_samples_get_buffer_size(&dstLinesize,
                                             dstNbChannels,
                                             result,
                                             dstSampleFmt,
                                             1);
    if (dstBufsize < 0) {
        fprintf(stderr, "Error:Could not get sample buffer size.\n");
        return -1;
    }
    
    printf("dstBufSize: %d.\n", dstBufsize);
    [self writePacketToFile:dstData[0] size:dstBufsize];
    return result;
}

- (int32_t)readPCMToFrame {
    // 单个声道一个样本的大小（假如是两声道就是一个 L，或者是一个 R的大小）
    int singleSize = av_get_bytes_per_sample(srcSampleFmt);
    // 所有声道单个样本的总大小（假如是两声道就是一个LR）
    int totalSize = srcNbChannels *singleSize;
    if (singleSize < 0) {
        /* This should not occur, checking just for paranoia */
        fprintf(stderr, "Failed to calculate sample size.\n");
        return -1;
    }
    if (av_sample_fmt_is_planar(srcSampleFmt)) {
        /*
         假如 PCM 是这样：LLLLLRRRRR
         那单个声道的样本数就是：frame->nb_samples，这里等于5;
         那声道数这里等于2
         */
        for (int sampleIdx = 0; sampleIdx < srcNbSamples; sampleIdx++) {// for:单个声道的样本数
            for (int channelIdx = 0; channelIdx < srcNbChannels; channelIdx++) {//for: 声道数
                // 写入frame的顺序是：先左声道写入一个样本L；再右声道写入一个样本R；然后移动指针，指向下个样本；然后重复上面的操作，直到文件尾部
                fread(inputFrame->data[channelIdx] + sampleIdx *singleSize, 1, singleSize, srcFile);
            }
        }
    } else {// PCM 是 packed
        fread(inputFrame->data[0], 1, totalSize *srcNbSamples, srcFile);
    }
    return 0;
}

- (void)destroyAudioResampler {
    if (inputFrame) {
        av_frame_free(&inputFrame);
    }
    if (dstData) av_freep(&dstData[0]);
    av_freep(&dstData);
    swr_free(&swrCtx);
}

#pragma mark - File related
/// 将编码后的数据写入到文件中
- (void)writePacketToFile:(const uint8_t *)buf size:(int32_t)size {
    fwrite(buf, 1, size, destFile);
}

- (void)closeFile:(FILE *)file {
    if (file) {
        fclose(file);
        file = NULL;
    }
}

- (BOOL)openFile:(const char*)srcFilePath dstFilePath:(const char *)dstFilePath {
    if (strlen(srcFilePath) == 0 || strlen(dstFilePath) == 0) {
        return NO;
    }
    [self closeFile:srcFile];
    [self closeFile:destFile];
    
    srcFile = fopen(srcFilePath, "rb");
    if (srcFile == NULL) {
        return NO;
    }
    destFile = fopen(dstFilePath, "wb");
    if (destFile == NULL) {
        return NO;
    }
    
    return YES;
}

- (int)endOfFile:(FILE *)file {
    if (!file) {
        fprintf(stderr, "Error: file is empty.\n");
        return 1;
    }
    return feof(file);
}

@end
