/*
 * WordCore runtime — wc.native: platform info, time, filesystem, sockets, randomness.
 * Copyright (C) 2026 WordCore contributors. GPLv3 + WordCore Addon and Theme Exception.
 *
 * Kept deliberately small: anything that can be written in Lua is written in Lua.
 */
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include "lua.h"
#include "lauxlib.h"
#include "wc_native.h"

#if defined(_WIN32)
  #define WIN32_LEAN_AND_MEAN
  #include <winsock2.h>
  #include <ws2tcpip.h>
  #include <windows.h>
  #include <bcrypt.h>
  #include <direct.h>
  #include <fcntl.h>
  #include <io.h>
  #include <sys/stat.h>
  typedef SOCKET wc_sock;
  #define WC_BADSOCK INVALID_SOCKET
  #define wc_closesock closesocket
  #define WC_PLATFORM "windows"
#else
  #include <dirent.h>
  #include <fcntl.h>
  #include <netdb.h>
  #include <netinet/in.h>
  #include <netinet/tcp.h>
  #include <poll.h>
  #include <arpa/inet.h>
  #include <sys/socket.h>
  #include <sys/stat.h>
  #include <sys/time.h>
  #include <sys/types.h>
  #include <unistd.h>
  typedef int wc_sock;
  #define WC_BADSOCK (-1)
  #define wc_closesock close
  #if defined(__APPLE__)
    #include <mach-o/dyld.h>
    #define WC_PLATFORM "macos"
  #elif defined(__linux__)
    #include <sys/random.h>
    #define WC_PLATFORM "linux"
  #else
    #define WC_PLATFORM "other"
  #endif
#endif

#if defined(__x86_64__) || defined(_M_X64)
  #define WC_ARCH "x86_64"
#elif defined(__aarch64__) || defined(_M_ARM64)
  #define WC_ARCH "arm64"
#else
  #define WC_ARCH "unknown"
#endif

/* ------------------------------------------------------------------ time */

double wc_process_start = 0.0;

double wc_now_seconds(void) {
#if defined(_WIN32)
  static LARGE_INTEGER freq = {0};
  LARGE_INTEGER now;
  if (freq.QuadPart == 0) QueryPerformanceFrequency(&freq);
  QueryPerformanceCounter(&now);
  return (double)now.QuadPart / (double)freq.QuadPart;
#else
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return (double)ts.tv_sec + (double)ts.tv_nsec / 1e9;
#endif
}

static int n_now(lua_State *L) {
  lua_pushnumber(L, wc_now_seconds());
  return 1;
}

static int n_uptime(lua_State *L) {
  lua_pushnumber(L, wc_now_seconds() - wc_process_start);
  return 1;
}

static int n_unixtime(lua_State *L) {
#if defined(_WIN32)
  FILETIME ft;
  ULARGE_INTEGER u;
  GetSystemTimeAsFileTime(&ft);
  u.LowPart = ft.dwLowDateTime;
  u.HighPart = ft.dwHighDateTime;
  /* 100ns intervals since 1601 -> seconds since 1970 */
  lua_pushnumber(L, (double)(u.QuadPart - 116444736000000000ULL) / 1e7);
#else
  struct timeval tv;
  gettimeofday(&tv, NULL);
  lua_pushnumber(L, (double)tv.tv_sec + (double)tv.tv_usec / 1e6);
#endif
  return 1;
}

static int n_sleep(lua_State *L) {
  double s = luaL_checknumber(L, 1);
  if (s < 0) s = 0;
#if defined(_WIN32)
  Sleep((DWORD)(s * 1000.0));
#else
  struct timespec ts;
  ts.tv_sec = (time_t)s;
  ts.tv_nsec = (long)((s - (double)ts.tv_sec) * 1e9);
  nanosleep(&ts, NULL);
#endif
  return 0;
}

/* -------------------------------------------------------------- platform */

static int n_platform(lua_State *L) {
  lua_pushstring(L, WC_PLATFORM);
  lua_pushstring(L, WC_ARCH);
  return 2;
}

static int n_exe_path(lua_State *L) {
  char buf[4096];
#if defined(_WIN32)
  DWORD n = GetModuleFileNameA(NULL, buf, (DWORD)sizeof(buf));
  if (n == 0 || n >= sizeof(buf)) return 0;
  lua_pushlstring(L, buf, n);
#elif defined(__APPLE__)
  uint32_t size = (uint32_t)sizeof(buf);
  char real[4096];
  if (_NSGetExecutablePath(buf, &size) != 0) return 0;
  if (realpath(buf, real) != NULL) lua_pushstring(L, real);
  else lua_pushstring(L, buf);
#else
  ssize_t n = readlink("/proc/self/exe", buf, sizeof(buf) - 1);
  if (n <= 0) return 0;
  buf[n] = '\0';
  lua_pushstring(L, buf);
#endif
  return 1;
}

