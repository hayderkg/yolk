#ifndef PORT_INSPECTOR_H
#define PORT_INSPECTOR_H

#include <stdint.h>
#include <stddef.h>

typedef struct {
    int32_t pid;
    uint32_t uid;
    uint64_t start_seconds;
    uint64_t start_microseconds;
} LPIdentity;

typedef struct {
    LPIdentity identity;
    uint16_t port;
    char address[46];
    char name[256];
} LPListener;

typedef struct {
    LPListener *items;
    size_t count;
    int error_code;
} LPScan;

typedef struct {
    char executable[4096];
    char working_directory[1024];
} LPDetails;

LPScan lp_scan(void);
void lp_free_scan(LPScan scan);
int lp_identity(int32_t pid, LPIdentity *identity);
int lp_details(LPIdentity expected, LPDetails *details);
// Returns an errno value. Revalidates the process birth time and owner before signaling.
int lp_signal(LPIdentity expected, int signal_number);

#endif
