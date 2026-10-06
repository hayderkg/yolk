#include "PortInspector.h"
#include <libproc.h>
#include <sys/proc_info.h>
#include <sys/socket.h>
#include <arpa/inet.h>
#include <signal.h>
#include <unistd.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>

static int same_identity(LPIdentity a, LPIdentity b) {
    return a.pid == b.pid && a.uid == b.uid &&
        a.start_seconds == b.start_seconds && a.start_microseconds == b.start_microseconds;
}

int lp_identity(int32_t pid, LPIdentity *identity) {
    struct proc_bsdinfo info = {0};
    errno = 0;
    if (proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, sizeof(info)) != sizeof(info))
        return errno ? errno : ESRCH;
    *identity = (LPIdentity){pid, info.pbi_uid, info.pbi_start_tvsec, info.pbi_start_tvusec};
    return 0;
}

int lp_signal(LPIdentity expected, int signal_number) {
    if (expected.pid <= 1 || expected.pid == getpid() || expected.uid != geteuid()) return EPERM;
    if (signal_number != SIGTERM && signal_number != SIGKILL) return EINVAL;
    LPIdentity current;
    int error = lp_identity(expected.pid, &current);
    if (error) return error;
    if (!same_identity(expected, current)) return ESTALE;
    if (kill(expected.pid, signal_number) != 0) return errno;
    return 0;
}

int lp_details(LPIdentity expected, LPDetails *details) {
    LPIdentity current;
    memset(details, 0, sizeof(*details));
    int error = lp_identity(expected.pid, &current);
    if (error) return error;
    if (!same_identity(expected, current)) return ESTALE;
    proc_pidpath(expected.pid, details->executable, sizeof(details->executable));
    struct proc_vnodepathinfo paths = {0};
    if (proc_pidinfo(expected.pid, PROC_PIDVNODEPATHINFO, 0, &paths, sizeof(paths)) == sizeof(paths))
        strlcpy(details->working_directory, paths.pvi_cdir.vip_path, sizeof(details->working_directory));
    error = lp_identity(expected.pid, &current);
    if (error || !same_identity(expected, current)) {
        memset(details, 0, sizeof(*details));
        return error ? error : ESTALE;
    }
    return 0;
}

static int local_address(const struct socket_info *socket, char *address) {
    const struct in_sockinfo *internet = &socket->soi_proto.pri_tcp.tcpsi_ini;
    if (socket->soi_family == AF_INET) {
        struct in_addr ip = internet->insi_laddr.ina_46.i46a_addr4;
        uint32_t host = ntohl(ip.s_addr);
        if (host != INADDR_ANY && (host >> 24) != 127) return 0;
        return inet_ntop(AF_INET, &ip, address, 46) != NULL;
    }
    if (socket->soi_family == AF_INET6) {
        struct in6_addr ip = internet->insi_laddr.ina_6;
        if (IN6_IS_ADDR_V4MAPPED(&ip)) {
            struct in_addr v4;
            memcpy(&v4, &ip.s6_addr[12], sizeof(v4));
            uint32_t host = ntohl(v4.s_addr);
            if (host != INADDR_ANY && (host >> 24) != 127) return 0;
            return inet_ntop(AF_INET, &v4, address, 46) != NULL;
        }
        if (!IN6_IS_ADDR_LOOPBACK(&ip) && !IN6_IS_ADDR_UNSPECIFIED(&ip)) return 0;
        return inet_ntop(AF_INET6, &ip, address, 46) != NULL;
    }
    return 0;
}

LPScan lp_scan(void) {
    LPScan result = {0};
    int estimate = proc_listallpids(NULL, 0);
    if (estimate <= 0) { result.error_code = errno ? errno : EIO; return result; }
    size_t capacity = (size_t)estimate + 128;
    pid_t *pids = NULL;
    int count = 0;
    // Allow the process list to grow while enumerating it.
    for (int attempt = 0; attempt < 3; attempt++) {
        free(pids);
        pids = calloc(capacity, sizeof(pid_t));
        if (!pids) { result.error_code = ENOMEM; return result; }
        count = proc_listallpids(pids, (int)(capacity * sizeof(pid_t)));
        if (count < (int)capacity) break;
        capacity *= 2;
    }
    if (count <= 0) {
        result.error_code = errno ? errno : EIO;
        free(pids);
        return result;
    }
    size_t item_capacity = 64;
    result.items = calloc(item_capacity, sizeof(LPListener));
    if (!result.items) { result.error_code = ENOMEM; free(pids); return result; }

    for (int index = 0; index < count; index++) {
        pid_t pid = pids[index];
        LPIdentity before, after;
        if (pid <= 0 || lp_identity(pid, &before)) continue;
        int bytes = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, NULL, 0);
        if (bytes <= 0) continue; // Exited or inaccessible to the current user.
        struct proc_fdinfo *fds = NULL;
        int read_bytes = 0;
        for (int attempt = 0; attempt < 3; attempt++) {
            bytes += 32 * (int)sizeof(struct proc_fdinfo);
            free(fds);
            fds = malloc((size_t)bytes);
            if (!fds) { result.error_code = ENOMEM; break; }
            read_bytes = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, fds, bytes);
            if (read_bytes < bytes) break;
            bytes *= 2;
        }
        if (!fds) break;
        size_t first_item = result.count;
        char name[256] = {0};
        proc_name(pid, name, sizeof(name));
        name[sizeof(name) - 1] = 0;
        for (int fd = 0; fd < read_bytes / (int)sizeof(*fds); fd++) {
            if (fds[fd].proc_fdtype != PROX_FDTYPE_SOCKET) continue;
            struct socket_fdinfo socket = {0};
            if (proc_pidfdinfo(pid, fds[fd].proc_fd, PROC_PIDFDSOCKETINFO,
                               &socket, sizeof(socket)) != sizeof(socket)) continue;
            if (socket.psi.soi_kind != SOCKINFO_TCP ||
                socket.psi.soi_proto.pri_tcp.tcpsi_state != TSI_S_LISTEN) continue;
            LPListener item = {0};
            if (!local_address(&socket.psi, item.address)) continue;
            item.port = ntohs((uint16_t)socket.psi.soi_proto.pri_tcp.tcpsi_ini.insi_lport);
            if (!item.port) continue;
            item.identity = before;
            strlcpy(item.name, name, sizeof(item.name));
            if (result.count == item_capacity) {
                item_capacity *= 2;
                LPListener *grown = realloc(result.items, item_capacity * sizeof(LPListener));
                if (!grown) { result.error_code = ENOMEM; break; }
                result.items = grown;
            }
            result.items[result.count++] = item;
        }
        free(fds);
        // Discard a snapshot if this PID changed owner or was reused mid-scan.
        if (lp_identity(pid, &after) || !same_identity(before, after)) result.count = first_item;
        if (result.error_code) break;
    }
    free(pids);
    return result;
}

void lp_free_scan(LPScan scan) { free(scan.items); }