static int n_getpid(lua_State *L) {
#if defined(_WIN32)
  lua_pushinteger(L, (lua_Integer)GetCurrentProcessId());
#else
  lua_pushinteger(L, (lua_Integer)getpid());
#endif
  return 1;
}

/* Put stdin/stdout in binary mode (matters on Windows only). */
static int n_stdio_binary(lua_State *L) {
#if defined(_WIN32)
  _setmode(_fileno(stdin), _O_BINARY);
  _setmode(_fileno(stdout), _O_BINARY);
#endif
  (void)L;
  return 0;
}

static int n_random_bytes(lua_State *L) {
  lua_Integer n = luaL_checkinteger(L, 1);
  luaL_argcheck(L, n >= 0 && n <= 65536, 1, "size out of range");
  luaL_Buffer b;
  char *p = luaL_buffinitsize(L, &b, (size_t)n);
  int ok = 0;
#if defined(_WIN32)
  ok = BCRYPT_SUCCESS(BCryptGenRandom(NULL, (PUCHAR)p, (ULONG)n, BCRYPT_USE_SYSTEM_PREFERRED_RNG));
#elif defined(__APPLE__)
  arc4random_buf(p, (size_t)n);
  ok = 1;
#elif defined(__linux__)
  size_t got = 0;
  while (got < (size_t)n) {
    ssize_t r = getrandom(p + got, (size_t)n - got, 0);
    if (r < 0) { if (errno == EINTR) continue; break; }
    got += (size_t)r;
  }
  ok = (got == (size_t)n);
#else
  FILE *f = fopen("/dev/urandom", "rb");
  if (f) { ok = fread(p, 1, (size_t)n, f) == (size_t)n; fclose(f); }
#endif
  if (!ok) return luaL_error(L, "secure random source unavailable");
  luaL_pushresultsize(&b, (size_t)n);
  return 1;
}

/* environ() -> { NAME = value, ... } */
#if !defined(_WIN32)
extern char **environ;
#endif
static int n_environ(lua_State *L) {
  lua_newtable(L);
#if defined(_WIN32)
  LPCH block = GetEnvironmentStringsA();
  if (!block) return 1;
  for (LPCH p = block; *p; p += strlen(p) + 1) {
    const char *eq = strchr(p + 1, '=');  /* skip leading '=' of hidden vars */
    if (!eq) continue;
    lua_pushlstring(L, p, (size_t)(eq - p));
    lua_pushstring(L, eq + 1);
    lua_rawset(L, -3);
  }
  FreeEnvironmentStringsA(block);
#else
  for (char **e = environ; e && *e; e++) {
    const char *eq = strchr(*e, '=');
    if (!eq) continue;
    lua_pushlstring(L, *e, (size_t)(eq - *e));
    lua_pushstring(L, eq + 1);
    lua_rawset(L, -3);
  }
#endif
  return 1;
}

/* ------------------------------------------------------------ filesystem */

static int push_errno(lua_State *L, const char *what) {
  lua_pushnil(L);
  lua_pushfstring(L, "%s: %s", what, strerror(errno));
  return 2;
}

static int n_stat(lua_State *L) {
  const char *path = luaL_checkstring(L, 1);
#if defined(_WIN32)
  struct _stat64 st;
  if (_stat64(path, &st) != 0) return 0;
  lua_pushstring(L, (st.st_mode & _S_IFDIR) ? "dir" : "file");
#else
  struct stat st;
  if (stat(path, &st) != 0) return 0;
  lua_pushstring(L, S_ISDIR(st.st_mode) ? "dir" : (S_ISREG(st.st_mode) ? "file" : "other"));
#endif
  lua_pushinteger(L, (lua_Integer)st.st_size);
  lua_pushinteger(L, (lua_Integer)st.st_mtime);
  return 3;
}

static int n_mkdir(lua_State *L) {
  const char *path = luaL_checkstring(L, 1);
#if defined(_WIN32)
  int r = _mkdir(path);
#else
  int r = mkdir(path, 0755);
#endif
  if (r != 0 && errno != EEXIST) return push_errno(L, path);
  lua_pushboolean(L, 1);
  return 1;
}

static int n_remove(lua_State *L) {
  const char *path = luaL_checkstring(L, 1);
#if defined(_WIN32)
  int r = remove(path);
  if (r != 0) r = _rmdir(path);
#else
  int r = remove(path);
#endif
  if (r != 0) return push_errno(L, path);
  lua_pushboolean(L, 1);
  return 1;
}

