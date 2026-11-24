// 进程级采样：CPU 占用 + 物理内存 footprint（活动监视器口径）
// 用 C 实现以规避 Swift 对 libproc rusage 指针的 ABI 问题。
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <libproc.h>
#include <sys/resource.h>
#include <mach/mach_time.h>

#define MAX_PROCS 512

typedef struct {
    int pid;
    double cpu;                // 0...1，相对单核
    unsigned long long mem;    // bytes (phys_footprint)
    const char *name;          // 指向内部静态缓冲
    const char *path;
} GlanceProc;

typedef struct {
    int pid;
    unsigned long long cpu_time;
} CpuTick;

static CpuTick prev_ticks[MAX_PROCS];
static int prev_count = 0;
static uint64_t prev_mach = 0;
static char name_buf[MAX_PROCS][64];
static char path_buf[MAX_PROCS][512];

static double mach_elapsed_ns(uint64_t now, uint64_t prev) {
    mach_timebase_info_data_t tb;
    mach_timebase_info(&tb);
    uint64_t d = now > prev ? now - prev : 0;
    return (double)d * (double)tb.numer / (double)tb.denom;
}

/// 采样所有进程。返回写入数量。out 容量至少 MAX_PROCS。
/// 首次调用只建立基线，返回 0。
int glance_procs_sample(GlanceProc *out, int cap) {
    uint64_t now = mach_absolute_time();
    int n = proc_listallpids(NULL, 0);
    if (n <= 0) return 0;
    int arr_cap = n + 32;
    int *pids = (int *)calloc(arr_cap, sizeof(int));
    if (!pids) return 0;
    int got = proc_listallpids(pids, arr_cap * sizeof(int));
    if (got <= 0) { free(pids); return 0; }

    CpuTick current[MAX_PROCS];
    int cur_count = 0;
    int out_count = 0;
    double elapsed = prev_mach ? mach_elapsed_ns(now, prev_mach) : 0;

    for (int i = 0; i < got && cur_count < MAX_PROCS; i++) {
        int pid = pids[i];
        if (pid <= 0 || pid == getpid()) continue;

        struct rusage_info_v4 ri;
        memset(&ri, 0, sizeof(ri));
        if (proc_pid_rusage(pid, RUSAGE_INFO_V4, (rusage_info_t *)&ri) != 0) continue;

        unsigned long long cpu_time = ri.ri_user_time + ri.ri_system_time;
        current[cur_count].pid = pid;
        current[cur_count].cpu_time = cpu_time;
        cur_count++;

        if (!prev_mach) continue; // 首次仅建立基线

        double cpu = 0;
        for (int j = 0; j < prev_count; j++) {
            if (prev_ticks[j].pid == pid) {
                unsigned long long d = cpu_time > prev_ticks[j].cpu_time
                    ? cpu_time - prev_ticks[j].cpu_time : 0;
                if (elapsed > 0) cpu = (double)d / elapsed;
                break;
            }
        }
        if (cpu > 1) cpu = 1;

        if (out_count < cap) {
            GlanceProc *p = &out[out_count];
            p->pid = pid;
            p->cpu = cpu;
            p->mem = (unsigned long long)ri.ri_phys_footprint;

            name_buf[out_count][0] = '\0';
            path_buf[out_count][0] = '\0';
            if (proc_name(pid, name_buf[out_count], sizeof(name_buf[out_count])) > 0) {
                p->name = name_buf[out_count];
            } else {
                p->name = "";
            }
            if (proc_pidpath(pid, path_buf[out_count], sizeof(path_buf[out_count])) > 0) {
                p->path = path_buf[out_count];
            } else {
                p->path = "";
            }
            out_count++;
        }
    }

    memcpy(prev_ticks, current, cur_count * sizeof(CpuTick));
    prev_count = cur_count;
    prev_mach = now;
    free(pids);
    return out_count;
}
