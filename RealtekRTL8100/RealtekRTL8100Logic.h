#ifndef REALTEK_RTL8100_LOGIC_H
#define REALTEK_RTL8100_LOGIC_H

#include <stddef.h>
#include <stdint.h>

#define RTL8100_ETHER_HDR_LEN 14
#define RTL8100_IP6_HDR_LEN 40
#define RTL8100_TCP_HDR_LEN 20
#define RTL8100_MC_FILTER_LIMIT 32

static inline uint32_t rtl8100EtherCRC(int length, const unsigned char *data)
{
    uint32_t crc = 0xffffffffU;

    while (--length >= 0) {
        unsigned char current_octet = *data++;
        int bit;

        for (bit = 0; bit < 8; bit++, current_octet >>= 1) {
            uint32_t top = crc >> 31;

            crc = (crc << 1) ^ ((top ^ (current_octet & 1)) ? 0x04c11db7U : 0);
        }
    }
    return crc;
}

static inline uint64_t rtl8100MulticastFilter(const unsigned char *addrs, uint32_t count)
{
    uint64_t filter = 0;
    uint32_t i;

    if (count > RTL8100_MC_FILTER_LIMIT)
        return ~(uint64_t)0;

    for (i = 0; i < count; i++, addrs += 6) {
        uint32_t bitNumber = rtl8100EtherCRC(6, addrs) >> 26;

        filter |= ((uint64_t)1 << (bitNumber & 0x3f));
    }
    return filter;
}

static inline uint16_t rtl8100ReadBE16(const unsigned char *p)
{
    return (uint16_t)(((uint16_t)p[0] << 8) | p[1]);
}

static inline void rtl8100WriteBE16(unsigned char *p, uint16_t value)
{
    p[0] = (unsigned char)(value >> 8);
    p[1] = (unsigned char)value;
}

static inline int rtl8100AdjustIPv6Header(void *packet, size_t length, uint32_t *adjustedLength)
{
    unsigned char *data = (unsigned char *)packet;
    unsigned char *ip6;
    unsigned char *tcp;
    uint32_t plen;
    uint32_t csum;

    if (!data || length < (size_t)(RTL8100_ETHER_HDR_LEN + RTL8100_IP6_HDR_LEN + RTL8100_TCP_HDR_LEN))
        return 0;

    ip6 = data + RTL8100_ETHER_HDR_LEN;
    tcp = ip6 + RTL8100_IP6_HDR_LEN;
    plen = rtl8100ReadBE16(ip6 + 4);
    csum = rtl8100ReadBE16(tcp + 16) - plen;
    csum += (csum >> 16);
    rtl8100WriteBE16(ip6 + 4, 0);
    rtl8100WriteBE16(tcp + 16, (uint16_t)csum);

    if (adjustedLength)
        *adjustedLength = plen + RTL8100_ETHER_HDR_LEN + RTL8100_IP6_HDR_LEN;
    return 1;
}

#endif