static int n_listdir(lua_State *L) {
  const char *path = luaL_checkstring(L, 1);
  lua_newtable(L);
  int i = 1;
#if defined(_WIN32)
  char pattern[4096];
  WIN32_FIND_DATAA fd;
  snprintf(pattern, sizeof(pattern), "%s\\*", path);
  HANDLE h = FindFirstFileA(pattern, &fd);
  if (h == INVALID_HANDLE_VALUE) { lua_pop(L, 1); return push_errno(L, path); }
  do {
    if (strcmp(fd.cFileName, ".") == 0 || strcmp(fd.cFileName, "..") == 0) continue;
    lua_pushstring(L, fd.cFileName);
    lua_rawseti(L, -2, i++);
  } while (FindNextFileA(h, &fd));
  FindClose(h);
#else
  DIR *d = opendir(path);
  if (!d) { lua_pop(L, 1); return push_errno(L, path); }
  struct dirent *e;
  while ((e = readdir(d)) != NULL) {
    if (strcmp(e->d_name, ".") == 0 || strcmp(e->d_name, "..") == 0) continue;
    lua_pushstring(L, e->d_name);
    lua_rawseti(L, -2, i++);
  }
  closedir(d);
#endif
  return 1;
}

/* --------------------------------------------------------------- sockets */

static const char *sock_error(void) {
#if defined(_WIN32)
  static char buf[64];
  snprintf(buf, sizeof(buf), "socket error %d", WSAGetLastError());
  return buf;
#else
  return strerror(errno);
#endif
}

static int sock_would_timeout(void) {
#if defined(_WIN32)
  int e = WSAGetLastError();
  return e == WSAETIMEDOUT || e == WSAEWOULDBLOCK;
#else
  return errno == EAGAIN || errno == EWOULDBLOCK;
#endif
}

static wc_sock check_sock(lua_State *L, int idx) {
  return (wc_sock)luaL_checkinteger(L, idx);
}

/* tcp_listen(host, port [, backlog]) -> fd | nil, err */
static int n_tcp_listen(lua_State *L) {
  const char *host = luaL_optstring(L, 1, "127.0.0.1");
  lua_Integer port = luaL_checkinteger(L, 2);
  int backlog = (int)luaL_optinteger(L, 3, 64);
  char portstr[16];
  struct addrinfo hints, *res = NULL, *ai;
  wc_sock s = WC_BADSOCK;

  snprintf(portstr, sizeof(portstr), "%d", (int)port);
  memset(&hints, 0, sizeof(hints));
  hints.ai_family = AF_UNSPEC;
  hints.ai_socktype = SOCK_STREAM;
  hints.ai_flags = AI_PASSIVE;
  if (getaddrinfo(host, portstr, &hints, &res) != 0 || !res) {
    lua_pushnil(L);
    lua_pushfstring(L, "cannot resolve %s", host);
    return 2;
  }
  for (ai = res; ai; ai = ai->ai_next) {
    s = socket(ai->ai_family, ai->ai_socktype, ai->ai_protocol);
    if (s == WC_BADSOCK) continue;
    int one = 1;
#if defined(_WIN32)
    setsockopt(s, SOL_SOCKET, SO_EXCLUSIVEADDRUSE, (const char *)&one, sizeof(one));
#else
    setsockopt(s, SOL_SOCKET, SO_REUSEADDR, &one, sizeof(one));
#endif
    if (bind(s, ai->ai_addr, (int)ai->ai_addrlen) == 0 && listen(s, backlog) == 0) break;
    wc_closesock(s);
    s = WC_BADSOCK;
  }
  freeaddrinfo(res);
  if (s == WC_BADSOCK) {
    lua_pushnil(L);
    lua_pushfstring(L, "cannot listen on %s:%d (%s)", host, (int)port, sock_error());
    return 2;
  }
  lua_pushinteger(L, (lua_Integer)s);
  return 1;
}

