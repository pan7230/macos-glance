// IOReport 私有框架封装（纯 C，避免 Swift 调用 SPI 的 ABI 陷阱）
// dlopen + dlsym，任何失败都返回 0/安全值，不让调用方崩溃。
#include <CoreFoundation/CoreFoundation.h>
#include <dlfcn.h>
#include <stdint.h>
#include <string.h>
#include <unistd.h>
#include <math.h>

typedef CFMutableDictionaryRef (*CopyGroupFn)(CFStringRef, CFStringRef, uint64_t, uint64_t, uint64_t);
typedef void *(*CreateSubFn)(void *, CFMutableDictionaryRef, CFMutableDictionaryRef *, uint64_t, CFTypeRef);
typedef CFDictionaryRef (*SamplesFn)(void *, CFMutableDictionaryRef, CFTypeRef);
typedef CFDictionaryRef (*DeltaFn)(CFDictionaryRef, CFDictionaryRef, CFTypeRef);
typedef CFStringRef (*GetStrFn)(CFDictionaryRef);
typedef int64_t (*SimpleValFn)(CFDictionaryRef, int32_t *);
typedef uint32_t (*StateCountFn)(CFDictionaryRef);
typedef CFStringRef (*StateNameFn)(CFDictionaryRef, int32_t);
typedef uint64_t (*StateResidencyFn)(CFDictionaryRef, int32_t);

// 供 Swift 使用的结果
typedef struct {
    double gpu_util;   // 0...1, <0 表示不可用
    double power_w;    // 瓦, <0 表示不可用
    double disk_temp;  // 摄氏度, <0 表示不可用
} GlanceIOResult;

static void *g_handle = NULL;
static void *g_gpu_sub = NULL, *g_gpu_subbed = NULL;
static void *g_eng_sub = NULL, *g_eng_subbed = NULL;
static CopyGroupFn pCopyGroup;
static CreateSubFn pCreateSub;
static SamplesFn pSamples;
static DeltaFn pDelta;
static GetStrFn pName, pUnit, pGroup;
static SimpleValFn pSimple;
static StateCountFn pStateCount;
static StateNameFn pStateName;
static StateResidencyFn pStateRes;
static int g_ready = 0;

static void load(void) {
    if (g_ready) return;
    g_ready = 1;
    const char *paths[] = {"/usr/lib/libIOReport.dylib",
        "/System/Library/PrivateFrameworks/IOReport.framework/IOReport"};
    for (int i = 0; i < 2; i++) {
        g_handle = dlopen(paths[i], RTLD_LAZY);
        if (g_handle) break;
    }
    if (!g_handle) return;
#define B(v,n) v=(void*)dlsym(g_handle,n); if(!v){dlclose(g_handle);g_handle=NULL;return;}
    B(pCopyGroup,"IOReportCopyChannelsInGroup"); B(pCreateSub,"IOReportCreateSubscription");
    B(pSamples,"IOReportCreateSamples"); B(pDelta,"IOReportCreateSamplesDelta");
    B(pName,"IOReportChannelGetChannelName"); B(pUnit,"IOReportChannelGetUnitLabel");
    B(pGroup,"IOReportChannelGetGroup"); B(pSimple,"IOReportSimpleGetIntegerValue");
    B(pStateCount,"IOReportStateGetCount"); B(pStateName,"IOReportStateGetNameForIndex");
    B(pStateRes,"IOReportStateGetResidency");
#undef B
}

static void subscribe(const char *group, void **sub, void **subbed) {
    CFStringRef g = CFStringCreateWithCString(NULL, group, kCFStringEncodingUTF8);
    CFMutableDictionaryRef chans = pCopyGroup(g, NULL, 0,0,0);
    CFRelease(g);
    if (!chans) return;
    CFMutableDictionaryRef out = NULL;
    void *s = pCreateSub(NULL, chans, &out, 0, NULL);
    if (s && out) { *sub = s; *subbed = out; }
}

void glance_io_init(void) {
    load();
    if (!g_handle) return;
    subscribe("GPU Stats", &g_gpu_sub, &g_gpu_subbed);
    subscribe("Energy Model", &g_eng_sub, &g_eng_subbed);
}

