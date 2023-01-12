//
//  EncodeUtil.m
//  ffmpegAudio2
//
//  Created by EBM on 2023/1/9.
//

#import "EncodeUtil.h"
#import "ResampleUtil.h"

#ifdef __cplusplus
extern "C" {
#endif

#include "libavformat/avformat.h"
#include "libavcodec/avcodec.h"
#include "libavutil/avutil.h"
#include "libswscale/swscale.h"
#include "libswresample/swresample.h"
#include "libavutil/opt.h"

#ifdef __cplusplus
};

#endif
// 输入文件
static FILE *srcFile = NULL;
// 输出文件
static FILE *destFile = NULL;
// 编码器
static const AVCodec *codec = NULL;
// 编码器上下文
static AVCodecContext *codecCtx = NULL;
// AVFrame
static AVFrame *frame = NULL;
// AVPacket
static AVPacket *pkt = NULL;
static const NSString *errorDomain = @"encoderError";

@interface EncodeUtil()

@property (strong, nonatomic) ResampleUtil *resampleUtil;

@end

@implementation EncodeUtil
- (instancetype)init {
    if (self = [super init]) {
        self.resampleUtil = [[ResampleUtil alloc] init];
    }
    return self;
}

- (void)encodeFromSrcPath:(NSString *)srcPath toDestPath:(NSString *)destPath error:(NSError **)error{
    if (!srcPath || !destPath) {
        *error = [NSError errorWithDomain:(NSString *)errorDomain code:0 userInfo:[NSDictionary dictionaryWithObject:@"Empty path" forKey:NSLocalizedDescriptionKey]];
        return;
    }
    
    NSString *reSrcPath = [[srcPath stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"repcm.pcm"];
    const char *reSrcFileName = [reSrcPath UTF8String];
    const char *destFileName = [destPath UTF8String];
    [self.resampleUtil swrContext:srcPath destFile:reSrcPath];
    
    if (![self openFile:reSrcFileName dstFilePath:destFileName]) {
        *error = [NSError errorWithDomain:(NSString *)errorDomain code:0 userInfo:[NSDictionary dictionaryWithObject:@"Open file failed" forKey:NSLocalizedDescriptionKey]];
        goto end;
    }
    
    if ([self initAudioEncoder:"AAC" error:error] < 0) {
        goto end;
    }
    
    if ([self audioEncoding:error] < 0) {
        goto end;
    }
    
end:
    [self destoryAudioEncoder];
    [self closeFile:srcFile];
    [self closeFile:destFile];
}

- (void)destoryAudioEncoder {
    if (frame) {
        av_frame_free(&frame);
    }
    if (pkt) {
        av_packet_free(&pkt);
    }
    if (codecCtx) {
        avcodec_free_context(&codecCtx);
    }
}

/// 初始化音频编码器等
- (int32_t)initAudioEncoder:(const char *)codecName error:(NSError **)error {
    if (strcasecmp(codecName, "AAC") == 0) {
        // 可以使用 libfdk_aac 进行编码（AV_CODEC_ID_AAC表示 FFmpeg 官方自带的 AAC 编解码器）
//        codec = avcodec_find_encoder(AV_CODEC_ID_AAC);
        codec = avcodec_find_encoder_by_name("libfdk_aac");
        printf("codec id: AAC.\n");
    } else {
        fprintf(stderr, "Error: invalid audio format.\n");
        *error = [NSError errorWithDomain:(NSString *)errorDomain code:0 userInfo:[NSDictionary dictionaryWithObject:@"Error: invalid audio format." forKey:NSLocalizedDescriptionKey]];
        return -1;
    }
    if (!codec) {
        fprintf(stderr, "Error: could not find codec.\n");
        *error = [NSError errorWithDomain:(NSString *)errorDomain code:0 userInfo:[NSDictionary dictionaryWithObject:@"Error: could not find codec." forKey:NSLocalizedDescriptionKey]];
        return -1;
    }
    
    // 初始化解码器上下文
    codecCtx = avcodec_alloc_context3(codec);
    if (!codecCtx) {
        fprintf(stderr, "Error: could not alloc codec.\n");
        *error = [NSError errorWithDomain:(NSString *)errorDomain code:0 userInfo:[NSDictionary dictionaryWithObject:@"Error: could not alloc codec." forKey:NSLocalizedDescriptionKey]];
        return -1;
    }

    codecCtx->sample_rate = 44100;
    codecCtx->channel_layout = AV_CH_LAYOUT_STEREO;
    codecCtx->channels = av_get_channel_layout_nb_channels(codecCtx->channel_layout);
    codecCtx->profile = FF_PROFILE_AAC_LOW;// 默认值
    codecCtx->bit_rate = 128000;
    codecCtx->sample_fmt = AV_SAMPLE_FMT_S16;
    // 检查编码器是否支持该采样格式
//    if ([self checkSampleFormat:codec sampleFormat:codecCtx->sample_fmt] <= 0) {
//        fprintf(stderr, "Error: encoder does not support sample format: %s",
//                av_get_sample_fmt_name(codecCtx->sample_fmt));
//        return -1;
//    }
    
    
    // 打开编码器
    int32_t result = avcodec_open2(codecCtx, codec, NULL);
    if (result < 0) {
        fprintf(stderr, "Error: could not open codec.\n");
        *error = [NSError errorWithDomain:(NSString *)errorDomain code:0 userInfo:[NSDictionary dictionaryWithObject:@"Error: could not open codec." forKey:NSLocalizedDescriptionKey]];
        return -1;
    }
    
    // 初始化 AVFrame
    frame = av_frame_alloc();
    if (!frame) {
        fprintf(stderr, "Error: could not alloc frame.\n");
        *error = [NSError errorWithDomain:(NSString *)errorDomain code:0 userInfo:[NSDictionary dictionaryWithObject:@"Error: could not alloc frame." forKey:NSLocalizedDescriptionKey]];
        return -1;
    }
    
    frame->nb_samples = codecCtx->frame_size;
    frame->format = codecCtx->sample_fmt;
    frame->channel_layout = codecCtx->channel_layout;
    frame->sample_rate = codecCtx->sample_rate;
    // 设置好 frame 参数后，可以创建 PCM 缓冲区
    result = av_frame_get_buffer(frame, 0);
    if (result < 0) {
        fprintf(stderr, "Error: frame could not get buffer.\n");
        *error = [NSError errorWithDomain:(NSString *)errorDomain code:0 userInfo:[NSDictionary dictionaryWithObject:@"Error: frame could not get buffer." forKey:NSLocalizedDescriptionKey]];
        return -1;
    }
    
    // 初始化 AVPacket
    pkt = av_packet_alloc();
    if (!pkt) {
        fprintf(stderr, "Error: could not alloc packet.\n");
        *error = [NSError errorWithDomain:(NSString *)errorDomain code:0 userInfo:[NSDictionary dictionaryWithObject:@"Error: could not alloc packet." forKey:NSLocalizedDescriptionKey]];
        return -1;
    }
    return 0;
}

// 音频编码
- (int32_t)audioEncoding:(NSError **)error {
    size_t size = 0;
    int32_t result = 0;
    while (![self endOfFile:srcFile]) {
        result = [self readPCMToFrame:frame
                         codecContext:codecCtx
                             readSize:&size];
        
        
        if (result < 0) {
            fprintf(stderr, "Error: readPCMToFrame:codecContext: failed.\n");
            *error = [NSError errorWithDomain:(NSString *)errorDomain code:0 userInfo:[NSDictionary dictionaryWithObject:@"Error: readPCMToFrame:codecContext: failed." forKey:NSLocalizedDescriptionKey]];
            return -1;
        }
        
        // 编码
        result = [self encodeFrameWithFlushing:NO];
        if (result < 0) {
            fprintf(stderr, "Error: encodeFrame: failed.\n");
            *error = [NSError errorWithDomain:(NSString *)errorDomain code:0 userInfo:[NSDictionary dictionaryWithObject:@"Error: encodeFrame: failed." forKey:NSLocalizedDescriptionKey]];
            return result;
        }
    }
    
    // 冲刷缓冲区
    result = [self encodeFrameWithFlushing:YES];
    if (result < 0) {
        fprintf(stderr, "Error: flushing failed.\n");
        *error = [NSError errorWithDomain:(NSString *)errorDomain code:0 userInfo:[NSDictionary dictionaryWithObject:@"Error: flushing failed." forKey:NSLocalizedDescriptionKey]];
        return result;
    }
    return 0;
}

/// 读取 PCM 数据到 AVFrame
/// @param frame AVFrame（最后存在 AVFrame 中的数据是多个声道交替存储的，而非 planar）
/// @param codecCtx 编码器上下文
/// @param size 读取文件的大小
- (int32_t)readPCMToFrame:(AVFrame *)frame codecContext:(AVCodecContext *)codecCtx readSize:(size_t *)size {
    // 单个声道一个样本的大小（假如是两声道就是一个 L，或者是一个 R）
    int singleSize = av_get_bytes_per_sample(codecCtx->sample_fmt);
    // 所有声道单个样本的总大小（假如是两声道就是一个LR）
    int totalSize = codecCtx->channels *singleSize;
    if (singleSize < 0) {
        fprintf(stderr, "Error: failed to calculate data size");
        return -1;
    }
    
    if (av_sample_fmt_is_planar(codecCtx->sample_fmt)) {// PCM 是 planar
        /*
         假如 PCM 是这样：LLLLLRRRRR
         那单个声道的样本数就是：frame->nb_samples，这里等于5;
         那声道数就是2
         */
        for (int sampleIdx = 0; sampleIdx < frame->nb_samples; sampleIdx++) {// for:单个声道的样本数
            for (int channelIdx = 0; channelIdx < codecCtx->channels; channelIdx++) {//for: 声道数
                // 写入frame的顺序是：先左声道写入一个样本L；再右声道写入一个样本R；然后移动指针，指向下个样本；然后重复上面的操作，直到文件尾部
                *size = fread(frame->data[channelIdx] + sampleIdx *singleSize, 1, singleSize, srcFile);
            }
        }
    } else {// PCM 是 packed
        *size = fread(frame->data[0], 1, totalSize *frame->nb_samples, srcFile);
    }
    
    return 0;
}

// 编码
- (int32_t)encodeFrameWithFlushing:(BOOL)flushing {
    int32_t result = 0;
    /*
     从 frame 中获取到重采样后的 PCM 数据，然后将数据发送到 codec 中.
     frame为 NULL 的时候，表示冲刷缓冲区
     */
    result = avcodec_send_frame(codecCtx, flushing ? NULL : frame);
    if (result < 0) {
        fprintf(stderr, "Error: avcodec_send_frame failed.\n");
        return -1;
    }
    
    while (result >= 0) {
        // 从编码器中获取编码后的数据，存放到 AVPacket 中
        result = avcodec_receive_packet(codecCtx, pkt);
        // AVERROR(EAGAIN): 编码器还没有完成对新的 1 帧的编码，应该继续通过函数 avcodec_send_frame 传入后续的图像
        // AVERROR_EOF: 编码器已经完全输出内部的数据，编码完成
        if (result == AVERROR(EAGAIN) || result == AVERROR_EOF) {
            return 1;
        } else if (result < 0) {
            fprintf(stderr, "Error: avcodec_receive_packet failed.\n");
            return result;
        }
        // 写入文件
        [self writePacketToFile:pkt];
        // 释放 pkt 所指向的缓冲区的引用
        av_packet_unref(pkt);
    }
    
    return 0;
}

#pragma mark - File related
/// 将编码后的数据写入到文件中
/// @param pkt 码流包
- (void)writePacketToFile:(AVPacket *)pkt {
    fwrite(pkt->data, 1, pkt->size, destFile);
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