/* tcp_accept(fd) -> clientfd, ip | nil, err */
static int n_tcp_accept(lua_State *L) {
  wc_sock s = check_sock(L, 1);
  struct sockaddr_storage addr;
  socklen_t len = sizeof(addr);
  wc_sock c;
  for (;;) {
    c = accept(s, (struct sockaddr *)&addr, &len);
#if !defined(_WIN32)
    if (c == WC_BADSOCK && errno == EINTR) continue;
#endif
    break;
  }
  if (c == WC_BADSOCK) {
    lua_pushnil(L);
    lua_pushstring(L, sock_would_timeout() ? "again" : sock_error());
    return 2;
  }
#if defined(__APPLE__)
  { int one = 1; setsockopt(c, SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof(one)); }
#endif
  { int one = 1; setsockopt(c, IPPROTO_TCP, TCP_NODELAY, (const char *)&one, sizeof(one)); }
  char ip[INET6_ADDRSTRLEN] = "";
  if (addr.ss_family == AF_INET)
    inet_ntop(AF_INET, &((struct sockaddr_in *)&addr)->sin_addr, ip, sizeof(ip));
  else if (addr.ss_family == AF_INET6)
    inet_ntop(AF_INET6, &((struct sockaddr_in6 *)&addr)->sin6_addr, ip, sizeof(ip));
  lua_pushinteger(L, (lua_Integer)c);
  lua_pushstring(L, ip);
  return 2;
}

/* sock_timeout(fd, seconds) — applies to both receive and send */
static int n_sock_timeout(lua_State *L) {
  wc_sock s = check_sock(L, 1);
  double secs = luaL_checknumber(L, 2);
#if defined(_WIN32)
  DWORD ms = (DWORD)(secs * 1000.0);
  setsockopt(s, SOL_SOCKET, SO_RCVTIMEO, (const char *)&ms, sizeof(ms));
  setsockopt(s, SOL_SOCKET, SO_SNDTIMEO, (const char *)&ms, sizeof(ms));
#else
  struct timeval tv;
  tv.tv_sec = (time_t)secs;
  tv.tv_usec = (suseconds_t)((secs - (double)tv.tv_sec) * 1e6);
  setsockopt(s, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
  setsockopt(s, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));
#endif
  return 0;
}

/* sock_recv(fd, max) -> data | nil, "timeout" | "closed" | err */
static int n_sock_recv(lua_State *L) {
  wc_sock s = check_sock(L, 1);
  lua_Integer max = luaL_optinteger(L, 2, 65536);
  luaL_argcheck(L, max > 0 && max <= 1048576, 2, "size out of range");
  luaL_Buffer b;
  char *p = luaL_buffinitsize(L, &b, (size_t)max);
  int n;
  for (;;) {
    n = (int)recv(s, p, (int)max, 0);
#if !defined(_WIN32)
    if (n < 0 && errno == EINTR) continue;
#endif
    break;
  }
  if (n > 0) {
    luaL_pushresultsize(&b, (size_t)n);
    return 1;
  }
  lua_pushnil(L);
  if (n == 0) lua_pushstring(L, "closed");
  else if (sock_would_timeout()) lua_pushstring(L, "again");
  else lua_pushstring(L, sock_error());
  return 2;
}

/* sock_send(fd, data [, i]) -> next_i | next_i, "again" | nil, err
 * Sends data starting at byte i (1-based). Returns the index of the first
 * byte not yet sent (len+1 when done). On a non-blocking socket that can't
 * take more right now, returns that index plus "again". */
static int n_sock_send(lua_State *L) {
  wc_sock s = check_sock(L, 1);
  size_t len;
  const char *data = luaL_checklstring(L, 2, &len);
  lua_Integer start = luaL_optinteger(L, 3, 1);
  luaL_argcheck(L, start >= 1 && (size_t)start <= len + 1, 3, "index out of range");
  size_t sent = (size_t)start - 1;
#if defined(__linux__)
  int flags = MSG_NOSIGNAL;
#else
  int flags = 0;
#endif
  while (sent < len) {
    int chunk = (len - sent) > 1048576 ? 1048576 : (int)(len - sent);
    int n = (int)send(s, data + sent, chunk, flags);
    if (n < 0) {
#if !defined(_WIN32)
      if (errno == EINTR) continue;
#endif
      if (sock_would_timeout()) {
        lua_pushinteger(L, (lua_Integer)sent + 1);
        lua_pushliteral(L, "again");
        return 2;
      }
      lua_pushnil(L);
      lua_pushstring(L, sock_error());
      return 2;
    }
    sent += (size_t)n;
  }
  lua_pushinteger(L, (lua_Integer)sent + 1);
  return 1;
}

/* sock_nonblock(fd, on) */
static int n_sock_nonblock(lua_State *L) {
  wc_sock s = check_sock(L, 1);
  int on = lua_toboolean(L, 2);
#if defined(_WIN32)
  u_long mode = on ? 1 : 0;
  ioctlsocket(s, FIONBIO, &mode);
#else
  int flags = fcntl(s, F_GETFL, 0);
  if (flags >= 0) fcntl(s, F_SETFL, on ? (flags | O_NONBLOCK) : (flags & ~O_NONBLOCK));
#endif
  return 0;
}