static const char *cstr(CFStringRef s, char *buf, size_t n) {
    buf[0]=0; if (s) CFStringGetCString(s, buf, n, kCFStringEncodingUTF8); return buf;
}

// GPU 占用：GPUPH 状态里 OFF 之外的 residency 占比
static double gpu_util(void) {
    if (!g_gpu_sub || !g_gpu_subbed) return -1;
    CFDictionaryRef s1 = pSamples(g_gpu_sub, g_gpu_subbed, NULL);
    usleep(200000);
    CFDictionaryRef s2 = pSamples(g_gpu_sub, g_gpu_subbed, NULL);
    if (!s1 || !s2) return -1;
    CFDictionaryRef d = pDelta(s1, s2, NULL);
    if (s1) CFRelease(s1); if (s2) CFRelease(s2);
    if (!d) return -1;
    CFArrayRef items = CFDictionaryGetValue(d, CFSTR("IOReportChannels"));
    double off = 0, awake = 0;
    if (items) {
        CFIndex n = CFArrayGetCount(items);
        for (CFIndex i=0;i<n;i++) {
            CFDictionaryRef ch = CFArrayGetValueAtIndex(items,i);
            char name[128]; cstr(pName(ch), name, sizeof(name));
            if (strcmp(name,"GPUPH")!=0) continue;
            uint32_t cnt = pStateCount(ch);
            if (cnt==0 || cnt>64) continue;
            for (uint32_t s=0;s<cnt;s++) {
                uint64_t res = pStateRes(ch,(int32_t)s);
                if (res > (uint64_t)1<<62) continue; // 空 bucket 哨兵
                char sn[64]; cstr(pStateName(ch,(int32_t)s),sn,sizeof(sn));
                if (strcmp(sn,"OFF")==0) off += (double)res; else awake += (double)res;
            }
        }
    }
    CFRelease(d);
    double tot = off+awake;
    if (tot<=0) return -1;
    double u = awake/tot;
    return u<0?0:u>1?1:u;
}

// 系统功耗：Energy Model 聚合通道（macOS 27 可能在 1s 窗口内读到 0，由 Swift 侧缓存）
static double power(void) {
    if (!g_eng_sub || !g_eng_subbed) return -1;
    CFDictionaryRef s1 = pSamples(g_eng_sub, g_eng_subbed, NULL);
    usleep(2200000);
    CFDictionaryRef s2 = pSamples(g_eng_sub, g_eng_subbed, NULL);
    if (!s1 || !s2) return -1;
    CFDictionaryRef d = pDelta(s1,s2,NULL);
    if (s1) CFRelease(s1); if (s2) CFRelease(s2);
    if (!d) return -1;
    CFArrayRef items = CFDictionaryGetValue(d, CFSTR("IOReportChannels"));
    double total = 0; int found = 0;
    if (items) {
        CFIndex n = CFArrayGetCount(items);
        for (CFIndex i=0;i<n;i++) {
            CFDictionaryRef ch = CFArrayGetValueAtIndex(items,i);
            char name[128],unit[32];
            cstr(pName(ch),name,sizeof(name)); cstr(pUnit(ch),unit,sizeof(unit));
            size_t len=strlen(name);
            if (len<8 || strcmp(name+len-8," Energy")!=0) continue;
            double scale = !strcmp(unit,"J")?1:!strcmp(unit,"mJ")?1e-3:!strcmp(unit,"uJ")?1e-6:!strcmp(unit,"nJ")?1e-9:0;
            if (scale<=0) continue;
            int64_t raw = pSimple(ch,NULL);
            if (raw<=0) continue;
            total += (double)raw*scale/2.2;
            found=1;
        }
    }
    CFRelease(d);
    return found?total:-1;
}

GlanceIOResult glance_io_sample(void) {
    GlanceIOResult r; r.gpu_util=-1; r.power_w=-1; r.disk_temp=-1;
    if (!g_handle) return r;
    r.gpu_util = gpu_util();
    r.power_w = power();
    return r;
}
