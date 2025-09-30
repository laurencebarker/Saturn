#ifndef SATURN_BYTEIO_H
#define SATURN_BYTEIO_H

#include <stdint.h>
#include <string.h>   // memcpy
#include <arpa/inet.h> // htons/htonl/ntohs/ntohl

#if defined(__GNUC__) || defined(__clang__)
  #define SATURN_INLINE static __inline__ __attribute__((always_inline))
#else
  #define SATURN_INLINE static inline
#endif

/*
 * Safe byte I/O helpers for unaligned memory access in network packets.
 * These functions use memcpy to avoid undefined behavior from casting
 * unaligned pointers, which can cause performance/odd behavior issues
 * or even crashes on ARM architectures.
 */

/* Read big-endian values from potentially unaligned buffers */
SATURN_INLINE uint16_t rd_be_u16(const void *p) {
    uint16_t v;
    memcpy(&v, p, sizeof(v));
    return ntohs(v);
}

SATURN_INLINE uint32_t rd_be_u32(const void *p) {
    uint32_t v;
    memcpy(&v, p, sizeof(v));
    return ntohl(v);
}

/* Read little-endian values from potentially unaligned buffers */
SATURN_INLINE uint16_t rd_le_u16(const void *p) {
    uint16_t v;
    memcpy(&v, p, sizeof(v));
    return v; // Already in host byte order
}

SATURN_INLINE uint32_t rd_le_u32(const void *p) {
    uint32_t v;
    memcpy(&v, p, sizeof(v));
    return v; // Already in host byte order
}

/* Write big-endian values to potentially unaligned buffers */
SATURN_INLINE void wr_be_u16(void *p, uint16_t val) {
    uint16_t v = htons(val);
    memcpy(p, &v, sizeof(v));
}

SATURN_INLINE void wr_be_u32(void *p, uint32_t val) {
    uint32_t v = htonl(val);
    memcpy(p, &v, sizeof(v));
}

/* Write little-endian values to potentially unaligned buffers */
SATURN_INLINE void wr_le_u16(void *p, uint16_t val) {
    memcpy(p, &val, sizeof(val));
}

SATURN_INLINE void wr_le_u32(void *p, uint32_t val) {
    memcpy(p, &val, sizeof(val));
}

#endif /* SATURN_BYTEIO_H */