/* poll({fd, ...}, {"r"|"w"|"rw", ...}, timeout_ms) -> { revents, ... } | nil, err
 * Each result is a string containing "r" (readable), "w" (writable) and/or
 * "e" (error/hang-up), or "" when nothing happened for that socket. */
static int n_poll(lua_State *L) {
  luaL_checktype(L, 1, LUA_TTABLE);
  luaL_checktype(L, 2, LUA_TTABLE);
  int timeout = (int)luaL_optinteger(L, 3, -1);
  int n = (int)luaL_len(L, 1);
  if (n > 4096) return luaL_error(L, "too many sockets to poll");
#if defined(_WIN32)
  WSAPOLLFD *pfd = (WSAPOLLFD *)lua_newuserdatauv(L, sizeof(WSAPOLLFD) * (size_t)(n > 0 ? n : 1), 0);
#else
  struct pollfd *pfd = (struct pollfd *)lua_newuserdatauv(L, sizeof(struct pollfd) * (size_t)(n > 0 ? n : 1), 0);
#endif
  for (int i = 0; i < n; i++) {
    lua_rawgeti(L, 1, i + 1);
    pfd[i].fd = (wc_sock)lua_tointeger(L, -1);
    lua_pop(L, 1);
    lua_rawgeti(L, 2, i + 1);
    const char *ev = lua_tostring(L, -1);
    pfd[i].events = 0;
    pfd[i].revents = 0;
    if (ev && strchr(ev, 'r')) pfd[i].events |= POLLIN;
    if (ev && strchr(ev, 'w')) pfd[i].events |= POLLOUT;
    lua_pop(L, 1);
  }
  int r;
#if defined(_WIN32)
  if (n == 0) { Sleep(timeout < 0 ? 0 : (DWORD)timeout); r = 0; }
  else r = WSAPoll(pfd, (ULONG)n, timeout);
#else
  do { r = poll(pfd, (nfds_t)n, timeout); } while (r < 0 && errno == EINTR);
#endif
  if (r < 0) {
    lua_pushnil(L);
    lua_pushstring(L, sock_error());
    return 2;
  }
  lua_createtable(L, n, 0);
  for (int i = 0; i < n; i++) {
    char out[4];
    int k = 0;
    if (pfd[i].revents & POLLIN) out[k++] = 'r';
    if (pfd[i].revents & POLLOUT) out[k++] = 'w';
    if (pfd[i].revents & (POLLERR | POLLHUP | POLLNVAL)) out[k++] = 'e';
    lua_pushlstring(L, out, (size_t)k);
    lua_rawseti(L, -2, i + 1);
  }
  return 1;
}

static int n_sock_close(lua_State *L) {
  wc_sock s = check_sock(L, 1);
#if defined(_WIN32)
  shutdown(s, SD_SEND);
#else
  shutdown(s, SHUT_WR);
#endif
  wc_closesock(s);
  return 0;
}

/* ----------------------------------------------------------------- module */

static const luaL_Reg native_funcs[] = {
  {"now", n_now},
  {"uptime", n_uptime},
  {"unixtime", n_unixtime},
  {"sleep", n_sleep},
  {"platform", n_platform},
  {"exe_path", n_exe_path},
  {"getpid", n_getpid},
  {"environ", n_environ},
  {"stdio_binary", n_stdio_binary},
  {"random_bytes", n_random_bytes},
  {"stat", n_stat},
  {"mkdir", n_mkdir},
  {"remove", n_remove},
  {"listdir", n_listdir},
  {"tcp_listen", n_tcp_listen},
  {"tcp_accept", n_tcp_accept},
  {"sock_timeout", n_sock_timeout},
  {"sock_recv", n_sock_recv},
  {"sock_send", n_sock_send},
  {"sock_close", n_sock_close},
  {"sock_nonblock", n_sock_nonblock},
  {"poll", n_poll},
  {NULL, NULL}
};

int luaopen_wc_native(lua_State *L) {
#if defined(_WIN32)
  static int wsa_started = 0;
  if (!wsa_started) {
    WSADATA wsa;
    if (WSAStartup(MAKEWORD(2, 2), &wsa) == 0) wsa_started = 1;
  }
#endif
  luaL_newlib(L, native_funcs);
  lua_pushstring(L, WC_PLATFORM);
  lua_setfield(L, -2, "os");
  lua_pushstring(L, WC_ARCH);
  lua_setfield(L, -2, "arch");
#if defined(_WIN32)
  lua_pushstring(L, "\\");
#else
  lua_pushstring(L, "/");
#endif
  lua_setfield(L, -2, "sep");
  return 1;
}
